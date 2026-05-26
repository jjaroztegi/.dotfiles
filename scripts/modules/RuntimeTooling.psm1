Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\Common.psm1") -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\SetupEnvironment.psm1") -Force

function Get-UserShimRoot {
    return (Join-Path $env:USERPROFILE ".local\bin")
}

function Get-UserPyenvRoot {
    return (Join-Path $env:USERPROFILE ".pyenv\pyenv-win")
}

function Get-UserPyenvCloneRoot {
    return (Split-Path -Parent (Get-UserPyenvRoot))
}

function Get-FnmDefaultAliasRoot {
    return (Join-Path $env:APPDATA "fnm\aliases\default")
}

function Get-FnmRoot {
    return (Join-Path $env:APPDATA "fnm")
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FilePath $($Arguments -join ' ')"
    }
}

function Get-TrimmedLines {
    param([object[]]$InputObject)

    return @(
        $InputObject |
            ForEach-Object { "$_".Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-HighestVersionMatch {
    param(
        [string[]]$Candidates,
        [string]$MajorMinor
    )

    $matching = @(
        $Candidates |
            Where-Object { $_ -match ('^{0}\.\d+$' -f [regex]::Escape($MajorMinor)) } |
            Sort-Object { [version]$_ }
    )

    if ($matching.Count -gt 0) {
        return $matching[-1]
    }

    return $null
}

function Set-UserEnvironmentVariableIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $currentValue = [System.Environment]::GetEnvironmentVariable($Name, 'User')
    if ($currentValue -ceq $Value) {
        return
    }

    [void](Set-ScopedEnvironmentVariable -Name $Name -Value $Value -Scope User)
}

function Invoke-GitExternalCommand {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is required to install pyenv-win automatically."
    }

    Invoke-ExternalCommand -FilePath 'git' -Arguments $Arguments
}

function Update-PyenvWinGitCheckout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CloneRoot
    )

    $status = Get-TrimmedLines -InputObject (& git -C $CloneRoot status --porcelain 2>$null)
    if ($status.Count -gt 0) {
        $nonCacheChanges = @($status | Where-Object { $_ -notmatch '^\s*M\s+pyenv-win/\.versions_cache\.xml$' })
        if ($nonCacheChanges.Count -gt 0) {
            Write-LogWarn "pyenv-win checkout at $CloneRoot has local changes. Skipping automatic refresh."
            return
        }

        Invoke-GitExternalCommand -Arguments @('-C', $CloneRoot, 'checkout', '--', 'pyenv-win/.versions_cache.xml')
    }

    Invoke-GitExternalCommand -Arguments @('-C', $CloneRoot, 'fetch', 'origin', 'master')
    $branch = @(& git -C $CloneRoot rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1)[0]
    if ($branch -eq 'HEAD') {
        Invoke-GitExternalCommand -Arguments @('-C', $CloneRoot, 'checkout', '-B', 'master', 'origin/master')
        return
    }

    Invoke-GitExternalCommand -Arguments @('-C', $CloneRoot, 'pull', '--ff-only', 'origin', 'master')
}

function Install-PyenvWinFromArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CloneRoot
    )

    $parentDir = Split-Path -Parent $CloneRoot
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $CloneRoot -PathType Container) {
        $existingItems = @(Get-ChildItem -LiteralPath $CloneRoot -Force -ErrorAction SilentlyContinue)
        if ($existingItems.Count -gt 0) {
            throw "Cannot install pyenv-win because '$CloneRoot' already exists and is not empty."
        }
    }

    $archivePath = Join-Path $env:TEMP 'pyenv-win.zip'
    $extractRoot = Join-Path $env:TEMP ("pyenv-win-{0}" -f [guid]::NewGuid())

    try {
        Write-LogInfo "Installing pyenv-win from the official release archive..."
        Invoke-WebRequest -Uri 'https://github.com/pyenv-win/pyenv-win/archive/refs/heads/master.zip' -OutFile $archivePath
        Expand-Archive -Path $archivePath -DestinationPath $extractRoot -Force
        $sourceRoot = Get-ChildItem -LiteralPath $extractRoot -Directory | Select-Object -First 1
        if (-not $sourceRoot) {
            throw "pyenv-win archive did not contain an extracted directory."
        }

        Move-Item -LiteralPath $sourceRoot.FullName -Destination $CloneRoot -Force
    }
    finally {
        Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-PyenvWinInstalled {
    param([switch]$Apply)

    $pyenvRoot = Get-UserPyenvRoot
    $cloneRoot = Get-UserPyenvCloneRoot
    $pyenvBin = Join-Path $pyenvRoot 'bin'
    $pyenvShims = Join-Path $pyenvRoot 'shims'

    if (-not (Test-Path -LiteralPath $pyenvRoot -PathType Container)) {
        if (-not $Apply) {
            Write-LogDryRun "Would install pyenv-win into $cloneRoot"
            return
        }
        else {
            if (Test-Path -LiteralPath (Join-Path $cloneRoot '.git') -PathType Container) {
                Write-LogInfo "Updating pyenv-win checkout in $cloneRoot..."
                Update-PyenvWinGitCheckout -CloneRoot $cloneRoot
            }
            else {
                $parentDir = Split-Path -Parent $cloneRoot
                if ($parentDir -and -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
                    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                }

                if (Test-Path -LiteralPath $cloneRoot -PathType Container) {
                    $existingItems = @(Get-ChildItem -LiteralPath $cloneRoot -Force -ErrorAction SilentlyContinue)
                    if ($existingItems.Count -gt 0) {
                        throw "Cannot install pyenv-win because '$cloneRoot' already exists and is not a git checkout."
                    }
                }

                if (Get-Command git -ErrorAction SilentlyContinue) {
                    Write-LogInfo "Installing pyenv-win from the official git repository..."
                    Invoke-GitExternalCommand -Arguments @('clone', 'https://github.com/pyenv-win/pyenv-win.git', $cloneRoot)
                }
                else {
                    Install-PyenvWinFromArchive -CloneRoot $cloneRoot
                }
            }
        }
    }
    elseif ($Apply -and (Test-Path -LiteralPath (Join-Path $cloneRoot '.git') -PathType Container)) {
        Write-LogInfo "Refreshing pyenv-win checkout in $cloneRoot..."
        Update-PyenvWinGitCheckout -CloneRoot $cloneRoot
    }

    $pyenvHome = $pyenvRoot.TrimEnd('\') + '\'
    Set-UserEnvironmentVariableIfNeeded -Name 'PYENV' -Value $pyenvHome
    Set-UserEnvironmentVariableIfNeeded -Name 'PYENV_ROOT' -Value $pyenvHome
    Set-UserEnvironmentVariableIfNeeded -Name 'PYENV_HOME' -Value $pyenvHome
    [void](Add-PathEntry -Entry $pyenvBin -Scope User)
    [void](Add-PathEntry -Entry $pyenvShims -Scope User)
    Update-StandardPaths -IsAdmin (Test-IsAdmin) | Out-Null
    Update-Path
}

function Remove-ObsoleteRuntimeWrappers {
    param([switch]$Apply)

    $shimRoot = Get-UserShimRoot
    $obsoleteWrapperNames = @(
        'fnm.cmd', 'fnm.ps1', 'fnm',
        'node.cmd', 'node.ps1', 'node',
        'npm.cmd', 'npm.ps1', 'npm',
        'npx.cmd', 'npx.ps1', 'npx',
        'corepack.cmd', 'corepack.ps1', 'corepack',
        'python.cmd', 'python.ps1', 'python',
        'python3.cmd', 'python3.ps1', 'python3',
        'pip.cmd', 'pip.ps1', 'pip',
        'pip3.cmd', 'pip3.ps1', 'pip3'
    )

    foreach ($wrapperName in $obsoleteWrapperNames) {
        $wrapperPath = Join-Path $shimRoot $wrapperName
        if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) {
            continue
        }

        if (-not (Test-IsObsoleteRuntimeWrapper -Path $wrapperPath)) {
            Write-LogSkip "Leaving non-dotfiles runtime wrapper in place: $wrapperPath"
            continue
        }

        if ($Apply) {
            Remove-Item -LiteralPath $wrapperPath -Force
            Write-LogInfo "Removed obsolete runtime wrapper $wrapperPath"
        }
        else {
            Write-LogDryRun "Would remove obsolete runtime wrapper $wrapperPath"
        }
    }
}

function Test-IsObsoleteRuntimeWrapper {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    }
    catch {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($content)) {
        return $false
    }

    $normalized = $content -replace "`r`n", "`n"
    $targetsManagedRuntime = (
        $normalized -like '*\AppData\Roaming\fnm\*' -or
        $normalized -like '*\fnm.exe*' -or
        $normalized -like '*\.pyenv\pyenv-win\shims\*' -or
        $normalized -like '*\.pyenv\pyenv-win\versions\*'
    )
    if (-not $targetsManagedRuntime) {
        return $false
    }

    $isLegacyCmdWrapper = (
        $normalized -match '(?ms)^@echo off\nsetlocal\n".+"\s+%\*\nset "exitCode=%ERRORLEVEL%"\nendlocal & exit /b %exitCode%\n?$'
    )
    $isLegacyPsWrapper = (
        $normalized -match '(?ms)^& ".+"\s+@args\nexit \$LASTEXITCODE\n?$'
    )
    $isLegacyShWrapper = (
        $normalized -match '(?ms)^#!/usr/bin/env sh\nexec ".+"\s+"\$@"\n?$'
    )

    return ($isLegacyCmdWrapper -or $isLegacyPsWrapper -or $isLegacyShWrapper)
}

function Register-FnmDefaultRuntimePath {
    param([switch]$Apply)

    $fnmRoot = Get-FnmRoot
    $defaultAliasRoot = Get-FnmDefaultAliasRoot

    if ($Apply) {
        Set-UserEnvironmentVariableIfNeeded -Name 'FNM_DIR' -Value $fnmRoot
        if (-not (Test-Path -LiteralPath $defaultAliasRoot -PathType Container)) {
            throw "fnm default alias is missing at $defaultAliasRoot"
        }

        [void](Add-PathEntry -Entry $defaultAliasRoot -Scope User)
    }
    else {
        Write-LogDryRun "Would persist FNM_DIR=$fnmRoot"
        Write-LogDryRun "Would register fnm default alias path in user PATH: $defaultAliasRoot"
    }
}

function Set-NodeRuntimeState {
    param([switch]$Apply)

    $runtimePolicy = (Get-RuntimePolicy).node
    $fnmRoot = Get-FnmRoot
    $env:FNM_DIR = $fnmRoot
    if ($Apply) {
        Set-UserEnvironmentVariableIfNeeded -Name 'FNM_DIR' -Value $fnmRoot
    }

    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        if ($Apply) {
            Write-LogWarn "fnm is not installed yet. Deferring Node.js runtime configuration until after the admin phase installs managed packages."
            return
        }

        Write-LogDryRun "Would configure Node.js via fnm once it is installed."
        return
    }

    $fnmPath = (Get-Command fnm -ErrorAction Stop).Source
    if (-not $fnmPath) {
        $fnmPath = (Get-Command fnm -ErrorAction Stop).Path
    }

    if ($Apply) {
        Write-LogInfo "Ensuring Node.js $($runtimePolicy.channel) v$($runtimePolicy.version) via fnm..."
        Invoke-ExternalCommand -FilePath $fnmPath -Arguments @('install', $runtimePolicy.version)
        Invoke-ExternalCommand -FilePath $fnmPath -Arguments @('default', $runtimePolicy.version)
    }
    else {
        Write-LogDryRun "Would install/set default Node.js $($runtimePolicy.version) via fnm"
    }

    Remove-ObsoleteRuntimeWrappers -Apply:$Apply
    Register-FnmDefaultRuntimePath -Apply:$Apply
}

function Set-PythonRuntimeState {
    param([switch]$Apply)

    $runtimePolicy = (Get-RuntimePolicy).python
    if ($Apply -or -not (Get-Command pyenv -ErrorAction SilentlyContinue)) {
        Ensure-PyenvWinInstalled -Apply:$Apply
    }

    if (-not (Get-Command pyenv -ErrorAction SilentlyContinue)) {
        if (-not $Apply) {
            Write-LogDryRun "Would ensure pyenv-win is installed and available on PATH"
            return
        }
        throw "pyenv-win is required but not installed."
    }

    $pyenvPath = (Get-Command pyenv -ErrorAction Stop).Source
    if (-not $pyenvPath) {
        $pyenvPath = (Get-Command pyenv -ErrorAction Stop).Path
    }

    $installedVersions = Get-TrimmedLines -InputObject (& $pyenvPath versions --bare 2>$null)
    $availableVersions = Get-TrimmedLines -InputObject (& $pyenvPath install --list 2>$null)
    $selectedVersion = Get-HighestVersionMatch -Candidates $availableVersions -MajorMinor $runtimePolicy.majorMinor

    if (-not $selectedVersion) {
        $selectedVersion = Get-HighestVersionMatch -Candidates $installedVersions -MajorMinor $runtimePolicy.majorMinor
    }

    if (-not $selectedVersion) {
        $selectedVersion = $runtimePolicy.fallbackExactVersion
    }

    if ([string]::IsNullOrWhiteSpace($selectedVersion)) {
        throw "Unable to resolve a supported pyenv-win Python version for $($runtimePolicy.majorMinor)."
    }

    $pyenvBin = Join-Path (Get-UserPyenvRoot) "bin"
    $pyenvShims = Join-Path (Get-UserPyenvRoot) "shims"

    if ($Apply) {
        if (-not ($installedVersions -contains $selectedVersion)) {
            Write-LogInfo "Installing Python $selectedVersion via pyenv-win..."
            Invoke-ExternalCommand -FilePath $pyenvPath -Arguments @('install', $selectedVersion)
        }

        Write-LogInfo "Setting pyenv-win global Python to $selectedVersion..."
        Invoke-ExternalCommand -FilePath $pyenvPath -Arguments @('global', $selectedVersion)
        Invoke-ExternalCommand -FilePath $pyenvPath -Arguments @('rehash')
        [void](Add-PathEntry -Entry $pyenvBin -Scope User)
        [void](Add-PathEntry -Entry $pyenvShims -Scope User)
    }
    else {
        Write-LogDryRun "Would ensure pyenv-win Python $selectedVersion and register $pyenvBin / $pyenvShims in user PATH"
    }
}

function Invoke-RuntimeToolingSetup {
    [CmdletBinding()]
    param([switch]$Execute)

    Write-LogInfo "Applying runtime policy..."
    Set-NodeRuntimeState -Apply:$Execute
    Set-PythonRuntimeState -Apply:$Execute

    if ($Execute) {
        Update-StandardPaths -IsAdmin (Test-IsAdmin) | Out-Null
        Write-LogOK "Runtime tooling is configured."
    }
}

Export-ModuleMember -Function Invoke-RuntimeToolingSetup
