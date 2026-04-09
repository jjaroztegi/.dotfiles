Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\Common.psm1") -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\SetupEnvironment.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "ManagedPackages.psm1") -Force

function Install-DevTools {
    param(
        [ValidateSet('All', 'User', 'Machine')]
        [string]$Scope = 'All',
        [string[]]$ExcludePackageKeys = @()
    )

    Write-LogInfo "Installing Developer Tools from package catalog..."

    $excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $ExcludePackageKeys) {
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            [void]$excluded.Add($key)
        }
    }

    $packages = @(Get-ManagedPackages)
    if ($Scope -ne 'All') {
        $packages = @($packages | Where-Object { $_.scope -eq $Scope.ToLowerInvariant() })
    }

    if ($excluded.Count -gt 0) {
        $packages = @($packages | Where-Object { -not $excluded.Contains($_.key) })
    }

    foreach ($package in $packages) {
        Install-ManagedPackage -Package $package
    }
}

Export-ModuleMember -Function Install-DevTools
