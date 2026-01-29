#Requires -Module Common

function Install-PackageManagers {
    $isAdmin = Test-IsAdmin

    if ($isAdmin) {
        Write-LogInfo "Running as Admin. Verifying Winget..."
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-LogWarn "Winget not found. Please install App Installer from Microsoft Store."
        }
        else {
            Write-LogInfo "Resetting Winget sources to ensure fresh state..."
            try {
                winget source reset --force 2>&1 | Out-Null
            }
            catch {
                Write-LogWarn "Winget source reset failed. Continuing anyway..."
            }
        }

        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-LogWarn "Chocolatey missing. Installing..."
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                Update-Path
            }
            catch {
                Write-LogError "Failed to install Chocolatey: $_"
            }
        }
    }
    else {
        Write-LogInfo "Running as User. Verifying Scoop..."
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-LogWarn "Installing Scoop..."
            try {
                Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
                Update-Path
            }
            catch {
                Write-LogError "Failed to install Scoop: $_"
            }
        }
    }
}

function Test-SoftwareInstalled {
    param(
        [string]$Name,
        [string]$ExecutableName,
        [string]$WingetId,
        [string]$ChocoId
    )

    if ($ExecutableName -and (Get-Command $ExecutableName -ErrorAction SilentlyContinue)) {
        return $true
    }

    if ($WingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        $wingetList = winget list --id $WingetId --exact --accept-source-agreements 2>$null
        if ($LASTEXITCODE -eq 0 -and $wingetList -notmatch "No installed package") {
            return $true
        }
    }

    if ($ChocoId -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        $chocoList = choco list --local-only --exact --id-only -r $ChocoId 2>$null
        if ($chocoList -contains $ChocoId) {
            return $true
        }
    }

    if ($ExecutableName -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        $scoopList = scoop list 2>$null | Select-Object -ExpandProperty Name
        if ($scoopList -contains $ExecutableName) {
            return $true
        }
    }

    return $false
}

function Install-Software {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$ExecutableName,
        [string]$WingetId,
        [string]$ScoopId,
        [string]$ChocoId
    )

    $isAdmin = Test-IsAdmin

    if (Test-SoftwareInstalled -Name $Name -ExecutableName $ExecutableName -WingetId $WingetId -ChocoId $ChocoId) {
        Write-LogSkip "$Name is already installed."
        return
    }

    # Installer priority based on privilege level:
    # Admin: Winget -> Chocolatey
    # User: Scoop -> Winget (User scope)

    if ($isAdmin) {
        if ($WingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($Name, "Install via Winget (Admin)")) {
                Write-LogInfo "Installing $Name via Winget..."
                winget install --id $WingetId -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --source winget
                if ($LASTEXITCODE -eq 0) { Write-LogOK "Installed $Name" } else { Write-LogError "Failed to install $Name via Winget" }
            }
            return
        }

        if ($ChocoId -and (Get-Command choco -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($Name, "Install via Chocolatey")) {
                Write-LogInfo "Installing $Name via Chocolatey..."
                choco install $ChocoId -y
                if ($LASTEXITCODE -eq 0) { Write-LogOK "Installed $Name" } else { Write-LogError "Failed to install $Name via Chocolatey" }
            }
            return
        }
    }
    else {
        if ($ScoopId -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($Name, "Install via Scoop")) {
                Write-LogInfo "Installing $Name via Scoop..."
                scoop install $ScoopId
                if ($LASTEXITCODE -eq 0) { Write-LogOK "Installed $Name" } else { Write-LogError "Failed to install $Name via Scoop" }
            }
            return
        }

        if ($WingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($Name, "Install via Winget (User)")) {
                Write-LogInfo "Installing $Name via Winget (User scope)..."
                winget install --id $WingetId -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --scope user --source winget
                if ($LASTEXITCODE -eq 0) { Write-LogOK "Installed $Name" } else { Write-LogError "Failed to install $Name via Winget" }
            }
            return
        }
    }

    Write-LogWarn "Skipping $Name. No suitable package manager found or ID missing for current context."
}

Export-ModuleMember -Function Install-PackageManagers, Install-Software, Test-SoftwareInstalled
