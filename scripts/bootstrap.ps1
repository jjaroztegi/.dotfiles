param(
    [string]$OriginalUserProfile,
    [string]$OriginalAppData,
    [string]$OriginalLocalAppData
)

$ErrorActionPreference = 'Stop'

$modulesDir = Join-Path $PSScriptRoot "modules"
$libDir = Join-Path $PSScriptRoot "lib"
$env:PSModulePath = $libDir + [IO.Path]::PathSeparator + $env:PSModulePath

Import-Module (Join-Path $libDir "Common.psm1") -Force

# Restore original user profile when running elevated
if ($OriginalUserProfile) {
    Write-LogInfo "Restoring original user context: $OriginalUserProfile"
    $env:USERPROFILE = $OriginalUserProfile
    $env:HOME = $OriginalUserProfile
    $env:APPDATA = $OriginalAppData
    $env:LOCALAPPDATA = $OriginalLocalAppData
}

# Enforce TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-LogWarn "Winget not found. Installing via winget-install.ps1..."

    $installScript = Join-Path $PSScriptRoot "winget-install.ps1"

    if (Test-Path $installScript) {
        Write-LogInfo "Executing $installScript..."
        & $installScript -Force -Wait
        Update-Path
    }
    else {
        Write-LogWarn "winget-install.ps1 not found. Skipping Winget bootstrap."
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-LogWarn "Running on legacy PowerShell ($($PSVersionTable.PSVersion)). Checking for PowerShell 7..."

    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-LogInfo "PowerShell 7 not found. Installing..."

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-LogInfo "Installing PowerShell 7 via Winget..."
            winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent
        }
        else {
            Write-LogInfo "Installing PowerShell 7 via Direct MSI Download..."
            try {
                $releaseUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
                $release = Invoke-RestMethod -Uri $releaseUrl
                $asset = $release.assets | Where-Object { $_.name -like "PowerShell-*-win-x64.msi" } | Select-Object -First 1

                if (-not $asset) { throw "Could not find PowerShell MSI asset from GitHub." }

                $msiUrl = $asset.browser_download_url
                $msiPath = "$env:TEMP\$($asset.name)"

                Write-LogInfo "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 2)) MB)..."

                if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
                    Start-BitsTransfer -Source $msiUrl -Destination $msiPath -ErrorAction Stop
                }
                else {
                    $ProgressPreference = 'SilentlyContinue'
                    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath
                    $ProgressPreference = 'Continue'
                }

                Write-LogInfo "Installing MSI..."
                $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait -PassThru

                if ($proc.ExitCode -ne 0) {
                    throw "MSI installation failed with exit code $($proc.ExitCode)"
                }

                Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
                Write-LogOK "PowerShell 7 installed successfully."
            }
            catch {
                Write-LogError "Failed to install PowerShell 7: $_"
                exit 1
            }
        }

        Update-Path

        if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Write-LogError "Failed to verify PowerShell 7 installation."
            exit 1
        }
    }

    Write-LogOK "Restarting script in PowerShell 7..."
    $scriptArgs = @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    if ($OriginalUserProfile) {
        $scriptArgs += @("-OriginalUserProfile", "`"$OriginalUserProfile`"", "-OriginalAppData", "`"$OriginalAppData`"", "-OriginalLocalAppData", "`"$OriginalLocalAppData`"")
    }
    Start-Process pwsh -ArgumentList $scriptArgs
    exit
}

if (-not (Test-IsAdmin)) {
    Write-LogWarn "Running as standard user. System installations require Admin privileges."

    $choice = Read-Host "Do you want to restart with Administrator privileges? (y/N)"
    if ($choice -match '^[Yy]$') {
        $exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
        Write-LogInfo "Restarting elevated..."

        $scriptArgs = @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
        # Pass current user context to the admin process
        $scriptArgs += @("-OriginalUserProfile", "`"$env:USERPROFILE`"", "-OriginalAppData", "`"$env:APPDATA`"", "-OriginalLocalAppData", "`"$env:LOCALAPPDATA`"")

        Start-Process $exe -ArgumentList $scriptArgs -Verb RunAs
        exit
    }
}

Import-Module (Join-Path $modulesDir "Install-PackageManagers.psm1") -Force
Import-Module (Join-Path $modulesDir "Install-DevTools.psm1") -Force
Import-Module (Join-Path $modulesDir "Install-Fonts.psm1") -Force
Import-Module (Join-Path $modulesDir "Install-PowerShellModules.psm1") -Force
Import-Module (Join-Path $modulesDir "Configure-WindowsTerminal.psm1") -Force

try {
    Write-LogInfo "Starting Setup..."

    if (-not (Test-InternetConnection)) {
        throw "Internet connection required."
    }

    Install-PackageManagers
    Install-DevTools
    Install-NerdFonts

    Install-PowerShellModules -Modules @("Terminal-Icons", "posh-git", "PSFzf")

    Write-LogInfo "`n--- Deploying Dotfiles ---"
    $deployParams = @{}
    if ($OriginalUserProfile) {
        $deployParams['OriginalUserProfile'] = $OriginalUserProfile
        $deployParams['OriginalAppData'] = $OriginalAppData
        $deployParams['OriginalLocalAppData'] = $OriginalLocalAppData
    }
    & (Join-Path $PSScriptRoot "deploy.ps1") @deployParams

    Write-LogInfo "`n--- Configuring Windows Terminal ---"
    Set-WindowsTerminalDefaults

    Write-LogOK "`nSetup Completed Successfully!"
    Write-LogInfo "Please restart your terminal."

}
catch {
    Write-LogError "Setup failed: $_"
    exit 1
}
