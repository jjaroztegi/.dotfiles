Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\Common.psm1") -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\SetupEnvironment.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "ManagedPackages.psm1") -Force

function Install-PackageManagers {
    $isAdmin = Test-IsAdmin
    $packages = Get-ManagedPackages
    $requiresChocolatey = [bool]($packages | Where-Object {
            ($_.preferredManager -eq 'choco') -or (@($_.fallbackManagers) -contains 'choco')
        })

    Write-LogInfo "Verifying package manager availability..."

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-LogWarn "Winget not found. Please install App Installer from Microsoft Store."
    }
    elseif ($isAdmin) {
        Write-LogInfo "Resetting Winget sources to ensure fresh state..."
        try {
            winget source reset --force 2>&1 | Out-Null
        }
        catch {
            Write-LogWarn "Winget source reset failed. Continuing anyway..."
        }
    }
    else {
        Write-LogInfo "Skipping Winget source reset in standard-user mode."
    }

    if ($isAdmin -and $requiresChocolatey -and -not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-LogWarn "Chocolatey missing. Installing fallback package manager..."
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

    Update-StandardPaths -IsAdmin $isAdmin | Out-Null
}

Export-ModuleMember -Function Install-PackageManagers
