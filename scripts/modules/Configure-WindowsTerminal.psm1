function Set-WindowsTerminalDefaults {
    param (
        [string]$ThemeUrl = "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/windowsterminal/Gruber%20Darker.json",
        [string]$ThemeName = "gruber-darker",
        [string]$FontName = "Iosevka Nerd Font Mono",
        [int]$FontSize = 14
    )

    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

    if (-not (Test-Path $settingsPath)) {
        Write-LogWarn "Windows Terminal settings file not found. Creating default settings..."
        $parentDir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        $defaultSettings = @{
            '$schema'      = 'https://aka.ms/terminal-profiles-schema'
            defaultProfile = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
            profiles       = @{
                defaults = @{}
                list     = @(
                    @{
                        guid        = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
                        name        = 'Windows PowerShell'
                        commandline = 'powershell.exe'
                        hidden      = $false
                    }
                )
            }
            schemes        = @()
        }
        $defaultSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Force
    }


    try {
        Write-LogInfo "Backing up Windows Terminal settings..."
        Copy-Item -Path $settingsPath -Destination "$settingsPath.backup" -Force

        $jsonContent = Get-Content -Path $settingsPath -Raw
        if ([string]::IsNullOrWhiteSpace($jsonContent)) {
            Write-LogWarn "Settings file is empty."
            return
        }
        $settings = $jsonContent | ConvertFrom-Json -ErrorAction Stop

        if (-not $settings.PSObject.Properties.Name -contains 'schemes') {
            $settings | Add-Member -MemberType NoteProperty -Name 'schemes' -Value @()
        }

        Write-LogInfo "Installing Windows Terminal theme '$ThemeName'..."
        if (-not ($settings.schemes | Where-Object { $_.name -eq $ThemeName })) {
            try {
                $themeContent = Invoke-RestMethod -Uri $ThemeUrl
                $settings.schemes += $themeContent
                Write-LogOK "Theme '$ThemeName' added."
            }
            catch {
                Write-LogWarn "Failed to download theme from $ThemeUrl. $_"
            }
        }
        else {
            Write-LogSkip "Theme '$ThemeName' already exists."
        }

        if (-not $settings.profiles.PSObject.Properties.Name -contains 'defaults') {
            if (-not $settings.PSObject.Properties.Name -contains 'profiles') {
                $settings | Add-Member -MemberType NoteProperty -Name 'profiles' -Value @{ defaults = @{} }
            }
            elseif (-not $settings.profiles.PSObject.Properties.Name -contains 'defaults') {
                $settings.profiles | Add-Member -MemberType NoteProperty -Name 'defaults' -Value @{}
            }
        }

        $fontConfig = @{
            face = $FontName
            size = $FontSize
        }

        Write-LogInfo "Setting defaults for color scheme and font..."
        $settings.profiles.defaults | Add-Member -Type NoteProperty -Name "colorScheme" -Value $ThemeName -Force
        $settings.profiles.defaults | Add-Member -Type NoteProperty -Name "font" -Value $fontConfig -Force

        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath
        Write-LogOK "Set '$ThemeName' and '$FontName' as Windows Terminal defaults."
    }
    catch {
        Write-LogError "Failed to configure Windows Terminal settings. Error: $_"
    }
}

Export-ModuleMember -Function Set-WindowsTerminalDefaults
