param(
    [string]$OriginalUserProfile,
    [string]$OriginalAppData,
    [string]$OriginalLocalAppData,
    [ValidatePattern('^[A-Za-z]:$')]
    [string]$PreferredDrive,
    [ValidateSet('Auto', 'User', 'Admin')]
    [string]$Phase = 'Auto',
    [switch]$AdminManifestOnly,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'

# Remote Bootstrapping
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    try {
        Write-Host "[INFO] No local script root detected. Bootstrapping repository..." -ForegroundColor Cyan

        $repoDir = Join-Path $HOME ".dotfiles"
        if (-not (Test-Path $repoDir)) {
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                Write-Host "[INFO] Git not found. Attempting to install via Winget..." -ForegroundColor Yellow
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    winget install --id Git.Git --source winget --accept-package-agreements --accept-source-agreements --silent
                    # Refresh path
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                }

                if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                    throw "Git is still missing after installation attempt. Please install Git manually."
                }
            }
            Write-Host "[INFO] Cloning repository to $repoDir..." -ForegroundColor Cyan
            git clone https://github.com/jjaroztegi/.dotfiles.git $repoDir
        }
        else {
            Write-Host "[INFO] Using existing repository at $repoDir" -ForegroundColor Cyan
        }

        $bootstrapPath = Join-Path (Join-Path $repoDir "scripts") "bootstrap.ps1"
        Write-Host "[INFO] Launching local bootstrap: $bootstrapPath" -ForegroundColor Cyan
        & $bootstrapPath @PSBoundParameters
        return
    }
    catch {
        Write-Host "[ERROR] Remote bootstrap failed: $_" -ForegroundColor Red
        Write-Host "`nPress any key to exit..." -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
        return
    }
}

$modulesDir = Join-Path $PSScriptRoot "modules"
$libDir = Join-Path $PSScriptRoot "lib"
$env:PSModulePath = $libDir + [IO.Path]::PathSeparator + $env:PSModulePath

Import-Module (Join-Path $libDir "Common.psm1") -Force
Import-Module (Join-Path $modulesDir "BootstrapWorkflow.psm1") -Force

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    if (-not [string]::IsNullOrWhiteSpace($env:DOTFILES_LOG_PATH)) {
        $LogPath = $env:DOTFILES_LOG_PATH
    }
    else {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $LogPath = Join-Path $env:TEMP "dotfiles-bootstrap-$timestamp.log"
    }
}
$env:DOTFILES_LOG_PATH = $LogPath
Start-SetupTranscript -LogPath $LogPath
Write-LogInfo "Log file: $LogPath"
Write-LogInfo ("Session: Phase={0} PID={1} PS={2} Admin={3}" -f $Phase, $PID, $PSVersionTable.PSVersion, (Test-IsAdmin))

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
                Write-Host "`nPress any key to exit..." -ForegroundColor Gray
                $null = [Console]::ReadKey($true)
                return
            }
        }

        Update-Path

        if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Write-LogError "Failed to verify PowerShell 7 installation."
            Write-Host "`nPress any key to exit..." -ForegroundColor Gray
            $null = [Console]::ReadKey($true)
            return
        }
    }

    Write-LogOK "Restarting script in PowerShell 7..."
    $scriptArgs = @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    if ($OriginalUserProfile) {
        $scriptArgs += @("-OriginalUserProfile", "`"$OriginalUserProfile`"", "-OriginalAppData", "`"$OriginalAppData`"", "-OriginalLocalAppData", "`"$OriginalLocalAppData`"")
    }
    if ($Phase) {
        $scriptArgs += @("-Phase", $Phase)
    }
    if ($PreferredDrive) {
        $scriptArgs += @("-PreferredDrive", $PreferredDrive.ToUpperInvariant())
    }
    if ($AdminManifestOnly) {
        $scriptArgs += "-AdminManifestOnly"
    }
    if ($LogPath) {
        $scriptArgs += @("-LogPath", "`"$LogPath`"")
    }
    Stop-SetupTranscript
    Start-Process pwsh -ArgumentList $scriptArgs
    exit
}

try {
    Write-LogInfo "Starting Setup..."
    Start-DotfilesBootstrap -Phase $Phase -ScriptPath $PSCommandPath -PreferredDrive $PreferredDrive -OriginalUserProfile $OriginalUserProfile -OriginalAppData $OriginalAppData -OriginalLocalAppData $OriginalLocalAppData -LogPath $LogPath -AdminManifestOnly:$AdminManifestOnly
}
catch {
    Write-LogError "Setup failed: $_"
    Stop-SetupTranscript
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
    return
}
