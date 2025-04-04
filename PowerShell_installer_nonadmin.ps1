# Non elevated PowerShell Setup Script

# Function to test internet connectivity
function Test-InternetConnection {
    try {
        Test-Connection -ComputerName www.google.com -Count 1 -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "Internet connection is required but not available. Please check your connection."
        return $false
    }
}

function Install-PowerShell {
    # install via microsoft store
    winget install -e -i --id=9MZ1SNWT0N5D --source=msstore
}

function Install-WindowsTerminalTheme {
    param (
        [string]$ThemeUrl = "https://github.com/mbadolato/iTerm2-Color-Schemes/raw/master/windowsterminal/gruber-darker.json",
        [string]$ThemeName = "gruber-darker"
    )

    try {
        Write-Host "Installing Windows Terminal theme: $ThemeName..." -ForegroundColor Cyan
        
        $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        
        if (-not (Test-Path $settingsPath)) {
            Write-Warning "Windows Terminal settings file not found. Make sure Windows Terminal is installed."
            return
        }
        
        Copy-Item -Path $settingsPath -Destination "$settingsPath.backup" -Force
        Write-Host "Created backup of Windows Terminal settings at $settingsPath.backup" -ForegroundColor Green
        
        $themeContent = Invoke-RestMethod -Uri $ThemeUrl
        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
        
        if (-not $settings.PSObject.Properties.Name -contains "schemes") {
            $settings | Add-Member -Type NoteProperty -Name "schemes" -Value @()
        }
        
        $themeExists = $settings.schemes | Where-Object { $_.name -eq $ThemeName }
        
        if (-not $themeExists) {
            $settings.schemes += $themeContent
            # Save after adding the scheme
            $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath
            Write-Host "Theme '$ThemeName' has been added to Windows Terminal" -ForegroundColor Green
            
            # Reload settings to ensure we have the latest structure
            $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            
            # Set as default for all profiles
            if (-not $settings.PSObject.Properties.Name -contains "profiles") {
                $settings | Add-Member -Type NoteProperty -Name "profiles" -Value @{}
            }
            
            if (-not $settings.profiles.PSObject.Properties.Name -contains "defaults") {
                $settings.profiles | Add-Member -Type NoteProperty -Name "defaults" -Value @{}
            }
            
            $settings.profiles.defaults | Add-Member -Type NoteProperty -Name "colorScheme" -Value $ThemeName -Force
            
            $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath
            Write-Host "Theme '$ThemeName' set as default for all profiles" -ForegroundColor Green
        }
        else {
            Write-Host "Theme '$ThemeName' already exists in Windows Terminal settings" -ForegroundColor Yellow
            # Check if it's already the default, if not, set it
            if ($settings.profiles.defaults.colorScheme -ne $ThemeName) {
                $settings.profiles.defaults | Add-Member -Type NoteProperty -Name "colorScheme" -Value $ThemeName -Force
                $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath
                Write-Host "Theme '$ThemeName' set as default for all profiles" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Error "Failed to install Windows Terminal theme. Error: $_"
    }
}

function Install-NerdFonts {
    param (
        [string]$FontDisplayName = "Iosevka NF",
        [string]$FontMonoName = "Iosevka Nerd Font Mono",
        [int]$FontSize = 14
    )

    try {
        [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
        $fontFamilies = (New-Object System.Drawing.Text.InstalledFontCollection).Families.Name
        
        Write-Host "Checking if $FontDisplayName is installed..." -ForegroundColor Cyan
        
        if ($fontFamilies -notcontains "${FontDisplayName}") {
            scoop bucket add nerd-fonts
            scoop install nerd-fonts/Iosevka-NF-Mono

            Write-Host "Font $FontDisplayName installation process completed ($fontsInstalled fonts installed)" -ForegroundColor Green
            Write-Host "Note: You may need to restart applications or log out/in for the fonts to be fully available" -ForegroundColor Yellow
        }
        else {
            Write-Host "Font $FontDisplayName already installed" -ForegroundColor Yellow
        }

        # Set Iosevka NF Mono as default font in Windows Terminal
        $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        
        if (Test-Path $settingsPath) {
            Write-Host "Configuring Windows Terminal to use $FontMonoName..." -ForegroundColor Cyan
            $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            
            if (-not $settings.PSObject.Properties.Name -contains "profiles") {
                $settings | Add-Member -Type NoteProperty -Name "profiles" -Value @{}
            }
            
            if (-not $settings.profiles.PSObject.Properties.Name -contains "defaults") {
                $settings.profiles | Add-Member -Type NoteProperty -Name "defaults" -Value @{}
            }
            
            $fontConfig = @{
                face = $FontMonoName
                size = $FontSize
            }
            $settings.profiles.defaults | Add-Member -Type NoteProperty -Name "font" -Value $fontConfig -Force
            
            $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath
            Write-Host "Set $FontMonoName (size $FontSize) as default font in Windows Terminal" -ForegroundColor Green
        }
        else {
            Write-Warning "Windows Terminal settings file not found. Font installed but not set as default."
        }
    }
    catch {
        Write-Error "Failed to install or configure ${FontDisplayName}. Error: $_"
    }
}

function Install-OhMyPosh {
    Write-Host "Installing Oh My Posh..." -ForegroundColor Cyan
    try {
        # Install Oh My Posh using Scoop
        scoop bucket add main
        scoop install oh-my-posh
        
        Write-Host "Oh My Posh installed successfully via Scoop." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install Oh My Posh. Error: $_"
        Write-Host "Please manually install Oh My Posh from: https://ohmyposh.dev/docs/installation/windows" -ForegroundColor Yellow
    }
}

function Install-Modules {
    Write-Host "Installing PowerShell modules..." -ForegroundColor Cyan
    
    # Check if PSFzf module exists
    if (!(Get-Module -ListAvailable -Name PSFzf)) {
        try {
            & pwsh -NoProfile -Command "Install-Module -Name PSFzf -Scope CurrentUser -Force"
            Write-Host "PSFzf installed successfully."
        }
        catch {
            Write-Error "Failed to install PSFzf. Error: $_"
        }
    }
    else {
        Write-Host "PSFzf module is already installed." -ForegroundColor Yellow
    }
    
    # Check if Terminal-Icons module exists
    if (!(Get-Module -ListAvailable -Name Terminal-Icons)) {
        try {
            & pwsh -NoProfile -Command "Install-Module -Name Terminal-Icons -Repository PSGallery -Force -Scope CurrentUser"
        }
        catch {
            Write-Error "Failed to install Terminal Icons module. Error: $_"
        }
    }
    else {
        Write-Host "Terminal-Icons module is already installed." -ForegroundColor Yellow
    }
}

function Install-UserTools {
    Write-Host "Installing user tools..." -ForegroundColor Cyan
    
    # Install tools using scoop
    try {
        scoop bucket add main
        scoop install fzf
        Write-Host "fzf installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install fzf. Error: $_"
    }
    
    try {
        scoop install zoxide
        Write-Host "zoxide installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install zoxide. Error: $_"
    }
    
    try {
        scoop install winfetch
        Write-Host "winfetch installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install winfetch. Error: $_"
    }
}

# Check internet connection before proceeding
if (-not (Test-InternetConnection)) {
    break
}

# Install or check PowerShell 7
Install-PowerShell

# Define profile directory and file path explicitly for PowerShell 7
$profileDir = "$env:userprofile\Documents\PowerShell"
$profileFile = Join-Path $profileDir "Microsoft.PowerShell_profile.ps1"
$poshFile = Join-Path $profileDir "oh-my-posh_cobalt2.omp.json"
$configFile = Join-Path $profileDir "powershell.config.json"

# Profile creation or update
if (!(Test-Path -Path $profileFile -PathType Leaf)) {
    try {
        if (!(Test-Path -Path $profileDir)) {
            New-Item -Path $profileDir -ItemType "directory" | Out-Null
            Write-Host "Created directory $profileDir"
        }

        Invoke-RestMethod https://github.com/jjaroztegi/.dotfiles/raw/main/Powershell/Microsoft.PowerShell_profile.ps1 -OutFile $profileFile
        Invoke-RestMethod https://github.com/jjaroztegi/.dotfiles/raw/main/Powershell/oh-my-posh_cobalt2.omp.json -OutFile $poshFile
        Invoke-RestMethod https://github.com/jjaroztegi/.dotfiles/raw/main/Powershell/powershell.config.json -OutFile $configFile

        Write-Host "The profile and configuration files have been created in [$profileDir]."
    }
    catch {
        Write-Error "Failed to create or update the profile. Error: $_"
    }
}
else {
    try {
        Get-Item -Path $profileFile | Move-Item -Destination (Join-Path $profileDir "oldprofile.ps1") -Force
        Invoke-RestMethod https://github.com/jjaroztegi/.dotfiles/raw/main/Powershell/Microsoft.PowerShell_profile.ps1 -OutFile $profileFile
        Invoke-RestMethod https://github.com/jjaroztegi/.dotfiles/raw/main/Powershell/oh-my-posh_cobalt2.omp.json -OutFile $poshFile
        Invoke-RestMethod https://github.com/jjaroztegi/.dotfiles/raw/main/Powershell/powershell.config.json -OutFile $configFile
        Write-Host "The profile @ [$profileFile] has been created and old profile renamed to oldprofile.ps1."
    }
    catch {
        Write-Error "Failed to backup and update the profile. Error: $_"
    }
}


# Check if scoop is installed
if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Scoop is not installed. Installing Scoop..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }
    catch {
        Write-Error "Failed to install Scoop. Error: $_"
        return
    }
}

# Oh My Posh Install
Install-OhMyPosh

# Font Install
Install-NerdFonts -FontDisplayName "Iosevka NF"

# Module Install
Install-Modules

# User Tools Install
Install-UserTools

# Windows Terminal Theme Install
Install-WindowsTerminalTheme

# Final check
if ((Test-Path -Path $profileFile) -and 
    (Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and 
    ((New-Object System.Drawing.Text.InstalledFontCollection).Families.Name -contains "Iosevka NF")) {
    Write-Host "Setup completed successfully." -ForegroundColor Green
    Write-Host "Please restart your PowerShell session to apply changes." -ForegroundColor Magenta
}
else {
    Write-Warning "Setup completed with some components missing. Please check the error messages above."
}