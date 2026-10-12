Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\Common.psm1") -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\SetupEnvironment.psm1") -Force

function Get-UserShimRoot {
    return (Join-Path $env:USERPROFILE ".local\bin")
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

function Set-UserEnvironmentVariableIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    Set-Item -Path "Env:$Name" -Value $Value
    $currentValue = [System.Environment]::GetEnvironmentVariable($Name, 'User')
    if ($currentValue -ceq $Value) {
        return
    }

    [void](Set-ScopedEnvironmentVariable -Name $Name -Value $Value -Scope User)
}

function Test-IsReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return [bool]($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint))
}

function Set-ConfigFileValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Separator,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Values
    )

    # Merge keys into an existing file so unrelated settings survive.
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            $lines.Add($line)
        }
    }

    foreach ($key in $Values.Keys) {
        $newLine = "$key$Separator$($Values[$key])"
        $pattern = '^\s*{0}\s*{1}' -f [regex]::Escape($key), [regex]::Escape($Separator.Trim())
        $index = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $pattern) {
                $index = $i
                break
            }
        }

        if ($index -ge 0) {
            $lines[$index] = $newLine
        }
        else {
            $lines.Add($newLine)
        }
    }

    New-Item -Path (Split-Path -Parent $Path) -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllLines($Path, $lines)
}

function Set-DevDirectoryEnvironment {
    param([switch]$Apply)

    $layout = Get-DevToolchainLayout
    if (-not $layout.PreferredDrive) {
        return
    }

    $drive = $layout.PreferredDrive
    $toolchains = $layout.ToolchainsRoot
    $cache = $layout.CacheRoot
    $variables = [ordered]@{
        UV_CACHE_DIR             = Join-Path $cache 'uv'
        UV_PYTHON_INSTALL_DIR    = Join-Path $toolchains 'uv\python'
        UV_TOOL_DIR              = Join-Path $toolchains 'uv\tools'
        UV_TOOL_BIN_DIR          = $layout.UvToolBin
        PIP_CACHE_DIR            = Join-Path $cache 'pip'
        PLAYWRIGHT_BROWSERS_PATH = Join-Path $cache 'ms-playwright'
        NUGET_PACKAGES           = Join-Path $cache 'nuget\packages'
        GOCACHE                  = Join-Path $cache 'go-build'
        GOPATH                   = "$drive\developer\go"
        GOMODCACHE               = "$drive\developer\go\pkg\mod"
        CARGO_HOME               = Join-Path $toolchains 'cargo'
        RUSTUP_HOME              = Join-Path $toolchains 'rustup'
        TEMP                     = "$drive\Temp"
        TMP                      = "$drive\Temp"
    }

    foreach ($name in $variables.Keys) {
        $value = $variables[$name]
        if (-not $Apply) {
            Write-LogDryRun "Would persist $name=$value"
            continue
        }

        New-Item -Path $value -ItemType Directory -Force | Out-Null
        Set-UserEnvironmentVariableIfNeeded -Name $name -Value $value
    }
}

function Remove-ObsoleteRuntimeWrappers {
    param([switch]$Apply)

    $shimRoot = Get-UserShimRoot
    $obsoleteWrapperNames = @(
        'fnm.cmd', 'fnm.ps1', 'fnm',
        'node.cmd', 'node.ps1', 'node',
        'npm.cmd', 'npm.ps1', 'npm',
        'npx.cmd', 'npx.ps1', 'npx',
        'corepack.cmd', 'corepack.ps1', 'corepack'
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
        $normalized -like '*\fnm.exe*'
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

    $defaultAliasRoot = (Get-DevToolchainLayout).FnmDefaultAlias

    if ($Apply) {
        # PATH points at the alias, so it must stay the junction fnm repoints on 'fnm default'.
        if (-not (Test-IsReparsePoint -Path $defaultAliasRoot)) {
            throw "fnm default alias at $defaultAliasRoot is missing or is not a junction."
        }

        [void](Add-PathEntry -Entry $defaultAliasRoot -Scope User)
    }
    else {
        Write-LogDryRun "Would register fnm default alias path in user PATH: $defaultAliasRoot"
    }
}

function Set-NpmGlobalConfig {
    param([switch]$Apply)

    # Version-independent prefix: npm's default prefix is the active Node install directory.
    $layout = Get-DevToolchainLayout
    $npm = Join-Path $layout.FnmDefaultAlias 'npm.cmd'
    $settings = [ordered]@{ prefix = $layout.NpmPrefix }
    if ($layout.CacheRoot) {
        $settings.cache = Join-Path $layout.CacheRoot 'npm'
    }

    foreach ($key in $settings.Keys) {
        if (-not $Apply) {
            Write-LogDryRun "Would run: npm config set $key $($settings[$key]) --location=user"
            continue
        }

        Invoke-ExternalCommand -FilePath $npm -Arguments @('config', 'set', $key, $settings[$key], '--location=user')
    }

    if ($Apply) {
        New-Item -Path $layout.NpmPrefix -ItemType Directory -Force | Out-Null
    }
}

function Set-PnpmGlobalConfig {
    param([switch]$Apply)

    $layout = Get-DevToolchainLayout
    $corepack = Join-Path $layout.FnmDefaultAlias 'corepack.cmd'
    if ($Apply) {
        Write-LogInfo "Enabling pnpm via corepack..."
        Invoke-ExternalCommand -FilePath $corepack -Arguments @('enable', 'pnpm')
    }
    else {
        Write-LogDryRun "Would run: corepack enable pnpm"
    }

    if (-not $layout.PreferredDrive) {
        return
    }

    $configDir = Join-Path $env:LOCALAPPDATA 'pnpm\config'
    $settings = [ordered]@{
        storeDir     = $layout.PnpmStore
        cacheDir     = Join-Path $layout.CacheRoot 'pnpm'
        globalDir    = Join-Path $layout.PnpmHome 'global'
        globalBinDir = $layout.PnpmBin
    }

    if (-not $Apply) {
        Write-LogDryRun "Would persist PNPM_HOME=$($layout.PnpmHome)"
        Write-LogDryRun "Would merge pnpm settings into $configDir (config.yaml, rc): store $($layout.PnpmStore)"
        return
    }

    Set-UserEnvironmentVariableIfNeeded -Name 'PNPM_HOME' -Value $layout.PnpmHome
    New-Item -Path $layout.PnpmBin -ItemType Directory -Force | Out-Null
    # pnpm 11 reads config.yaml; pnpm 10 still reads the ini-style rc file.
    Set-ConfigFileValues -Path (Join-Path $configDir 'config.yaml') -Separator ': ' -Values $settings
    Set-ConfigFileValues -Path (Join-Path $configDir 'rc') -Separator '=' -Values ([ordered]@{ 'store-dir' = $layout.PnpmStore })
}

function Set-NodeRuntimeState {
    param([switch]$Apply)

    $runtimePolicy = (Get-RuntimePolicy).node
    $layout = Get-DevToolchainLayout
    $env:FNM_DIR = $layout.FnmDir
    if ($Apply) {
        Set-UserEnvironmentVariableIfNeeded -Name 'FNM_DIR' -Value $layout.FnmDir
    }
    else {
        Write-LogDryRun "Would persist FNM_DIR=$($layout.FnmDir)"
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

    if ((Test-Path -LiteralPath $layout.FnmDefaultAlias) -and -not (Test-IsReparsePoint -Path $layout.FnmDefaultAlias)) {
        throw "fnm default alias at $($layout.FnmDefaultAlias) is a real directory, not the junction fnm creates. Move anything you need out of it, delete it, and re-run."
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
    Set-NpmGlobalConfig -Apply:$Apply
    Set-PnpmGlobalConfig -Apply:$Apply
}

function Set-PythonRuntimeState {
    param([switch]$Apply)

    $layout = Get-DevToolchainLayout
    $majorMinor = $layout.PythonMajorMinor
    $venvPython = Join-Path $layout.PythonVenv 'Scripts\python.exe'

    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        if ($Apply) {
            Write-LogWarn "uv is not installed yet. Deferring Python runtime configuration until uv is installed."
            return
        }

        Write-LogDryRun "Would configure Python via uv once it is installed."
        return
    }

    if (-not $Apply) {
        Write-LogDryRun "Would run: uv python install $majorMinor --default"
        if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
            Write-LogDryRun "Would create seeded global venv $($layout.PythonVenv)"
        }
        return
    }

    Write-LogInfo "Ensuring Python $majorMinor via uv..."
    Invoke-ExternalCommand -FilePath 'uv' -Arguments @('python', 'install', $majorMinor, '--default')
    if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        Write-LogInfo "Creating global Python venv at $($layout.PythonVenv)..."
        Invoke-ExternalCommand -FilePath 'uv' -Arguments @('venv', '--seed', '--python', $majorMinor, $layout.PythonVenv)
    }
}

function Set-ProfileJunction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [switch]$Apply
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and (Test-IsReparsePoint -Path $Path)) {
        if ((Format-PathEntryText -Entry "$($item.Target)") -ine (Format-PathEntryText -Entry $Target)) {
            Write-LogWarn "$Path is a link to '$($item.Target)', expected '$Target'. Leaving it in place."
        }
        return
    }

    if ($item -and @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-LogWarn "$Path has content. Move it to $Target, delete $Path, and re-run to create the junction."
        return
    }

    if (-not $Apply) {
        Write-LogDryRun "Would create junction $Path -> $Target"
        return
    }

    New-Item -Path $Target -ItemType Directory -Force | Out-Null
    if ($item) {
        Remove-Item -LiteralPath $Path -Force
    }
    New-Item -Path (Split-Path -Parent $Path) -ItemType Directory -Force | Out-Null
    New-Item -Path $Path -ItemType Junction -Target $Target | Out-Null
    Write-LogInfo "Created junction $Path -> $Target"
}

function Set-ProfileJunctions {
    param([switch]$Apply)

    # Directory junctions for tools without a relocation setting. T3 Code resolves realpath, so its
    # worktree and scratch roots can live on the preferred drive.
    $layout = Get-DevToolchainLayout
    if (-not $layout.PreferredDrive) {
        return
    }

    $developerRoot = "$($layout.PreferredDrive)\developer"
    Set-ProfileJunction -Path (Join-Path $env:USERPROFILE '.cache') -Target (Join-Path $layout.CacheRoot 'home') -Apply:$Apply
    Set-ProfileJunction -Path (Join-Path $env:USERPROFILE '.t3\worktrees') -Target (Join-Path $developerRoot '.t3\worktrees') -Apply:$Apply
    Set-ProfileJunction -Path (Join-Path $env:USERPROFILE '.t3\scratch') -Target (Join-Path $developerRoot '.t3\scratch') -Apply:$Apply
}

function Invoke-RuntimeToolingSetup {
    [CmdletBinding()]
    param([switch]$Execute)

    Write-LogInfo "Applying runtime policy..."
    Set-DevDirectoryEnvironment -Apply:$Execute
    Set-NodeRuntimeState -Apply:$Execute
    Set-PythonRuntimeState -Apply:$Execute
    Set-ProfileJunctions -Apply:$Execute

    if ($Execute) {
        Update-StandardPaths -IsAdmin (Test-IsAdmin) | Out-Null
        Write-LogOK "Runtime tooling is configured."
    }
}

Export-ModuleMember -Function Invoke-RuntimeToolingSetup
