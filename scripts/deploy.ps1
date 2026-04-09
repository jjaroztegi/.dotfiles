#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OriginalUserProfile,
    [string]$OriginalAppData,
    [string]$OriginalLocalAppData,
    [switch]$OnlyProtectedPaths,
    [switch]$ContinueOnAccessDenied
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path (Join-Path $PSScriptRoot 'lib') 'ManifestHelpers.psm1'
if (-not (Test-Path $modulePath)) {
    throw "Module not found: $modulePath"
}
Import-Module $modulePath -Force

# Ensure logging utility is available; ManifestHelpers may import it, but we require it explicitly here.
Import-Module (Join-Path $PSScriptRoot 'lib' 'Common.psm1') -Force

function Initialize-HomeVariable {
    <#
    .SYNOPSIS
        Ensures HOME environment variable exists and is valid.
    #>

    if ($OriginalUserProfile) {
        Write-LogInfo "Restoring user context for deployment: $OriginalUserProfile"
        $env:USERPROFILE = $OriginalUserProfile
        $env:HOME = $OriginalUserProfile
        $env:APPDATA = $OriginalAppData
        $env:LOCALAPPDATA = $OriginalLocalAppData
    }

    $currentHome = [Environment]::GetEnvironmentVariable('HOME', 'User')

    if ([string]::IsNullOrWhiteSpace($currentHome)) {
        $newHome = $env:USERPROFILE

        if (-not (Test-Path $newHome -PathType Container)) {
            Write-LogError "USERPROFILE path does not exist: $newHome"
            throw "USERPROFILE path does not exist: $newHome"
        }

        Write-LogInfo "Setting HOME environment variable to: $newHome"
        try {
            [Environment]::SetEnvironmentVariable('HOME', $newHome, 'User')
        }
        catch {
            Write-LogWarn "Unable to persist HOME to the user environment. Continuing for the current session only."
        }
        $env:HOME = $newHome

    }
    elseif (-not (Test-Path $currentHome -PathType Container)) {
        Write-LogWarn "HOME is set to non-existent path: $currentHome"
        Write-LogWarn "Continuing with USERPROFILE: $env:USERPROFILE"
        $env:HOME = $env:USERPROFILE

    }
    else {
        Write-LogOK "HOME already set to: $currentHome"
        if ([string]::IsNullOrWhiteSpace($env:HOME)) {
            $env:HOME = $currentHome
        }
    }
}

try {
    Initialize-HomeVariable

    $scriptRoot = $PSScriptRoot
    if (-not $scriptRoot) {
        $scriptRoot = $MyInvocation.MyCommand.Path | Split-Path -Parent
    }
    if (-not $scriptRoot) {
        $scriptRoot = $PWD.Path
    }

    if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
        throw "Could not determine script root directory."
    }

    # Manifest is in ../manifests/windows.manifest
    $manifestPath = Join-Path (Split-Path $scriptRoot -Parent) 'manifests' 'windows.manifest'

    if (-not (Test-Path $manifestPath)) {
        Write-LogError "Manifest not found: $manifestPath"
        throw "Manifest not found: $manifestPath"
    }

    $deployParams = @{
        ManifestFile = $manifestPath
    }
    if ($PSBoundParameters.ContainsKey('WhatIf')) {
        $deployParams['WhatIf'] = $true
    }
    if ($OnlyProtectedPaths) {
        $deployParams['OnlyProtectedPaths'] = $true
    }
    if ($ContinueOnAccessDenied) {
        $deployParams['ContinueOnAccessDenied'] = $true
    }

    $summary = Deploy-Manifest @deployParams
    if ($summary -and $summary.SkippedAccess -and $summary.SkippedAccess.Count -gt 0) {
        Write-LogWarn "Skipped $($summary.SkippedAccess.Count) entries due to access denied."
        foreach ($entry in $summary.SkippedAccess) {
            Write-LogWarn "  - $($entry.Source) -> $($entry.Destination)"
        }
    }

    Write-LogOK "`nDeployment completed successfully!"

}
catch {
    Write-LogError "Deployment failed at line $($_.InvocationInfo.ScriptLineNumber): $_"
    exit 1
}
