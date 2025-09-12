#Requires -Version 5.1

<#
.SYNOPSIS
    A unified PowerShell environment setup script for both admin and non-admin users.
.DESCRIPTION
    This script automates the setup of a WindowsTerminal environment, including the installation of PowerShell 7, essential modules, and tools.
    It automatically detects if it's running with administrative privileges and uses the appropriate package manager (Chocolatey for admin, Scoop for non-admin).
.NOTES
    Author: Juanjo
    Version: 2.0
    Last Updated: 2025-08-27
#>

#region Global Variables and Initial Checks

$scriptUrl = "https://raw.githubusercontent.com/jjaroztegi/.dotfiles/refs/heads/main/PowerShell_installer.ps1"
$global:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')

if ($global:IsAdmin) {
    Write-Host "Running with Administrator privileges." -ForegroundColor Green
} else {
    Write-Host "Running as a standard user." -ForegroundColor Yellow
    $choice = Read-Host "Do you want to restart with Administrator privileges? (recommended) (y/N)"
    if ($choice -match '^[Yy]$') {
        Write-Host "Attempting to relaunch with administrator privileges..." -ForegroundColor Cyan
        try {
            $tempScriptPath = Join-Path $env:TEMP "temp-setup-script.ps1"
            Invoke-RestMethod -Uri $scriptUrl -OutFile $tempScriptPath

            $psi = @{
                FilePath     = "powershell.exe"
                Verb         = "RunAs"
                ArgumentList = "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$tempScriptPath`""
            }
            Start-Process @psi
            exit
        } catch {
            Write-Warning "Elevation request canceled or failed. Continuing as standard user. Error: $_"
        }
    } else {
        Write-Host "Continuing without elevation." -ForegroundColor Yellow
    }
}

#endregion

#region Core Functions

function Test-InternetConnection {
    try {
        Test-Connection -ComputerName "www.google.com" -Count 1 -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Warning "Internet connection is required but not available. Please check your connection."
        return $false
    }
}

function Install-PackageManager {
    if ($global:IsAdmin) {
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Host "Chocolatey not found. Installing..." -ForegroundColor Yellow
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            }
            catch {
                Write-Error "Failed to install Chocolatey. Error: $_"
                throw "Chocolatey installation failed."
            }
        } else {
            Write-Host "Chocolatey is already installed." -ForegroundColor Green
        }
    } else {
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Host "Scoop not found. Installing..." -ForegroundColor Yellow
            try {
                Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
                Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
            }
            catch {
                Write-Error "Failed to install Scoop. Error: $_"
                throw "Scoop installation failed."
            }
        } else {
            Write-Host "Scoop is already installed." -ForegroundColor Green
        }
    }
}

function Install-Package {
    param(
        [string]$PackageName,
        [string]$ChocoId,
        [string]$ScoopId,
        [string]$WingetId
    )

    try {
        if ($global:IsAdmin) {
            if ($ChocoId) {
                if ((choco list --local-only --exact --id-only -r $ChocoId) -contains $ChocoId) {
                    Write-Host "$PackageName (via choco) is already installed." -ForegroundColor Green
                    return
                }
                Write-Host "Installing $PackageName via Chocolatey..." -ForegroundColor Cyan
                choco install $ChocoId -y --ignore-checksums
            } elseif ($WingetId) {
                if (winget list --exact --id $WingetId) {
                    Write-Host "$PackageName (via winget) is already installed." -ForegroundColor Green
                    return
                }
                Write-Host "Installing $PackageName via Winget..." -ForegroundColor Cyan
                winget install -e --id $WingetId --accept-source-agreements --accept-package-agreements
            }
        } else {
            if ($ScoopId) {
                if ((scoop list | Select-Object -ExpandProperty Name) -contains ($ScoopId.split('/')[-1])) {
                    Write-Host "$PackageName (via scoop) is already installed." -ForegroundColor Green
                    return
                }
                Write-Host "Installing $PackageName via Scoop..." -ForegroundColor Cyan
                scoop install $ScoopId
            } elseif ($WingetId) {
                if (winget list --exact --id $WingetId) {
                    Write-Host "$PackageName (via winget) is already installed." -ForegroundColor Green
                    return
                }
                Write-Host "Installing $PackageName via Winget..." -ForegroundColor Cyan
                winget install -e --id $WingetId --accept-source-agreements --accept-package-agreements
            }
        }
        Write-Host "$PackageName installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install $PackageName. Error: $_"
    }
}

function Install-PowerShellModule {
    param(
        [string]$ModuleName
    )

    try {
        $Scope = if ($global:IsAdmin) { "AllUsers" } else { "CurrentUser" }

        $pwsh7ModulePath = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'PowerShell\Modules'
        $moduleInstalledInPwsh7 = Test-Path -Path (Join-Path -Path $pwsh7ModulePath -ChildPath $ModuleName)

        if ($moduleInstalledInPwsh7) {
            Write-Host "PowerShell module '$ModuleName' is already installed for PowerShell 7." -ForegroundColor Green
            return
        }

        Write-Host "Installing PowerShell module '$ModuleName' for $Scope..." -ForegroundColor Cyan

        if (-not (Get-PackageProvider -Name 'NuGet' -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-Host 'NuGet provider not found. Installing...'
            Install-PackageProvider -Name 'NuGet' -MinimumVersion '2.8.5.201' -Force -Scope $Scope
            Import-PackageProvider -Name 'NuGet' -Force
        }

        # If PowerShell 7 is present, and we are a non-admin, install to the PS7 user module path
        if ((Get-Command pwsh -ErrorAction SilentlyContinue) -and -not $global:IsAdmin) {
            if (-not (Test-Path -Path $pwsh7ModulePath)) {
                New-Item -Path $pwsh7ModulePath -ItemType Directory -Force | Out-Null
            }
            # Save the module to a temporary path and then move it to the correct folder
            $tempPath = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([Guid]::NewGuid().ToString()))
            Save-Module -Name $ModuleName -Repository PSGallery -Path $tempPath.FullName
            $moduleSourcePath = Join-Path -Path $tempPath.FullName -ChildPath $ModuleName
            $moduleDestPath = Join-Path -Path $pwsh7ModulePath -ChildPath $ModuleName
            Move-Item -Path $moduleSourcePath -Destination $moduleDestPath -Force
            Remove-Item -Path $tempPath -Recurse -Force
        } else {
            Install-Module -Name $ModuleName -Repository PSGallery -Force -Scope $Scope -ErrorAction Stop
        }

        Write-Host "'$ModuleName' module installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install '$ModuleName' module. Error: $_"
    }
}

#endregion

#region Installation Functions

function Install-PowerShellCore {
    Write-Host "Checking for PowerShell 7..." -ForegroundColor Cyan
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Host "PowerShell 7 not found. Installing..." -ForegroundColor Yellow
        if ($global:IsAdmin) {
            Install-Package -PackageName "PowerShell 7" -WingetId "Microsoft.PowerShell"
        } else {
            # Non-admin: Try winget first if available, then fall back to Scoop.
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                try {
                    Write-Host "Attempting installation using Winget..." -ForegroundColor Cyan
                    winget install -e --id 9MZ1SNWT0N5D --source msstore --accept-source-agreements --accept-package-agreements
                    Write-Host "PowerShell 7 installed successfully via Winget." -ForegroundColor Green
                }
                catch {
                    Write-Warning "Winget attempt failed. Falling back to Scoop. Error: $_"
                    try {
                        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { Install-PackageManager }
                        Write-Host "Attempting installation using Scoop..." -ForegroundColor Cyan
                        Install-Package -PackageName "PowerShell 7" -ScoopId "main/pwsh"
                        Write-Host "PowerShell 7 installed successfully from Scoop." -ForegroundColor Green
                    }
                    catch {
                        Write-Error "Failed to install PowerShell 7 via both Winget and Scoop. Error: $_"
                    }
                }
            } else {
                try {
                    Write-Host "Winget not found. Using Scoop for installation..." -ForegroundColor Yellow
                    Install-Package -PackageName "PowerShell 7" -ScoopId "main/pwsh"
                    Write-Host "PowerShell 7 installed successfully from Scoop." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to install PowerShell 7 from Scoop (winget unavailable). Error: $_"
                }
            }
        }
    } else {
        Write-Host "PowerShell 7 is already installed. Checking for updates..." -ForegroundColor Green
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                winget upgrade --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements
            }
            catch {
                Write-Warning "Could not check for PowerShell 7 updates via winget. Error: $_"
            }
        } else {
            Write-Host "Winget not available; skipping automatic update check." -ForegroundColor Yellow
        }
    }
}

function Install-OhMyPosh {
    Install-Package -PackageName "Oh My Posh" -ChocoId "oh-my-posh" -ScoopId "main/oh-my-posh"
}

function Install-NerdFonts {
    param (
        [string]$FontName = "Iosevka",
        [string]$FontDisplayName = "Iosevka NF"
    )

    Write-Host "Checking if '$FontDisplayName' is installed..." -ForegroundColor Cyan
    $fontInstalled = $false
    try {
        $fontRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        $installedFontNames = Get-ItemProperty -Path $fontRegistryPath |
                              Get-Member -MemberType NoteProperty |
                              Select-Object -ExpandProperty Name

        if ($installedFontNames -match [regex]::Escape($FontDisplayName)) {
            $fontInstalled = $true
        }
    }
    catch {
        Write-Warning "Could not check for installed fonts in the registry. Will attempt to install anyway. Error: $_"
    }

    if (-not $fontInstalled) {
        Write-Host "'$FontDisplayName' not found. Installing..." -ForegroundColor Yellow
        if ($global:IsAdmin) {
            try {
                Install-Package -PackageName "Iosevka Nerd Fonts" -ChocoId "nerd-fonts-iosevka"
            }
            catch {
                Write-Error "Failed to install Iosevka Nerd Fonts via Chocolatey. Error: $_"
            }
        } else {
            try {
                scoop install git
                scoop bucket add nerd-fonts
                Install-Package -PackageName "Iosevka Nerd Fonts" -ScoopId "nerd-fonts/iosevka-nf-mono"
            }
            catch {
                Write-Error "Failed to install Iosevka Nerd Fonts via Scoop. Error: $_"
            }
        }
    } else {
        Write-Host "'$FontDisplayName' is already installed." -ForegroundColor Green
    }
}

function Set-WindowsTerminalDefaults {
    param (
        [string]$ThemeUrl = "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/windowsterminal/gruber-darker.json",
        [string]$ThemeName = "gruber-darker",
        [string]$FontName = "Iosevka Nerd Font Mono",
        [int]$FontSize = 14
    )

    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path $settingsPath)) {
        Write-Warning "Windows Terminal settings file not found. Skipping theme and font configuration."
        return
    }

    try {
        Write-Host "Backing up Windows Terminal settings..." -ForegroundColor Cyan
        Copy-Item -Path $settingsPath -Destination "$settingsPath.backup" -Force

        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop

        if (-not $settings.PSObject.Properties.Name -contains 'schemes') {
            $settings | Add-Member -MemberType NoteProperty -Name 'schemes' -Value @()
        }

        # Install Theme
        Write-Host "Installing Windows Terminal theme '$ThemeName'..." -ForegroundColor Cyan
        if (-not ($settings.schemes | Where-Object { $_.name -eq $ThemeName })) {
            $themeContent = Invoke-RestMethod -Uri $ThemeUrl
            $settings.schemes += $themeContent
            Write-Host "Theme '$ThemeName' added." -ForegroundColor Green
        } else {
            Write-Host "Theme '$ThemeName' already exists." -ForegroundColor Yellow
        }

        if (-not $settings.PSObject.Properties.Name -contains 'profiles') {
            $settings | Add-Member -MemberType NoteProperty -Name 'profiles' -Value (New-Object -TypeName PSObject)
        }

        if (-not $settings.profiles.PSObject.Properties.Name -contains 'defaults') {
            $settings.profiles | Add-Member -MemberType NoteProperty -Name 'defaults' -Value (New-Object -TypeName PSObject)
        }

        $fontConfig = @{
            face = $FontName
            size = $FontSize
        }

        # Assign properties.
        Write-Host "Setting defaults for color scheme and font..." -ForegroundColor Cyan
        $settings.profiles.defaults | Add-Member -Type NoteProperty -Name "colorScheme" -Value $ThemeName -Force
        $settings.profiles.defaults | Add-Member -Type NoteProperty -Name "font" -Value $fontConfig -Force

        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath
        Write-Host "Set '$ThemeName' and '$FontName' as Windows Terminal defaults." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to configure Windows Terminal settings. Error: $_"
        throw
    }
}

function Update-PowerShellProfile {
    $profileDir = Join-Path $env:USERPROFILE "Documents\PowerShell"
    $profileFile = Join-Path $profileDir "Microsoft.PowerShell_profile.ps1"
    $poshFile = Join-Path $profileDir "oh-my-posh_cobalt2.omp.json"
    $configFile = Join-Path $profileDir "powershell.config.json"

    $profileUrl = "https://github.com/jjaroztegi/.dotfiles/raw/main/Powershell/Microsoft.PowerShell_profile.ps1"
    $poshThemeUrl = "https://github.com/jjaroztegi/.dotfiles/raw/main/Powershell/oh-my-posh_cobalt2.omp.json"
    $configJsonUrl = "https://github.com/jjaroztegi/.dotfiles/raw/main/Powershell/powershell.config.json"

    Write-Host "Setting up custom PowerShell profile from jjaroztegi/.dotfiles..." -ForegroundColor Cyan

    try {
        if (-not (Test-Path -Path $profileDir -PathType Container)) {
            New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: $profileDir"
        }

        if (Test-Path -Path $profileFile -PathType Leaf) {
            $backupPath = Join-Path $profileDir "oldprofile.ps1"
            Move-Item -Path $profileFile -Destination $backupPath -Force
            Write-Host "Existing profile backed up to '$backupPath'." -ForegroundColor Yellow
        }

        Write-Host "Downloading profile from $profileUrl..."
        Invoke-RestMethod -Uri $profileUrl -OutFile $profileFile
        Invoke-RestMethod -Uri $poshThemeUrl -OutFile $poshFile
        Invoke-RestMethod -Uri $configJsonUrl -OutFile $configFile

        Write-Host "Custom profile and configuration files have been set up in '$profileDir'." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create or update the custom profile. Error: $_"
    }
}

#endregion

#region Main Script Execution

function Main {
    if (-not (Test-InternetConnection)) {
        Write-Error "No internet connection. Aborting setup."
        return
    }

    try {
        Install-PackageManager
        Install-PowerShellCore
        Install-OhMyPosh
        Install-NerdFonts

        # Install CLI Tools
        Install-Package -PackageName "fzf"      -ChocoId "fzf"      -ScoopId "main/fzf"
        Install-Package -PackageName "zoxide"   -ChocoId "zoxide"   -ScoopId "main/zoxide"
        Install-Package -PackageName "ripgrep"  -ChocoId "ripgrep"  -ScoopId "main/ripgrep"
        Install-Package -PackageName "winfetch" -ChocoId "winfetch" -ScoopId "main/winfetch"

        # Install PowerShell Modules
        Install-PowerShellModule -ModuleName "Terminal-Icons"
        Install-PowerShellModule -ModuleName "posh-git"
        Install-PowerShellModule -ModuleName "PSFzf"

        # Configure Environment
        Set-WindowsTerminalDefaults
        Update-PowerShellProfile

        Write-Host "Setup completed successfully! Please restart your PowerShell session." -ForegroundColor Magenta
    }
    catch {
        Write-Error "An error occurred during setup. Please check the messages above."
    }
}

Main

#endregion