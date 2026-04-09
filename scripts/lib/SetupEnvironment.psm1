Import-Module (Join-Path $PSScriptRoot "Common.psm1") -Force

function Set-PlacementOverride {
    param([string]$PreferredDrive)

    if ([string]::IsNullOrWhiteSpace($PreferredDrive)) {
        $script:PlacementOverride = $null
        return
    }

    if ($PreferredDrive -notmatch '^[A-Za-z]:$') {
        throw "PreferredDrive must look like 'D:' or 'E:'."
    }

    $script:PlacementOverride = $PreferredDrive.ToUpperInvariant()
}

function Get-PlacementConfig {
    if (-not $script:PlacementConfigCache) {
        $script:PlacementConfigCache = Read-JsonFile -Path (Get-DotfilesConfigPath -Name "placement.json")
    }

    return $script:PlacementConfigCache
}

function Get-PreferredDrive {
    $candidate = $null

    if ($script:PlacementOverride) {
        $candidate = $script:PlacementOverride
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:DOTFILES_PREFERRED_DRIVE)) {
        $candidate = $env:DOTFILES_PREFERRED_DRIVE
    }
    else {
        $candidate = (Get-PlacementConfig).preferredDrive
    }

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }

    $candidate = $candidate.Trim().ToUpperInvariant()
    if ($candidate -notmatch '^[A-Z]:$') {
        throw "Preferred drive '$candidate' is invalid. Use a drive root such as D:."
    }

    $driveName = $candidate.TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction SilentlyContinue
    if (-not $drive) {
        Write-LogWarn "Preferred drive '$candidate' is not available. Falling back to package manager defaults."
        return $null
    }

    return $candidate
}

function Expand-PlacementRelativePath {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $null
    }

    return $RelativePath.Replace("{UserName}", $env:USERNAME)
}

function Get-ManagedPlacement {
    $config = Get-PlacementConfig
    $preferredDrive = Get-PreferredDrive

    if (-not $preferredDrive) {
        return [pscustomobject]@{
            PreferredDrive = $null
            ManagedUserDataRoot = $null
            ManagedAppRoot = $null
        }
    }

    $managedUserRelative = Expand-PlacementRelativePath -RelativePath $config.managedUserDataRelativePath
    $managedAppRelative = Expand-PlacementRelativePath -RelativePath $config.managedAppRelativePath

    return [pscustomobject]@{
        PreferredDrive = $preferredDrive
        ManagedUserDataRoot = if ($managedUserRelative) { "{0}\{1}" -f $preferredDrive, $managedUserRelative } else { $null }
        ManagedAppRoot = if ($managedAppRelative) { "{0}\{1}" -f $preferredDrive, $managedAppRelative } else { $null }
    }
}

function Get-PackageCatalog {
    if (-not $script:PackageCatalogCache) {
        $script:PackageCatalogCache = Read-JsonFile -Path (Get-DotfilesConfigPath -Name "package-catalog.json")
    }

    return $script:PackageCatalogCache
}

function Get-RuntimePolicy {
    if (-not $script:RuntimePolicyCache) {
        $script:RuntimePolicyCache = Read-JsonFile -Path (Get-DotfilesConfigPath -Name "runtime-policy.json")
    }

    return $script:RuntimePolicyCache
}

function Get-ManagedPackages {
    return @((Get-PackageCatalog).packages | Where-Object { $_.managed -ne $false })
}

function Split-PathEntries {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return @()
    }

    return @($PathValue.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Format-PathEntryText {
    param([string]$Entry)

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return $null
    }

    $trimmed = $Entry.Trim().Trim('"')
    if ($trimmed.Length -gt 3 -and $trimmed.EndsWith("\")) {
        $trimmed = $trimmed.TrimEnd("\")
    }

    return $trimmed
}

function Test-IsStalePathEntry {
    param([string]$Entry)

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return $true
    }

    $normalized = Format-PathEntryText -Entry $Entry
    if (-not $normalized) {
        return $true
    }

    $stalePatterns = @(
        '*\AppData\Local\Microsoft\WinGet\Packages\*',
        '*\AppData\Roaming\fnm\aliases\default',
        '*\ProgramData\chocolatey\lib\*'
    )

    foreach ($pattern in $stalePatterns) {
        if ($normalized -like $pattern) {
            return $true
        }
    }

    return $false
}

function Get-PreferredPathEntries {
    param([ValidateSet('User', 'Machine')][string]$Scope)

    if ($Scope -eq 'User') {
        $entries = @(
            (Join-Path $env:USERPROFILE ".local\bin"),
            (Join-Path $env:USERPROFILE ".pyenv\pyenv-win\shims"),
            (Join-Path $env:USERPROFILE ".pyenv\pyenv-win\bin"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps")
        )

        $pwshScripts = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Scripts'
        if (Test-Path $pwshScripts -PathType Container) {
            $entries += $pwshScripts
        }

        $placement = Get-ManagedPlacement
        if ($placement.ManagedUserDataRoot) {
            $managedBin = Join-Path $placement.ManagedUserDataRoot "bin"
            if (Test-Path $managedBin -PathType Container) {
                $entries += $managedBin
            }
        }

        return @($entries | Where-Object { $_ })
    }

    $machineEntries = @()
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $chocoBin = Join-Path $env:ProgramData "chocolatey\bin"
        if (Test-Path $chocoBin -PathType Container) {
            $machineEntries += $chocoBin
        }
    }

    return @($machineEntries | Where-Object { $_ })
}

function Set-ScopedEnvironmentVariable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [AllowEmptyString()]
        [string]$Value,
        [ValidateSet('User', 'Machine', 'Process')]
        [string]$Scope
    )

    if ($Scope -eq 'Process') {
        Set-Item -Path "Env:$Name" -Value $Value
        return $true
    }

    try {
        [System.Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
        if (($Scope -eq 'User') -and ($Name -ieq 'Path')) {
            $env:DOTFILES_SESSION_USER_PATH = $Value
        }
        return $true
    }
    catch {
        if ($Scope -ne 'User') {
            throw
        }

        Write-LogWarn "Unable to persist $Name to the user environment. Continuing for the current session only."
        Set-Item -Path "Env:$Name" -Value $Value
        if ($Name -ieq 'Path') {
            $env:DOTFILES_SESSION_USER_PATH = $Value
        }
        return $false
    }
}

function Set-PathEntries {
    param(
        [ValidateSet('User', 'Machine')]
        [string]$Scope,
        [string[]]$Entries
    )

    $newValue = (($Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';')
    [void](Set-ScopedEnvironmentVariable -Name 'Path' -Value $newValue -Scope $Scope)
}

function Repair-PathScope {
    param(
        [ValidateSet('User', 'Machine')]
        [string]$Scope,
        [string[]]$InheritedEntries = @()
    )

    $current = [System.Environment]::GetEnvironmentVariable("Path", $Scope)
    $entries = Split-PathEntries -PathValue $current
    $normalizedEntries = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $inheritedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in $InheritedEntries) {
        $normalizedInherited = Format-PathEntryText -Entry $entry
        if ($normalizedInherited) {
            [void]$inheritedSet.Add($normalizedInherited)
        }
    }

    foreach ($preferred in Get-PreferredPathEntries -Scope $Scope) {
        $normalizedPreferred = Format-PathEntryText -Entry $preferred
        if (-not $normalizedPreferred) {
            continue
        }

        if ($seen.Add($normalizedPreferred)) {
            $normalizedEntries.Add($normalizedPreferred)
        }
    }

    foreach ($entry in $entries) {
        $normalized = Format-PathEntryText -Entry $entry
        if (-not $normalized) {
            continue
        }

        if (Test-IsStalePathEntry -Entry $normalized) {
            continue
        }

        if (
            ($Scope -eq 'User') -and
            $env:APPDATA -and
            ($normalized -ieq (Join-Path $env:APPDATA "fnm\aliases\default"))
        ) {
            continue
        }

        if (($Scope -eq 'User') -and $inheritedSet.Contains($normalized)) {
            continue
        }

        if ($seen.Add($normalized)) {
            $normalizedEntries.Add($normalized)
        }
    }

    Set-PathEntries -Scope $Scope -Entries $normalizedEntries
    return @($normalizedEntries)
}

function Repair-StandardPaths {
    param([bool]$IsAdmin = $false)

    $machineEntries = Split-PathEntries -PathValue ([System.Environment]::GetEnvironmentVariable("Path", "Machine"))
    if ($IsAdmin) {
        $machineEntries = Repair-PathScope -Scope Machine
    }

    [void](Repair-PathScope -Scope User -InheritedEntries $machineEntries)
    Update-Path
}

function Add-PathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Entry,
        [ValidateSet('User', 'Machine')]
        [string]$Scope = 'User'
    )

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return $false
    }

    $normalizedEntry = Format-PathEntryText -Entry $Entry
    $current = [System.Environment]::GetEnvironmentVariable("Path", $Scope)
    $parts = Split-PathEntries -PathValue $current

    foreach ($part in $parts) {
        if ((Format-PathEntryText -Entry $part) -ieq $normalizedEntry) {
            return $false
        }
    }

    $newPath = if ($parts.Count -gt 0) { ($parts + $normalizedEntry) -join ';' } else { $normalizedEntry }
    [void](Set-ScopedEnvironmentVariable -Name 'Path' -Value $newPath -Scope $Scope)
    return $true
}

function Update-StandardPaths {
    param([bool]$IsAdmin = $false)

    $updated = $false

    foreach ($entry in Get-PreferredPathEntries -Scope User) {
        if (-not (Test-Path $entry -PathType Container)) {
            continue
        }

        if (Add-PathEntry -Entry $entry -Scope User) {
            $updated = $true
        }
    }

    if ($IsAdmin) {
        foreach ($entry in Get-PreferredPathEntries -Scope Machine) {
            if (-not (Test-Path $entry -PathType Container)) {
                continue
            }

            if (Add-PathEntry -Entry $entry -Scope Machine) {
                $updated = $true
            }
        }
    }

    Repair-StandardPaths -IsAdmin $IsAdmin
    return $updated
}

Export-ModuleMember -Function Set-PlacementOverride, Get-PlacementConfig, Get-PreferredDrive, Get-ManagedPlacement, `
    Get-PackageCatalog, Get-RuntimePolicy, Get-ManagedPackages, Split-PathEntries, Format-PathEntryText, `
    Test-IsStalePathEntry, Get-PreferredPathEntries, Set-PathEntries, Repair-PathScope, Repair-StandardPaths, `
    Add-PathEntry, Update-StandardPaths, Set-ScopedEnvironmentVariable
