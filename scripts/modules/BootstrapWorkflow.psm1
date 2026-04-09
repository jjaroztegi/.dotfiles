Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\Common.psm1") -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\SetupEnvironment.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Install-PackageManagers.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Install-DevTools.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Install-Fonts.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Install-PowerShellModules.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Configure-WindowsTerminal.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "RuntimeTooling.psm1") -Force

function Invoke-ManagedRuntimeMaintenance {
    Write-LogInfo "`n--- Configuring Runtime Tooling ---"
    Invoke-RuntimeToolingSetup -Execute
}

function Invoke-UserSetupPhase {
    param([string]$ScriptsRoot)

    Write-LogInfo "Starting user setup..."

    if (-not (Test-InternetConnection)) {
        throw "Internet connection required."
    }

    Install-PackageManagers
    Write-LogInfo "Managed package installation is deferred to the admin phase on Windows."
    Invoke-ManagedRuntimeMaintenance

    Write-LogInfo "Nerd Font installation is deferred to the admin phase on Windows."
    Install-PowerShellModules -Modules @("Terminal-Icons", "posh-git", "PSFzf")

    Write-LogInfo "`n--- Deploying Dotfiles ---"
    & (Join-Path $ScriptsRoot "deploy.ps1") -ContinueOnAccessDenied

    Write-LogInfo "`n--- Configuring Windows Terminal ---"
    Set-WindowsTerminalDefaults

    Update-StandardPaths -IsAdmin (Test-IsAdmin) | Out-Null
    Write-LogOK "`nUser setup completed successfully."
}

function Invoke-AdminSetupPhase {
    param([string]$ScriptsRoot)

    Write-LogInfo "Starting admin setup..."

    if (-not (Test-InternetConnection)) {
        throw "Internet connection required."
    }

    $excludedPackageKeys = [System.Collections.Generic.List[string]]::new()
    $excludedPackageKeys.Add('pyenv-win') | Out-Null
    if (-not (Test-InteractiveSession)) {
        Write-LogWarn "Ghostscript and MSYS2 installation are skipped in non-interactive admin sessions because their installers can hang."
        $excludedPackageKeys.Add('ghostscript') | Out-Null
        $excludedPackageKeys.Add('msys2') | Out-Null
    }

    Install-PackageManagers
    Install-DevTools -Scope All -ExcludePackageKeys @($excludedPackageKeys)
    Install-NerdFonts

    Write-LogInfo "`n--- Deploying Protected Dotfiles ---"
    & (Join-Path $ScriptsRoot "deploy.ps1") -OnlyProtectedPaths

    Update-StandardPaths -IsAdmin $true | Out-Null
    Write-LogOK "`nAdmin setup completed successfully."
}

function Start-AdminElevationRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [string]$PreferredDrive,
        [string]$OriginalUserProfile,
        [string]$OriginalAppData,
        [string]$OriginalLocalAppData,
        [string]$LogPath,
        [switch]$AdminManifestOnly
    )

    Write-LogWarn "Running as standard user. System installations require admin privileges."
    if (-not (Test-InteractiveSession)) {
        Write-LogWarn "Interactive elevation is unavailable in this session. Re-run the admin phase from an elevated shell."
        return $false
    }

    $choice = Read-Host "Do you want to restart with Administrator privileges? (y/N)"
    if ($choice -notmatch '^[Yy]$') {
        return $false
    }

    $exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    Write-LogInfo "Restarting elevated..."

    $scriptArgs = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath, "-Phase", "Admin", "-AdminManifestOnly")
    $scriptArgs += @("-OriginalUserProfile", $OriginalUserProfile, "-OriginalAppData", $OriginalAppData, "-OriginalLocalAppData", $OriginalLocalAppData)

    if ($PreferredDrive) {
        $scriptArgs += @("-PreferredDrive", $PreferredDrive.ToUpperInvariant())
    }

    if ($LogPath) {
        $scriptArgs += @("-LogPath", $LogPath)
    }

    Stop-SetupTranscript
    Start-Process $exe -ArgumentList $scriptArgs -Verb RunAs
    return $true
}

function Show-BootstrapExitPrompt {
    Write-LogInfo "Please restart your terminal."
    Wait-BootstrapExit
}

function Start-DotfilesBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Phase,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [string]$PreferredDrive,
        [string]$OriginalUserProfile,
        [string]$OriginalAppData,
        [string]$OriginalLocalAppData,
        [string]$LogPath,
        [switch]$AdminManifestOnly
    )

    if ($PreferredDrive) {
        Set-PlacementOverride -PreferredDrive $PreferredDrive
        $env:DOTFILES_PREFERRED_DRIVE = $PreferredDrive.ToUpperInvariant()
    }

    $placement = Get-ManagedPlacement
    if ($placement.PreferredDrive) {
        Write-LogInfo "Preferred install drive: $($placement.PreferredDrive)"
    }
    else {
        Write-LogInfo "Preferred install drive: package manager defaults"
    }

    if ($OriginalUserProfile) {
        Write-LogInfo "Original user context: $OriginalUserProfile"
    }

    $scriptsRoot = Split-Path -Parent $ScriptPath
    $isAdmin = Test-IsAdmin

    switch ($Phase) {
        'User' {
            Invoke-UserSetupPhase -ScriptsRoot $scriptsRoot
            Stop-SetupTranscript
            Show-BootstrapExitPrompt
        }
        'Admin' {
            if (-not $isAdmin) {
                if (Start-AdminElevationRequest -ScriptPath $ScriptPath -PreferredDrive $PreferredDrive -OriginalUserProfile $OriginalUserProfile -OriginalAppData $OriginalAppData -OriginalLocalAppData $OriginalLocalAppData -LogPath $LogPath -AdminManifestOnly:$AdminManifestOnly) {
                    return
                }

                throw "Administrator privileges are required to run the admin phase."
            }

            Invoke-AdminSetupPhase -ScriptsRoot $scriptsRoot
            Stop-SetupTranscript
            Show-BootstrapExitPrompt
        }
        default {
            Invoke-UserSetupPhase -ScriptsRoot $scriptsRoot

            if ($isAdmin) {
                Invoke-AdminSetupPhase -ScriptsRoot $scriptsRoot
            }
            else {
                $elevationStarted = Start-AdminElevationRequest -ScriptPath $ScriptPath -PreferredDrive $PreferredDrive -OriginalUserProfile $env:USERPROFILE -OriginalAppData $env:APPDATA -OriginalLocalAppData $env:LOCALAPPDATA -LogPath $LogPath -AdminManifestOnly:$AdminManifestOnly
                if ($elevationStarted) {
                    return
                }

                Write-LogWarn "Admin phase was not started. Re-run the bootstrap from an elevated shell to finish machine-level setup."
            }

            Stop-SetupTranscript
            Show-BootstrapExitPrompt
        }
    }
}

Export-ModuleMember -Function Start-DotfilesBootstrap
