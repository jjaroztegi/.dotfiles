Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\Common.psm1") -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\SetupEnvironment.psm1") -Force

function Get-UserShimRoot {
    return (Join-Path $env:USERPROFILE ".local\bin")
}

function Get-UserPyenvRoot {
    return (Join-Path $env:USERPROFILE ".pyenv\pyenv-win")
}

function Get-FnmDefaultAliasRoot {
    return (Join-Path $env:APPDATA "fnm\aliases\default")
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FilePath $($Arguments -join ' ')"
    }
}

function Get-TrimmedLines {
    param([object[]]$InputObject)

    return @(
        $InputObject |
            ForEach-Object { "$_".Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-HighestVersionMatch {
    param(
        [string[]]$Candidates,
        [string]$MajorMinor
    )

    $matching = @(
        $Candidates |
            Where-Object { $_ -match ('^{0}\.\d+$' -f [regex]::Escape($MajorMinor)) } |
            Sort-Object { [version]$_ }
    )

    if ($matching.Count -gt 0) {
        return $matching[-1]
    }

    return $null
}

function Set-CommandWrapperContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $existing = if (Test-Path $Path -PathType Leaf) { Get-Content $Path -Raw } else { $null }
    if ($existing -ceq $Content) {
        return $false
    }

    Set-Content -Path $Path -Value $Content -Encoding ASCII
    return $true
}

function Update-FnmCommandWrappers {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Commands,
        [switch]$Apply
    )

    $shimRoot = Get-UserShimRoot
    if (-not (Test-Path $shimRoot -PathType Container)) {
        New-Item -Path $shimRoot -ItemType Directory -Force | Out-Null
    }

    $aliasRoot = Get-FnmDefaultAliasRoot
    foreach ($command in $Commands) {
        $targetPath = switch ($command) {
            'node' { Join-Path $aliasRoot 'node.exe' }
            'npm' { Join-Path $aliasRoot 'npm.cmd' }
            'npx' { Join-Path $aliasRoot 'npx.cmd' }
            'corepack' { Join-Path $aliasRoot 'corepack.cmd' }
            default { throw "Unsupported Node runtime wrapper target: $command" }
        }

        if (-not (Test-Path $targetPath -PathType Leaf)) {
            throw "Unable to resolve fnm default alias target for $command at $targetPath"
        }

        $quotedTargetPath = '"' + $targetPath + '"'
        $cmdWrapperPath = Join-Path $shimRoot ("{0}.cmd" -f $command)
        $cmdWrapper = @"
@echo off
setlocal
$quotedTargetPath %*
set "exitCode=%ERRORLEVEL%"
endlocal & exit /b %exitCode%
"@

        $ps1WrapperPath = Join-Path $shimRoot ("{0}.ps1" -f $command)
        $ps1Wrapper = @"
& $quotedTargetPath @args
exit `$LASTEXITCODE
"@

        if ($Apply) {
            $cmdUpdated = Set-CommandWrapperContent -Path $cmdWrapperPath -Content $cmdWrapper
            $ps1Updated = Set-CommandWrapperContent -Path $ps1WrapperPath -Content $ps1Wrapper
            if ($cmdUpdated -or $ps1Updated) {
                Write-LogInfo "Updated fnm wrapper for $command in $shimRoot"
            }
            else {
                Write-LogSkip "fnm wrapper for $command is already current."
            }
        }
        else {
            Write-LogDryRun "Would register fnm wrappers for $command in $shimRoot"
        }
    }
}

function Set-NodeRuntimeState {
    param([switch]$Apply)

    $runtimePolicy = (Get-RuntimePolicy).node
    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        throw "fnm is required but not installed."
    }

    $fnmPath = (Get-Command fnm -ErrorAction Stop).Source
    if (-not $fnmPath) {
        $fnmPath = (Get-Command fnm -ErrorAction Stop).Path
    }

    if ($Apply) {
        Write-LogInfo "Ensuring Node.js $($runtimePolicy.channel) v$($runtimePolicy.version) via fnm..."
        Invoke-ExternalCommand -FilePath $fnmPath -Arguments @('install', $runtimePolicy.version)
        Invoke-ExternalCommand -FilePath $fnmPath -Arguments @('default', $runtimePolicy.version)
    }
    else {
        Write-LogDryRun "Would install/set default Node.js $($runtimePolicy.version) via fnm"
    }

    Update-FnmCommandWrappers -Commands @($runtimePolicy.commands) -Apply:$Apply
}

function Set-PythonRuntimeState {
    param([switch]$Apply)

    $runtimePolicy = (Get-RuntimePolicy).python
    if (-not (Get-Command pyenv -ErrorAction SilentlyContinue)) {
        throw "pyenv-win is required but not installed."
    }

    $pyenvPath = (Get-Command pyenv -ErrorAction Stop).Source
    if (-not $pyenvPath) {
        $pyenvPath = (Get-Command pyenv -ErrorAction Stop).Path
    }

    $installedVersions = Get-TrimmedLines -InputObject (& $pyenvPath versions --bare 2>$null)
    $selectedVersion = Get-HighestVersionMatch -Candidates $installedVersions -MajorMinor $runtimePolicy.majorMinor

    if (-not $selectedVersion) {
        $availableVersions = Get-TrimmedLines -InputObject (& $pyenvPath install --list 2>$null)
        $selectedVersion = Get-HighestVersionMatch -Candidates $availableVersions -MajorMinor $runtimePolicy.majorMinor
    }

    if (-not $selectedVersion) {
        $selectedVersion = $runtimePolicy.fallbackExactVersion
    }

    if ([string]::IsNullOrWhiteSpace($selectedVersion)) {
        throw "Unable to resolve a supported pyenv-win Python version for $($runtimePolicy.majorMinor)."
    }

    $pyenvBin = Join-Path (Get-UserPyenvRoot) "bin"
    $pyenvShims = Join-Path (Get-UserPyenvRoot) "shims"

    if ($Apply) {
        if (-not ($installedVersions -contains $selectedVersion)) {
            Write-LogInfo "Installing Python $selectedVersion via pyenv-win..."
            Invoke-ExternalCommand -FilePath $pyenvPath -Arguments @('install', $selectedVersion)
        }

        Write-LogInfo "Setting pyenv-win global Python to $selectedVersion..."
        Invoke-ExternalCommand -FilePath $pyenvPath -Arguments @('global', $selectedVersion)
        [void](Add-PathEntry -Entry $pyenvBin -Scope User)
        [void](Add-PathEntry -Entry $pyenvShims -Scope User)
    }
    else {
        Write-LogDryRun "Would ensure pyenv-win Python $selectedVersion and register $pyenvBin / $pyenvShims in user PATH"
    }
}

function Invoke-RuntimeToolingSetup {
    [CmdletBinding()]
    param([switch]$Execute)

    Write-LogInfo "Applying runtime policy..."
    Set-NodeRuntimeState -Apply:$Execute
    Set-PythonRuntimeState -Apply:$Execute

    if ($Execute) {
        Update-StandardPaths -IsAdmin (Test-IsAdmin) | Out-Null
        Write-LogOK "Runtime tooling is configured."
    }
}

Export-ModuleMember -Function Invoke-RuntimeToolingSetup
