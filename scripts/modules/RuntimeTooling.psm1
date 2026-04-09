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

function Set-CommandWrapperContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $existing = if (Test-Path $Path -PathType Leaf) { Get-Content $Path -Raw } else { $null }
    if ($existing -ceq $Content) {
        return $false
    }

    Set-Content -Path $Path -Value $Content -Encoding ASCII
    return $true
}

function Set-PosixCommandWrapperContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $normalizedContent = ($Content -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    $existing = if (Test-Path $Path -PathType Leaf) {
        [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::ASCII)
    }
    else {
        $null
    }

    if ($existing -ceq $normalizedContent) {
        return $false
    }

    [System.IO.File]::WriteAllText($Path, $normalizedContent, [System.Text.Encoding]::ASCII)
    return $true
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
                Invoke-GitExternalCommand -Arguments @('-C', $cloneRoot, 'pull', '--ff-only')
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

                Write-LogInfo "Installing pyenv-win from the official git repository..."
                Invoke-GitExternalCommand -Arguments @('clone', 'https://github.com/pyenv-win/pyenv-win.git', $cloneRoot)
            }
        }
    }
    elseif ($Apply -and (Test-Path -LiteralPath (Join-Path $cloneRoot '.git') -PathType Container)) {
        Write-LogInfo "Refreshing pyenv-win checkout in $cloneRoot..."
        Invoke-GitExternalCommand -Arguments @('-C', $cloneRoot, 'pull', '--ff-only')
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

function Get-ResolvedExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [ValidateSet('Leaf', 'Container')]
        [string]$PathType = 'Leaf'
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($PathType -eq 'Leaf') -and $item.PSIsContainer) {
        throw "Expected a file path but found a directory: $Path"
    }

    if (($PathType -eq 'Container') -and -not $item.PSIsContainer) {
        throw "Expected a directory path but found a file: $Path"
    }

    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $item.Target) {
        foreach ($target in @($item.Target)) {
            if ([string]::IsNullOrWhiteSpace($target)) {
                continue
            }

            $candidate = if ([System.IO.Path]::IsPathRooted($target)) {
                $target
            }
            else {
                Join-Path (Split-Path -Parent $item.FullName) $target
            }

            if (Test-Path -LiteralPath $candidate -PathType $PathType) {
                return $candidate
            }
        }
    }

    if ($item.PSObject.Properties.Name -contains 'ResolvedTarget' -and $item.ResolvedTarget) {
        if ($item.ResolvedTarget -is [System.Array]) {
            foreach ($target in $item.ResolvedTarget) {
                if ($target -and (Test-Path -LiteralPath $target -PathType $PathType)) {
                    return $target
                }
            }
        }
        elseif (Test-Path -LiteralPath $item.ResolvedTarget -PathType $PathType) {
            return $item.ResolvedTarget
        }
    }

    if (Test-Path -LiteralPath $item.FullName -PathType $PathType) {
        return $item.FullName
    }

    throw "Unable to resolve a valid $PathType path for $Path"
}

function Get-FnmManagedCommandLeaf {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('node', 'npm', 'npx', 'corepack')]
        [string]$CommandName
    )

    switch ($CommandName) {
        'node' { return 'node.exe' }
        'npm' { return 'npm.cmd' }
        'npx' { return 'npx.cmd' }
        'corepack' { return 'corepack.cmd' }
    }
}

function Get-FnmDefaultInstallationPath {
    $aliasRoot = Get-FnmDefaultAliasRoot
    if (-not (Test-Path -LiteralPath $aliasRoot -PathType Container)) {
        throw "fnm default alias is missing at $aliasRoot"
    }

    return (Get-ResolvedExecutablePath -Path $aliasRoot -PathType Container)
}

function Get-FnmManagedCommandPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallationPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('node', 'npm', 'npx', 'corepack')]
        [string]$CommandName
    )

    $targetPath = Join-Path $InstallationPath (Get-FnmManagedCommandLeaf -CommandName $CommandName)
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw "Unable to resolve fnm-managed $CommandName target at $targetPath"
    }

    return $targetPath
}

function Update-FnmExecutableWrapper {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FnmPath,
        [switch]$Apply
    )

    $shimRoot = Get-UserShimRoot
    if (-not (Test-Path $shimRoot -PathType Container)) {
        New-Item -Path $shimRoot -ItemType Directory -Force | Out-Null
    }

    $resolvedFnmPath = Get-ResolvedExecutablePath -Path $FnmPath
    $quotedFnmPath = '"' + $resolvedFnmPath + '"'
    $cmdWrapperPath = Join-Path $shimRoot 'fnm.cmd'
    $cmdWrapper = @"
@echo off
setlocal
$quotedFnmPath %*
set "exitCode=%ERRORLEVEL%"
endlocal & exit /b %exitCode%
"@

    $ps1WrapperPath = Join-Path $shimRoot 'fnm.ps1'
    $ps1Wrapper = @"
& $quotedFnmPath @args
exit `$LASTEXITCODE
"@

    $posixWrapperPath = Join-Path $shimRoot 'fnm'
    $posixWrapper = @"
#!/usr/bin/env sh
exec $quotedFnmPath "`$@"
"@

    if ($Apply) {
        $cmdUpdated = Set-CommandWrapperContent -Path $cmdWrapperPath -Content $cmdWrapper
        $ps1Updated = Set-CommandWrapperContent -Path $ps1WrapperPath -Content $ps1Wrapper
        $posixUpdated = Set-PosixCommandWrapperContent -Path $posixWrapperPath -Content $posixWrapper
        if ($cmdUpdated -or $ps1Updated -or $posixUpdated) {
            Write-LogInfo "Updated fnm wrapper in $shimRoot"
        }
        else {
            Write-LogSkip "fnm wrapper is already current."
        }
    }
    else {
        Write-LogDryRun "Would register fnm wrappers in $shimRoot"
    }
}

function Update-FnmCommandWrappers {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Commands,
        [Parameter(Mandatory = $true)]
        [string]$InstallationPath,
        [switch]$Apply
    )

    $shimRoot = Get-UserShimRoot
    if (-not (Test-Path $shimRoot -PathType Container)) {
        New-Item -Path $shimRoot -ItemType Directory -Force | Out-Null
    }

    foreach ($command in $Commands) {
        $targetPath = Get-FnmManagedCommandPath -InstallationPath $InstallationPath -CommandName $command
        $quotedTargetPath = '"' + $targetPath + '"'
        $cmdWrapperPath = Join-Path $shimRoot ("{0}.cmd" -f $command)
        $cmdWrapper = @"
@echo off
setlocal
$quotedTargetPath %*
set "exitCode=%ERRORLEVEL%"
endlocal & exit /b %exitCode%
"@

        $posixWrapperPath = Join-Path $shimRoot $command
        $posixWrapper = @"
#!/usr/bin/env sh
exec $quotedTargetPath "`$@"
"@

        if ($Apply) {
            $cmdUpdated = Set-CommandWrapperContent -Path $cmdWrapperPath -Content $cmdWrapper
            $posixUpdated = Set-PosixCommandWrapperContent -Path $posixWrapperPath -Content $posixWrapper
            $ps1WrapperPath = Join-Path $shimRoot ("{0}.ps1" -f $command)
            $removedPs1Wrapper = $false
            if (Test-Path $ps1WrapperPath -PathType Leaf) {
                Remove-Item -LiteralPath $ps1WrapperPath -Force
                $removedPs1Wrapper = $true
            }

            if ($cmdUpdated -or $posixUpdated -or $removedPs1Wrapper) {
                Write-LogInfo "Updated fnm wrapper for $command in $shimRoot"
            }
            else {
                Write-LogSkip "fnm wrapper for $command is already current."
            }
        }
        else {
            Write-LogDryRun "Would register fnm wrappers for $command in $shimRoot"
        }
    }
}

function Set-NodeRuntimeState {
    param([switch]$Apply)

    $runtimePolicy = (Get-RuntimePolicy).node
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

    $defaultInstallationPath = Get-FnmDefaultInstallationPath
    Update-FnmExecutableWrapper -FnmPath $fnmPath -Apply:$Apply
    Update-FnmCommandWrappers -Commands @($runtimePolicy.commands) -InstallationPath $defaultInstallationPath -Apply:$Apply
}

function Set-PythonRuntimeState {
    param([switch]$Apply)

    $runtimePolicy = (Get-RuntimePolicy).python
    if (-not (Get-Command pyenv -ErrorAction SilentlyContinue)) {
        if ($Apply -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-LogWarn "Git is not installed yet. Deferring Python runtime configuration until after the admin phase installs managed packages."
            return
        }

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
    $selectedVersion = Get-HighestVersionMatch -Candidates $installedVersions -MajorMinor $runtimePolicy.majorMinor

    if (-not $selectedVersion) {
        $availableVersions = Get-TrimmedLines -InputObject (& $pyenvPath install --list 2>$null)
        $selectedVersion = Get-HighestVersionMatch -Candidates $availableVersions -MajorMinor $runtimePolicy.majorMinor
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
