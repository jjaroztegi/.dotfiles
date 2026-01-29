function Install-PSModule {
    param([string]$ModuleName)

    if ([string]::IsNullOrWhiteSpace($ModuleName)) {
        Write-LogWarn "Install-PSModule called with empty ModuleName. Skipping."
        return
    }

    try {
        $isAdmin = Test-IsAdmin
        $Scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }

        $pwsh7ModulePath = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'PowerShell\Modules'
        $moduleInstalledInPwsh7 = Test-Path -Path (Join-Path -Path $pwsh7ModulePath -ChildPath $ModuleName)

        if ($moduleInstalledInPwsh7) {
            Write-LogSkip "PowerShell module '$ModuleName' already installed for PowerShell 7."
            return
        }

        if (Get-Module -ListAvailable -Name $ModuleName) {
            Write-LogSkip "PowerShell module '$ModuleName' is already available."
            return
        }

        Write-LogInfo "Installing PowerShell module '$ModuleName' for $Scope..."

        if (-not (Get-PackageProvider -Name 'NuGet' -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-LogInfo 'NuGet provider not found. Installing...'
            Install-PackageProvider -Name 'NuGet' -MinimumVersion '2.8.5.201' -Force -Scope $Scope
            Import-PackageProvider -Name 'NuGet' -Force
        }

        if ((Get-Command pwsh -ErrorAction SilentlyContinue) -and -not $isAdmin) {
            if (-not (Test-Path -Path $pwsh7ModulePath)) {
                New-Item -Path $pwsh7ModulePath -ItemType Directory -Force | Out-Null
            }
            # Isolate module installation to a temporary directory before manual relocation
            $tempPath = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([Guid]::NewGuid().ToString()))
            try {
                Save-Module -Name $ModuleName -Repository PSGallery -Path $tempPath.FullName -ErrorAction Stop
                $moduleSourcePath = Join-Path -Path $tempPath.FullName -ChildPath $ModuleName
                $moduleDestPath = Join-Path -Path $pwsh7ModulePath -ChildPath $ModuleName
                if (Test-Path $moduleSourcePath) {
                    Move-Item -Path $moduleSourcePath -Destination $moduleDestPath -Force
                }
            }
            finally {
                Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            Install-Module -Name $ModuleName -Repository PSGallery -Force -Scope $Scope -ErrorAction Stop
        }

        Write-LogOK "'$ModuleName' module installed successfully."
    }
    catch {
        Write-LogError "Failed to install '$ModuleName' module. Error: $_"
    }
}

function Install-PowerShellModules {
    param([string[]]$Modules)

    foreach ($mod in $Modules) {
        if ([string]::IsNullOrWhiteSpace($mod)) {
            continue
        }
        Install-PSModule $mod
    }
}

Export-ModuleMember -Function Install-PowerShellModules, Install-PSModule
