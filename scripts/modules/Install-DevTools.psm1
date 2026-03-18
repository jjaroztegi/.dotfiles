Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\Common.psm1") -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\SetupEnvironment.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "ManagedPackages.psm1") -Force

function Install-DevTools {
    Write-LogInfo "Installing Developer Tools from package catalog..."

    foreach ($package in Get-ManagedPackages) {
        Install-ManagedPackage -Package $package
    }
}

Export-ModuleMember -Function Install-DevTools
