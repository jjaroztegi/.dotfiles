# Ensure the script can run with elevated privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as an Administrator!"
    break
}

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
    try {
        Write-Host "Checking for PowerShell 7..." -ForegroundColor Cyan
        if (Get-Command pwsh -ErrorAction SilentlyContinue) {
            Write-Host "PowerShell 7 is installed. Checking for updates..." -ForegroundColor Cyan

            $currentVersion = (& pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()').Trim()
            $gitHubApiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
            $latestReleaseInfo = Invoke-RestMethod -Uri $gitHubApiUrl
            $latestVersion = $latestReleaseInfo.tag_name.Trim('v')
            
            if ([version]$currentVersion -lt [version]$latestVersion) {
                Write-Host "Updating PowerShell 7 to version $latestVersion..." -ForegroundColor Yellow
                Start-Process powershell.exe -ArgumentList "-NoProfile -Command winget upgrade --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements" -Wait -NoNewWindow
                Write-Host "PowerShell 7 has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
            }
            else {
                Write-Host "Your PowerShell 7 is up to date." -ForegroundColor Green
            }
        }
        else {
            Write-Host "PowerShell 7 is not installed. Installing..." -ForegroundColor Yellow
            Start-Process powershell.exe -ArgumentList "-NoProfile -Command winget install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements" -Wait -NoNewWindow
            Write-Host "PowerShell 7 has been installed." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to install or update PowerShell 7. Error: $_"
    }
}

function Install-NerdFonts {
    param (
        [string]$FontName = "Iosevka",
        [string]$FontDisplayName = "Iosevka NF",
        [string]$Version = "3.3.0"
    )

    try {
        [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
        $fontFamilies = (New-Object System.Drawing.Text.InstalledFontCollection).Families.Name
        if ($fontFamilies -notcontains "${FontDisplayName}") {
            $fontZipUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/v${Version}/${FontName}.zip"
            $zipFilePath = "$env:TEMP\${FontName}.zip"
            $extractPath = "$env:TEMP\${FontName}"

            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFileAsync((New-Object System.Uri($fontZipUrl)), $zipFilePath)

            while ($webClient.IsBusy) {
                Start-Sleep -Seconds 2
            }

            Expand-Archive -Path $zipFilePath -DestinationPath $extractPath -Force
            $destination = (New-Object -ComObject Shell.Application).Namespace(0x14)
            Get-ChildItem -Path $extractPath -Recurse -Filter "*.ttf" | ForEach-Object {
                If (-not(Test-Path "C:\Windows\Fonts\$($_.Name)")) {
                    $destination.CopyHere($_.FullName, 0x10)
                }
            }

            Remove-Item -Path $extractPath -Recurse -Force
            Remove-Item -Path $zipFilePath -Force
        }
        else {
            Write-Host "Font ${FontDisplayName} already installed"
        }
    }
    catch {
        Write-Error "Failed to download or install ${FontDisplayName} font. Error: $_"
    }
}

if (-not (Test-InternetConnection)) {
    break
}

# Install or update PowerShell 7
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

# OhMyPosh Install
try {
    winget install -e --accept-source-agreements --accept-package-agreements JanDeDobbeleer.OhMyPosh
}
catch {
    Write-Error "Failed to install Oh My Posh. Error: $_"
}

# Font Install
Install-NerdFonts -FontName "Iosevka" -FontDisplayName "Iosevka NF"

# Final check
if ((Test-Path -Path $profileFile) -and (winget list --name "OhMyPosh" -e | Select-String "OhMyPosh") -and ((New-Object System.Drawing.Text.InstalledFontCollection).Families.Name -contains "Iosevka NF")) {
    Write-Host "Setup completed successfully. Please restart your PowerShell session to apply changes."
}
else {
    Write-Warning "Setup completed with errors. Please check the error messages above."
}

# Choco install
try {
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}
catch {
    Write-Error "Failed to install Chocolatey. Error: $_"
}

# Terminal Icons Install
try {
    Install-Module -Name Terminal-Icons -Repository PSGallery -Force
}
catch {
    Write-Error "Failed to install Terminal Icons module. Error: $_"
}

# fzf Install
try {
    choco install fzf -y
    Write-Host "fzf installed successfully."
}
catch {
    Write-Error "Failed to install fzf. Error: $_"
}

# PSFzf Install
try {
    Install-Module -Name PSFzf -Force
    Write-Host "PSFzf installed successfully."
}
catch {
    Write-Error "Failed to install PSFzf. Error: $_"
}

# zoxide Install
try {
    winget install -e --id ajeetdsouza.zoxide
    Write-Host "zoxide installed successfully."
}
catch {
    Write-Error "Failed to install zoxide. Error: $_"
}

# winfetch Install
try {
    choco install winfetch -y
    Write-Host "winfetch installed successfully."
}
catch {
    Write-Error "Failed to install winfetch. Error: $_"
}