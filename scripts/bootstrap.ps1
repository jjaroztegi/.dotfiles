param(
    [string]$OriginalUserProfile,
    [string]$OriginalAppData,
    [string]$OriginalLocalAppData,
    [string]$PreferredDrive,
    [string]$Phase = 'Auto',
    [switch]$AdminManifestOnly,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($PreferredDrive) -and $PreferredDrive -notmatch '^[A-Za-z]:$') {
    throw "PreferredDrive must look like 'D:' or 'E:'."
}

$validPhases = @('Auto', 'User', 'Admin')
if ($Phase -notin $validPhases) {
    throw "Phase must be one of: $($validPhases -join ', ')."
}

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
        Wait-BootstrapExit
        return
    }
}

$modulesDir = Join-Path $PSScriptRoot "modules"
$libDir = Join-Path $PSScriptRoot "lib"
$env:PSModulePath = $libDir + [IO.Path]::PathSeparator + $env:PSModulePath

Import-Module (Join-Path $modulesDir "BootstrapWorkflow.psm1") -Force
Import-Module (Join-Path $libDir "Common.psm1") -Force

function Repair-BootstrapWingetSources {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return
    }

    try {
        Write-LogInfo "Resetting Winget sources..."
        winget source reset --force 2>&1 | Out-Null
    }
    catch {
        Write-LogWarn "Winget source reset failed. Continuing with current source state."
    }
}

function Install-PowerShell7FromMsi {
    Write-LogInfo "Installing PowerShell 7 via Direct MSI Download..."
    try {
        $releaseUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl
        $asset = $release.assets | Where-Object { $_.name -like "PowerShell-*-win-x64.msi" } | Select-Object -First 1

        if (-not $asset) { throw "Could not find PowerShell MSI asset from GitHub." }

        $msiUrl = $asset.browser_download_url
        $msiPath = "$env:TEMP\$($asset.name)"

        Write-LogInfo "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 2)) MB)..."

        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath
        $ProgressPreference = 'Continue'

        Write-LogInfo "Installing MSI..."
        $msiLogPath = Join-Path $env:TEMP "powershell-msi-install.log"
        $msiArgs = @('/i', "`"$msiPath`"", '/quiet', '/norestart', '/L*V', "`"$msiLogPath`"", 'ADD_PATH=1')
        if (-not (Test-IsAdmin)) {
            $msiArgs += @('ALLUSERS=2', 'MSIINSTALLPERUSER=1', 'ENABLE_PSREMOTING=0', 'USE_MU=0', 'ENABLE_MU=0')
        }

        $proc = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "MSI installation failed with exit code $($proc.ExitCode). Log: $msiLogPath"
        }

        Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        Write-LogOK "PowerShell 7 installed successfully."
        return $true
    }
    catch {
        Write-LogError "Failed to install PowerShell 7: $_"
        Wait-BootstrapExit
        return $false
    }
}

function Install-PowerShell7Portable {
    Write-LogInfo "Installing PowerShell 7 via portable ZIP..."
    try {
        $portableRoot = Join-Path $env:LOCALAPPDATA '.dotfiles-bootstrap\pwsh'
        $pwshPath = Join-Path $portableRoot 'pwsh.exe'

        if (Test-Path $pwshPath -PathType Leaf) {
            if (-not (($env:Path -split ';') -contains $portableRoot)) {
                $env:Path = "$portableRoot;$env:Path"
            }
            $script:BootstrapPwshPath = $pwshPath
            Write-LogOK "Portable PowerShell 7 is already available at $pwshPath"
            return $true
        }

        $releaseUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl
        $asset = $release.assets | Where-Object { $_.name -like "PowerShell-*-win-x64.zip" } | Select-Object -First 1

        if (-not $asset) { throw "Could not find PowerShell ZIP asset from GitHub." }

        $zipUrl = $asset.browser_download_url
        $zipPath = Join-Path $env:TEMP $asset.name

        Write-LogInfo "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 2)) MB)..."
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
        $ProgressPreference = 'Continue'

        if (Test-Path $portableRoot) {
            Remove-Item $portableRoot -Recurse -Force
        }
        New-Item -Path $portableRoot -ItemType Directory -Force | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $portableRoot -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        if (-not (Test-Path $pwshPath -PathType Leaf)) {
            throw "Portable PowerShell extraction did not produce $pwshPath"
        }

        if (-not (($env:Path -split ';') -contains $portableRoot)) {
            $env:Path = "$portableRoot;$env:Path"
        }
        $script:BootstrapPwshPath = $pwshPath
        Write-LogOK "Portable PowerShell 7 is ready at $pwshPath"
        return $true
    }
    catch {
        Write-LogError "Failed to install portable PowerShell 7: $_"
        return $false
    }
}

function Restore-BootstrapPwshPath {
    if (-not $script:BootstrapPwshPath) {
        return $false
    }

    if (-not (Test-Path $script:BootstrapPwshPath -PathType Leaf)) {
        return $false
    }

    $bootstrapPwshDir = Split-Path -Parent $script:BootstrapPwshPath
    if (-not (($env:Path -split ';') -contains $bootstrapPwshDir)) {
        $env:Path = "$bootstrapPwshDir;$env:Path"
    }

    return $true
}

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

    if (-not (Test-IsAdmin)) {
        Write-LogWarn "Skipping Winget bootstrap in a standard-user session."
    }
    elseif (Test-Path $installScript) {
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

        $installedViaMsi = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-LogInfo "Installing PowerShell 7 via Winget..."
            Repair-BootstrapWingetSources
            $pwshScope = if (Test-IsAdmin) { 'machine' } else { 'user' }
            try {
                winget install --id Microsoft.PowerShell --source winget --scope $pwshScope --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
            }
            catch {
                Write-LogWarn "Winget install for PowerShell 7 threw an error: $($_.Exception.Message)"
                $global:LASTEXITCODE = -1
            }

            if ($LASTEXITCODE -ne 0) {
                if (-not (Test-IsAdmin) -and (Install-PowerShell7Portable)) {
                    Write-LogWarn "Winget install for PowerShell 7 failed with exit code $LASTEXITCODE. Using portable fallback for this session."
                }
                else {
                    Write-LogWarn "Winget install for PowerShell 7 failed with exit code $LASTEXITCODE. Falling back to MSI."
                    if (-not (Install-PowerShell7FromMsi)) {
                        return
                    }
                    $installedViaMsi = $true
                }
            }
        }
        else {
            if (-not (Test-IsAdmin) -and (Install-PowerShell7Portable)) {
                Write-LogWarn "Winget is unavailable. Using portable PowerShell 7 fallback for this session."
            }
            else {
                if (-not (Install-PowerShell7FromMsi)) {
                    return
                }
                $installedViaMsi = $true
            }
        }

        Update-Path
        $portablePwshAvailable = Restore-BootstrapPwshPath

        if ((-not $portablePwshAvailable) -and (-not (Get-Command pwsh -ErrorAction SilentlyContinue))) {
            if (-not $installedViaMsi) {
                if (-not (Test-IsAdmin) -and (Install-PowerShell7Portable)) {
                    Write-LogWarn "PowerShell 7 was not available after package installation. Using portable fallback for this session."
                }
                else {
                    Write-LogWarn "PowerShell 7 was not available after Winget installation. Retrying with MSI."
                    if (-not (Install-PowerShell7FromMsi)) {
                        return
                    }
                    Update-Path
                    $portablePwshAvailable = Restore-BootstrapPwshPath
                }
            }
        }

        if ((-not $portablePwshAvailable) -and (-not (Get-Command pwsh -ErrorAction SilentlyContinue))) {
            Write-LogError "Failed to verify PowerShell 7 installation."
            Wait-BootstrapExit
            return
        }
    }

    Write-LogOK "Restarting script in PowerShell 7..."
    $scriptArgs = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($OriginalUserProfile) {
        $scriptArgs += @("-OriginalUserProfile", $OriginalUserProfile, "-OriginalAppData", $OriginalAppData, "-OriginalLocalAppData", $OriginalLocalAppData)
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
        $scriptArgs += @("-LogPath", $LogPath)
    }
    Stop-SetupTranscript
    $pwshCommand = if ($script:BootstrapPwshPath) { $script:BootstrapPwshPath } else { 'pwsh' }
    & $pwshCommand @scriptArgs
    exit $LASTEXITCODE
}

try {
    Write-LogInfo "Starting Setup..."
    Start-DotfilesBootstrap -Phase $Phase -ScriptPath $PSCommandPath -PreferredDrive $PreferredDrive -OriginalUserProfile $OriginalUserProfile -OriginalAppData $OriginalAppData -OriginalLocalAppData $OriginalLocalAppData -LogPath $LogPath -AdminManifestOnly:$AdminManifestOnly
}
catch {
    Write-LogError "Setup failed: $_"
    Stop-SetupTranscript
    Wait-BootstrapExit
    return
}
