Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\Common.psm1") -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\SetupEnvironment.psm1") -Force

function Add-StringArgs {
    param(
        [Parameter(Mandatory = $true)]
        [object]$List,
        [Parameter(Mandatory = $true)]
        [string[]]$Values
    )

    foreach ($value in $Values) {
        [void]$List.Add($value)
    }
}

function Invoke-ChocoCommand {
    param([string[]]$Arguments)

    $command = if ((Test-IsAdmin) -or -not (Get-Command sudo -ErrorAction SilentlyContinue)) {
        @('choco') + $Arguments
    }
    else {
        @('sudo', 'choco') + $Arguments
    }

    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList (@('/d', '/c') + $command) -NoNewWindow -Wait -PassThru

    return $proc.ExitCode
}

function Test-InstallExitCodeSuccess {
    param([int]$ExitCode)

    return $ExitCode -in @(0, 1641, 3010)
}

function Test-InstallExitCodeRebootRequired {
    param([int]$ExitCode)

    return $ExitCode -in @(1641, 3010)
}

function Get-PackageCommands {
    param([psobject]$Package)

    if ($Package.commands) {
        return @($Package.commands)
    }

    if ($Package.ExecutableName) {
        return @($Package.ExecutableName)
    }

    return @()
}

function Test-PackageInstalledByManager {
    param(
        [psobject]$Package,
        [ValidateSet('winget', 'choco', 'scoop')]
        [string]$Manager
    )

    switch ($Manager) {
        'winget' {
            if (-not $Package.wingetId -or -not (Get-Command winget -ErrorAction SilentlyContinue)) {
                return $false
            }

            $wingetList = winget list --id $Package.wingetId --exact --accept-source-agreements 2>$null
            return ($LASTEXITCODE -eq 0 -and $wingetList -notmatch "No installed package")
        }
        'choco' {
            if (-not $Package.chocoId -or -not (Get-Command choco -ErrorAction SilentlyContinue)) {
                return $false
            }

            $chocoList = choco list --local-only --exact --id-only -r $Package.chocoId 2>$null
            return ($chocoList -contains $Package.chocoId)
        }
        'scoop' {
            if (-not $Package.scoopId -or -not (Get-Command scoop -ErrorAction SilentlyContinue)) {
                return $false
            }

            $bucketName = ($Package.scoopId -split '/')[-1]
            $scoopList = scoop list 2>$null | Select-Object -ExpandProperty Name
            return ($scoopList -contains $bucketName)
        }
    }

    return $false
}

function Test-SoftwareInstalled {
    param(
        [string]$Name,
        [string]$ExecutableName,
        [string]$WingetId,
        [string]$ChocoId
    )

    $package = [pscustomobject]@{
        name = $Name
        commands = if ($ExecutableName) { @($ExecutableName) } else { @() }
        wingetId = $WingetId
        chocoId = $ChocoId
        scoopId = $null
    }

    return (Test-PackageInstalledByManager -Package $package -Manager winget) -or
        (Test-PackageInstalledByManager -Package $package -Manager choco)
}

function Get-ManagerOrder {
    param([psobject]$Package)

    $managers = [System.Collections.Generic.List[string]]::new()
    foreach ($manager in @($Package.preferredManager) + @($Package.fallbackManagers)) {
        if ([string]::IsNullOrWhiteSpace($manager)) {
            continue
        }

        if (-not $managers.Contains($manager)) {
            $managers.Add($manager)
        }
    }

    if ($managers.Count -eq 0) {
        foreach ($manager in @('winget', 'choco', 'scoop')) {
            if ($Package."${manager}Id") {
                $managers.Add($manager)
            }
        }
    }

    return @($managers)
}

function Get-ResolvedPathIdentity {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $normalized = $Path.Trim().Trim('"')
    if ($normalized.Length -gt 3 -and $normalized.EndsWith("\")) {
        $normalized = $normalized.TrimEnd("\")
    }

    if (-not $normalized) {
        return $null
    }

    $extension = [System.IO.Path]::GetExtension($normalized)
    if ([string]::IsNullOrWhiteSpace($extension)) {
        return $normalized
    }

    $withoutExtension = [System.IO.Path]::ChangeExtension($normalized, '')
    if ($withoutExtension.EndsWith('.')) {
        $withoutExtension = $withoutExtension.TrimEnd('.')
    }

    return $withoutExtension
}

function Get-CommandResolutions {
    param([psobject]$Package)

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($commandName in Get-PackageCommands -Package $Package) {
        $resolved = & where.exe $commandName 2>$null
        $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in @($resolved)) {
            if ([string]::IsNullOrWhiteSpace($item)) {
                continue
            }

            if ($item -like '*\OpenAI.Codex_*\app\resources\*') {
                continue
            }

            if (-not $seenPaths.Add($item)) {
                continue
            }

            $results.Add([pscustomobject]@{
                    Command  = $commandName
                    Path     = $item
                    Identity = Get-ResolvedPathIdentity -Path $item
                }) | Out-Null
        }
    }

    return @($results)
}

function Get-PackageState {
    param([psobject]$Package)

    $installedManagers = [System.Collections.Generic.List[string]]::new()
    foreach ($manager in @('winget', 'choco', 'scoop')) {
        if (Test-PackageInstalledByManager -Package $Package -Manager $manager) {
            $installedManagers.Add($manager)
        }
    }

    $commands = Get-PackageCommands -Package $Package
    $accessibleCommand = $null
    foreach ($commandName in $commands) {
        if (Test-CommandAccessible -Name $commandName) {
            $accessibleCommand = $commandName
            break
        }
    }

    $resolutionRecords = Get-CommandResolutions -Package $Package
    $hasPathConflict = $false
    foreach ($group in @($resolutionRecords | Group-Object Command)) {
        $identities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($record in @($group.Group)) {
            if ($record.Identity) {
                [void]$identities.Add($record.Identity)
            }
        }

        if ($identities.Count -gt 1) {
            $hasPathConflict = $true
            break
        }
    }

    return [pscustomobject]@{
        Package = $Package
        InstalledManagers = @($installedManagers)
        ResolvedPaths = @($resolutionRecords | Select-Object -ExpandProperty Path)
        Accessible = [bool]$accessibleCommand
        AccessibleCommand = $accessibleCommand
        HasManagerConflict = ($installedManagers.Count -gt 1)
        HasPathConflict = if ($Package.ignorePathConflict) { $false } else { $hasPathConflict }
    }
}

function Get-PackageInstallLocation {
    param([psobject]$Package)

    if (-not $Package.supportsPreferredDrivePlacement) {
        return $null
    }

    $placement = Get-ManagedPlacement
    if (-not $placement.PreferredDrive) {
        return $null
    }

    $rootType = if ($Package.preferredDriveRootType) { $Package.preferredDriveRootType } else { 'app' }
    $baseRoot = if ($rootType -eq 'user') { $placement.ManagedUserDataRoot } else { $placement.ManagedAppRoot }
    if (-not $baseRoot) {
        return $null
    }

    return (Join-Path $baseRoot $Package.key)
}

function Get-ManagedShimRoot {
    return (Join-Path $env:USERPROFILE ".local\bin")
}

function Get-WingetPackageRoots {
    param([psobject]$Package)

    if (-not $Package.wingetId) {
        return @()
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (-not (Test-Path $packagesRoot -PathType Container)) {
        return @()
    }

    $pattern = "$($Package.wingetId)_*"
    return @(
        Get-ChildItem $packagesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $pattern } |
            Sort-Object LastWriteTime -Descending
    )
}

function Get-ManagedCommandSearchRoots {
    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @(
            $env:ProgramFiles,
            ${env:ProgramFiles(x86)},
            (Join-Path $env:LOCALAPPDATA "Programs")
        )) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path $root -PathType Container) -and -not $roots.Contains($root)) {
            [void]$roots.Add($root)
        }
    }

    return @($roots)
}

function Get-ManagedDirectoryHints {
    param([psobject]$Package)

    $hints = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($value in @($Package.name, $Package.key, $Package.wingetId)) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        foreach ($candidate in @(
                $value,
                ($value -replace '^[^.]+\.', ''),
                ($value -replace '[._]', '-'),
                ($value -replace '[._-]', ' '),
                ($value -replace '[^A-Za-z0-9 -]', ''),
                ($value -replace '[^A-Za-z0-9]', '')
            )) {
            $trimmed = $candidate.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed) -and $seen.Add($trimmed)) {
                [void]$hints.Add($trimmed)
            }
        }
    }

    return @($hints)
}

function Resolve-ManagedCommandTarget {
    param(
        [psobject]$Package,
        [string]$CommandName
    )

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return $null
    }

    $candidateExtensions = @('.exe', '.cmd', '.bat', '.ps1', '.com')
    foreach ($root in Get-WingetPackageRoots -Package $Package) {
        foreach ($extension in $candidateExtensions) {
            $candidate = Join-Path $root.FullName ($CommandName + $extension)
            if (Test-Path $candidate -PathType Leaf) {
                return $candidate
            }
        }

        $fallbackMatch = Get-ChildItem $root.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.BaseName -ieq $CommandName) -and
                ($candidateExtensions -contains $_.Extension.ToLowerInvariant())
            } |
            Select-Object -First 1
        if ($fallbackMatch) {
            return $fallbackMatch.FullName
        }
    }

    $candidateExtensions = @('.exe', '.cmd', '.bat', '.ps1', '.com')
    $directoryHints = Get-ManagedDirectoryHints -Package $Package
    foreach ($root in Get-ManagedCommandSearchRoots) {
        foreach ($hint in $directoryHints) {
            foreach ($extension in $candidateExtensions) {
                foreach ($relativePath in @(
                        (Join-Path $hint ($CommandName + $extension)),
                        (Join-Path $hint (Join-Path 'bin' ($CommandName + $extension)))
                    )) {
                    $candidate = Join-Path $root $relativePath
                    if (Test-Path $candidate -PathType Leaf) {
                        return $candidate
                    }
                }
            }
        }

        foreach ($extension in $candidateExtensions) {
            $fallbackMatch = Get-ChildItem $root -Filter ($CommandName + $extension) -File -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($fallbackMatch) {
                return $fallbackMatch.FullName
            }
        }
    }

    return $null
}

function New-CommandShim {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $shimRoot = Get-ManagedShimRoot
    if (-not (Test-Path $shimRoot -PathType Container)) {
        New-Item -Path $shimRoot -ItemType Directory -Force | Out-Null
    }

    $shimPath = Join-Path $shimRoot "$CommandName.cmd"
    $quotedTarget = '"' + $TargetPath + '"'
    $extension = [System.IO.Path]::GetExtension($TargetPath).ToLowerInvariant()

    $shimContent = switch ($extension) {
        '.ps1' {
@"
@echo off
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  pwsh -NoLogo -NoProfile -File $quotedTarget %*
) else (
  powershell -NoLogo -NoProfile -File $quotedTarget %*
)
exit /b %ERRORLEVEL%
"@
        }
        '.cmd' {
@"
@echo off
call $quotedTarget %*
exit /b %ERRORLEVEL%
"@
        }
        '.bat' {
@"
@echo off
call $quotedTarget %*
exit /b %ERRORLEVEL%
"@
        }
        default {
@"
@echo off
$quotedTarget %*
exit /b %ERRORLEVEL%
"@
        }
    }

    Set-Content -Path $shimPath -Value $shimContent -Encoding ASCII
    return $shimPath
}

function Update-ManagedCommandShims {
    param([psobject]$Package)

    if (-not $Package.manualPostInstallPathRegistration) {
        return
    }

    foreach ($commandName in Get-PackageCommands -Package $Package) {
        $targetPath = Resolve-ManagedCommandTarget -Package $Package -CommandName $commandName
        if (-not $targetPath) {
            Write-LogWarn "Unable to resolve a command target for '$commandName' in package '$($Package.name)' yet. Continuing without a shim."
            continue
        }

        $shimPath = New-CommandShim -CommandName $commandName -TargetPath $targetPath
        Write-LogInfo "Registered $commandName shim at $shimPath"
    }
}

function Invoke-WingetInstall {
    param([psobject]$Package)

    $wingetArgs = [System.Collections.Generic.List[string]]::new()
    Add-StringArgs -List $wingetArgs -Values @('install', '--id', $Package.wingetId, '-e', '--silent', '--disable-interactivity', '--accept-source-agreements', '--accept-package-agreements', '--source', 'winget')

    if ($Package.scope -eq 'user' -and $Package.supportsUserScopeInstall) {
        Add-StringArgs -List $wingetArgs -Values @('--scope', 'user')
    }
    elseif ($Package.scope -eq 'machine' -and (Test-IsAdmin)) {
        Add-StringArgs -List $wingetArgs -Values @('--scope', 'machine')
    }

    $installLocation = Get-PackageInstallLocation -Package $Package
    $usedLocation = $false
    if ($installLocation) {
        $parentDir = Split-Path -Parent $installLocation
        if ($parentDir -and -not (Test-Path $parentDir -PathType Container)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        Add-StringArgs -List $wingetArgs -Values @('--location', $installLocation)
        $usedLocation = $true
        Write-LogInfo "Using preferred install location '$installLocation' for $($Package.name)."
    }

    & winget @wingetArgs | Out-Host
    $exitCode = $LASTEXITCODE

    if (($exitCode -ne 0) -and $usedLocation) {
        Write-LogWarn "Winget install with --location failed for $($Package.name). Retrying with package manager defaults."
        $retryArgs = @($wingetArgs | Where-Object { $_ -ne '--location' -and $_ -ne $installLocation })
        & winget @retryArgs | Out-Host
        $exitCode = $LASTEXITCODE
    }

    return $exitCode
}

function Invoke-WingetRepair {
    param([psobject]$Package)

    winget repair --id $Package.wingetId -e --disable-interactivity --accept-source-agreements --accept-package-agreements --source winget | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        return 0
    }

    Write-LogWarn "Winget repair failed for $($Package.name) with exit code $exitCode. Falling back to uninstall/install."
    winget uninstall --id $Package.wingetId -e --all-versions --force --disable-interactivity --accept-source-agreements --source winget | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Winget uninstall failed for $($Package.name) during repair fallback with exit code $LASTEXITCODE."
    }

    return (Invoke-WingetInstall -Package $Package)
}

function Invoke-ChocoInstall {
    param([psobject]$Package)

    return (Invoke-ChocoCommand -Arguments @('install', $Package.chocoId, '-y'))
}

function Invoke-ScoopInstall {
    param([psobject]$Package)

    scoop install $Package.scoopId | Out-Host
    return $LASTEXITCODE
}

function Invoke-ManualPackageInstall {
    param([psobject]$Package)

    switch ($Package.key) {
        'ast-grep' {
            $assetName = switch ($env:PROCESSOR_ARCHITECTURE.ToUpperInvariant()) {
                'ARM64' { 'app-aarch64-pc-windows-msvc.zip' }
                'X86' { 'app-i686-pc-windows-msvc.zip' }
                default { 'app-x86_64-pc-windows-msvc.zip' }
            }

            $installRoot = Join-Path $env:LOCALAPPDATA 'Programs\ast-grep'
            $zipPath = Join-Path $env:TEMP $assetName
            $headers = @{ 'User-Agent' = 'dotfiles-bootstrap' }

            try {
                Write-LogInfo "Installing $($Package.name) via official release archive..."
                $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/ast-grep/ast-grep/releases/latest' -Headers $headers
                $asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
                if (-not $asset) {
                    throw "Unable to find asset '$assetName' in the latest ast-grep release."
                }

                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -Headers $headers
                if (Test-Path $installRoot) {
                    Remove-Item $installRoot -Recurse -Force
                }

                New-Item -Path $installRoot -ItemType Directory -Force | Out-Null
                Expand-Archive -Path $zipPath -DestinationPath $installRoot -Force
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                return 0
            }
            catch {
                Write-LogWarn "Manual install failed for $($Package.name): $($_.Exception.Message)"
                return 1
            }
            finally {
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            }
        }
        'btop' {
            $assetName = 'btop4win-x64.zip'
            $installParent = Join-Path $env:LOCALAPPDATA 'Programs'
            $installRoot = Join-Path $installParent 'btop4win'
            $zipPath = Join-Path $env:TEMP $assetName
            $headers = @{ 'User-Agent' = 'dotfiles-bootstrap' }

            try {
                Write-LogInfo "Installing $($Package.name) via official release archive..."
                $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/aristocratos/btop4win/releases/latest' -Headers $headers
                $asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
                if (-not $asset) {
                    throw "Unable to find asset '$assetName' in the latest btop4win release."
                }

                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -Headers $headers
                if (Test-Path $installRoot) {
                    Remove-Item $installRoot -Recurse -Force
                }

                New-Item -Path $installParent -ItemType Directory -Force | Out-Null
                Expand-Archive -Path $zipPath -DestinationPath $installParent -Force
                $targetPath = Join-Path $installRoot 'btop4win.exe'
                if (-not (Test-Path $targetPath -PathType Leaf)) {
                    throw "Expected executable was not found at '$targetPath'."
                }

                $shimPath = New-CommandShim -CommandName 'btop' -TargetPath $targetPath
                Write-LogInfo "Registered btop shim at $shimPath"
                return 0
            }
            catch {
                Write-LogWarn "Manual install failed for $($Package.name): $($_.Exception.Message)"
                return 1
            }
            finally {
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $null
}

function Uninstall-PackageFromManager {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Package,
        [Parameter(Mandatory = $true)]
        [ValidateSet('winget', 'choco', 'scoop')]
        [string]$Manager
    )

    if (-not (Test-PackageInstalledByManager -Package $Package -Manager $Manager)) {
        return
    }

    switch ($Manager) {
        'winget' {
            if ($PSCmdlet.ShouldProcess($Package.name, "Uninstall via Winget")) {
                winget uninstall --id $Package.wingetId -e --all-versions --force --disable-interactivity --accept-source-agreements --source winget | Out-Host
                if ($LASTEXITCODE -ne 0) {
                    throw "Winget uninstall failed for $($Package.name) with exit code $LASTEXITCODE."
                }
            }
        }
        'choco' {
            if ($PSCmdlet.ShouldProcess($Package.name, "Uninstall via Chocolatey")) {
                $exitCode = Invoke-ChocoCommand -Arguments @('uninstall', $Package.chocoId, '-y')
                if ($exitCode -ne 0) {
                    throw "Chocolatey uninstall failed for $($Package.name) with exit code $exitCode."
                }
            }
        }
        'scoop' {
            if ($PSCmdlet.ShouldProcess($Package.name, "Uninstall via Scoop")) {
                scoop uninstall $Package.scoopId | Out-Host
                if ($LASTEXITCODE -ne 0) {
                    throw "Scoop uninstall failed for $($Package.name) with exit code $LASTEXITCODE."
                }
            }
        }
    }
}

function Install-ManagedPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory = $true)][psobject]$Package)

    $state = Get-PackageState -Package $Package
    $canonicalManager = $Package.preferredManager
    if (
        $state.Accessible -and
        ($state.InstalledManagers -contains $canonicalManager) -and
        -not $state.HasManagerConflict -and
        -not $state.HasPathConflict
    ) {
        Write-LogSkip "$($Package.name) is already installed and accessible."
        return
    }

    if ($state.HasManagerConflict) {
        Write-LogWarn "$($Package.name) is installed by multiple managers: $($state.InstalledManagers -join ', ')"
    }
    if ($state.HasPathConflict) {
        Write-LogWarn "$($Package.name) resolves from multiple paths: $($state.ResolvedPaths -join '; ')"
    }

    $attemptedManager = $null
    $failedManagers = [System.Collections.Generic.List[string]]::new()
    foreach ($manager in Get-ManagerOrder -Package $Package) {
        $idProperty = "${manager}Id"
        if (-not $Package.$idProperty) {
            continue
        }

        if (-not (Get-Command $manager -ErrorAction SilentlyContinue)) {
            continue
        }

        if ($PSCmdlet.ShouldProcess($Package.name, "Install via $manager")) {
            $attemptedManager = $manager
            Write-LogInfo "Installing $($Package.name) via $manager..."
            $exitCode = switch ($manager) {
                'winget' {
                    if (($state.InstalledManagers -contains 'winget') -and -not $state.Accessible) {
                        Invoke-WingetRepair -Package $Package
                    }
                    else {
                        Invoke-WingetInstall -Package $Package
                    }
                }
                'choco' { Invoke-ChocoInstall -Package $Package }
                'scoop' { Invoke-ScoopInstall -Package $Package }
            }

            if (Test-InstallExitCodeSuccess -ExitCode $exitCode) {
                Write-LogOK "Installed $($Package.name)"
                if (Test-InstallExitCodeRebootRequired -ExitCode $exitCode) {
                    Write-LogWarn "$($Package.name) requested a reboot to finish setup."
                }
                Update-ManagedCommandShims -Package $Package
                Update-StandardPaths -IsAdmin (Test-IsAdmin) | Out-Null
                return
            }

            $failure = "$manager install failed for $($Package.name) with exit code $exitCode."
            $failedManagers.Add($failure) | Out-Null
            Write-LogWarn $failure
        }
    }

    if ($attemptedManager) {
        $manualExitCode = Invoke-ManualPackageInstall -Package $Package
        if ($null -ne $manualExitCode) {
            if (Test-InstallExitCodeSuccess -ExitCode $manualExitCode) {
                Write-LogOK "Installed $($Package.name)"
                Update-ManagedCommandShims -Package $Package
                Update-StandardPaths -IsAdmin (Test-IsAdmin) | Out-Null
                return
            }

            $failedManagers.Add("manual install failed for $($Package.name) with exit code $manualExitCode.") | Out-Null
        }

        throw "Failed to install $($Package.name). $($failedManagers -join ' ')"
    }

    $manualExitCode = Invoke-ManualPackageInstall -Package $Package
    if ($null -ne $manualExitCode) {
        if (Test-InstallExitCodeSuccess -ExitCode $manualExitCode) {
            Write-LogOK "Installed $($Package.name)"
            Update-ManagedCommandShims -Package $Package
            Update-StandardPaths -IsAdmin (Test-IsAdmin) | Out-Null
            return
        }

        throw "Failed to install $($Package.name). Manual fallback failed with exit code $manualExitCode."
    }

    throw "Failed to install $($Package.name). No usable package manager is available for the configured catalog entry."
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

    $primaryManager = if ($WingetId) { 'winget' } elseif ($ChocoId) { 'choco' } else { 'scoop' }
    $fallbackManagers = [System.Collections.Generic.List[string]]::new()

    if ($primaryManager -ne 'winget' -and $WingetId) {
        $fallbackManagers.Add('winget')
    }
    if ($primaryManager -ne 'choco' -and $ChocoId) {
        $fallbackManagers.Add('choco')
    }
    if ($primaryManager -ne 'scoop' -and $ScoopId) {
        $fallbackManagers.Add('scoop')
    }

    $package = [pscustomobject]@{
        key = ($Name -replace '[^A-Za-z0-9]+', '-').ToLowerInvariant()
        name = $Name
        commands = if ($ExecutableName) { @($ExecutableName) } else { @() }
        preferredManager = $primaryManager
        fallbackManagers = @($fallbackManagers)
        wingetId = $WingetId
        chocoId = $ChocoId
        scoopId = $ScoopId
        scope = 'user'
        supportsPreferredDrivePlacement = $false
        preferredDriveRootType = $null
        supportsUserScopeInstall = $true
        manualPostInstallPathRegistration = $false
        retainedException = [bool]$ScoopId
        managed = $true
    }

    Install-ManagedPackage -Package $package -WhatIf:$WhatIfPreference
}

Export-ModuleMember -Function Test-SoftwareInstalled, Get-PackageState, Install-ManagedPackage, `
    Install-Software, Test-PackageInstalledByManager, Uninstall-PackageFromManager
