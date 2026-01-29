function Get-AppInstallPath {
    param([string]$AppName)

    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($regPath in $regPaths) {
        $app = Get-ItemProperty $regPath -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*$AppName*" }
        if ($app.InstallLocation) {
            return $app.InstallLocation
        }
    }

    # Hardcoded fallback paths
    $knownPaths = @{
        "MSI Afterburner"             = "${env:ProgramFiles(x86)}\MSI Afterburner"
        "RivaTuner Statistics Server" = "${env:ProgramFiles(x86)}\RivaTuner Statistics Server"
    }

    if ($knownPaths.ContainsKey($AppName)) {
        return $knownPaths[$AppName]
    }

    throw "Application '$AppName' not found in registry"
}

function Resolve-DynamicPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    if ($Path.StartsWith('~')) {
        $Path = Join-Path $env:HOME $Path.Substring(1).TrimStart('\').TrimStart('/')
    }

    $Path = [System.Environment]::ExpandEnvironmentVariables($Path)

    $Path = $Path -replace '\$ProgramFiles\(x86\)', ${env:ProgramFiles(x86)}
    $Path = $Path -replace '\$ProgramFiles', $env:ProgramFiles
    $Path = $Path -replace '\$LocalAppData', $env:LOCALAPPDATA
    $Path = $Path -replace '\$AppData', $env:APPDATA

    # Resolve standard PowerShell profile directory.
    $profileDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'
    $Path = $Path -replace '\$ProfileDir', $profileDir

    # Resolve shell-specific special folders.
    if ($Path -eq 'shell:startup') {
        return [Environment]::GetFolderPath('Startup')
    }

    # Resolve application installation paths via registry lookup.
    if ($Path -match '\$AppPath\[(.+?)\]') {
        $appName = $Matches[1]
        try {
            $installPath = Get-AppInstallPath $appName
            # Ensure no trailing slash to avoid double slashes
            $installPath = $installPath.TrimEnd('\')
            $installPath = $installPath.TrimEnd('\')
            $token = "`$AppPath[$appName]"
            $Path = $Path.Replace($token, $installPath)
        }
        catch {
            Write-LogWarn "Could not resolve path for '$appName': $_"
        }
    }

    return $Path
}

function Get-DestinationPath {
    param(
        [string]$Source,
        [string]$Destination
    )

    if ([string]::IsNullOrWhiteSpace($Destination)) {
        if ([string]::IsNullOrWhiteSpace($Source)) {
            throw "Get-DestinationPath: Source cannot be null when Destination is empty."
        }
        # Default destination: HOME/filename
        return Join-Path $env:HOME (Split-Path $Source -Leaf)
    }

    $resolved = Resolve-DynamicPath -Path $Destination

    # If the destination is an existing directory, append the filename
    if (Test-Path $resolved -PathType Container) {
        return Join-Path $resolved (Split-Path $Source -Leaf)
    }

    return $resolved
}

function Test-ManifestEntry {
    param(
        [string]$Source,
        [string]$Operation,
        [string]$Destination
    )

    $errors = @()

    if ($Operation -notin @('symlink', 'copy')) {
        $errors += "Invalid operation: $Operation"
    }

    if (-not (Test-Path $Source)) {
        $errors += "Source not found: $Source"
    }

    return $errors
}

function Deploy-Manifest {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestFile
    )

    if (-not (Test-SymlinkCapability)) {
        Write-LogWarn "System cannot create symbolic links. Enable Developer Mode or run as Administrator."
        Write-LogWarn "Falling back to 'copy' for all symlink operations."
        $script:forceCopy = $true
    }

    $manifestDir = Split-Path $ManifestFile -Parent
    $repoRoot = (Get-Item $manifestDir).Parent.FullName

    Get-Content $ManifestFile | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            return
        }

        $parts = $line -split '\|'
        if ($parts.Count -lt 2) {
            Write-LogWarn "Skipping invalid line in manifest: $line"
            return
        }

        $sourceRel = $parts[0].Trim('"')
        $operation = $parts[1].Trim()
        $destRaw = if ($parts.Count -gt 2) { $parts[2].Trim('"') } else { "" }

        $sourcePath = Join-Path $repoRoot $sourceRel

        if ([string]::IsNullOrWhiteSpace($sourcePath)) {
            Write-LogWarn "Skipping invalid source path for line: $line"
            continue
        }

        $destPath = Get-DestinationPath -Source $sourcePath -Destination $destRaw

        $validationErrors = Test-ManifestEntry -Source $sourcePath -Operation $operation -Destination $destRaw
        if ($validationErrors) {
            Write-LogError "Validation failed for '$sourceRel': $($validationErrors -join '; ')"
            return
        }

        if ($operation -eq 'symlink' -and $script:forceCopy) {
            $operation = 'copy'
        }

        if ($operation -eq 'copy') {
            if (Test-Path $destPath) {
                if ((Test-Path $destPath -PathType Leaf) -and (Test-Path $sourcePath -PathType Leaf)) {
                    $sourceHash = (Get-FileHash $sourcePath -Algorithm MD5).Hash
                    $destHash = (Get-FileHash $destPath -Algorithm MD5).Hash
                    if ($sourceHash -eq $destHash) {
                        Write-LogSkip "Already up to date: $destPath"
                        return
                    }
                }

                if ($PSCmdlet.ShouldProcess($destPath, "Backup and Copy")) {
                    $backup = "$destPath.bak"
                    Write-LogBackup "Creating backup: $backup"
                    if (Test-Path $backup) {
                        Remove-Item -Path $backup -Recurse -Force
                    }
                    Move-Item -Path $destPath -Destination $backup -Force
                    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                    Write-LogOK "Copied: $destPath"
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess($destPath, "Copy")) {
                    $destDir = Split-Path $destPath -Parent
                    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                    Write-LogOK "Copied: $destPath"
                }
            }
        }
        elseif ($operation -eq 'symlink') {
            if (Test-Path $destPath) {
                if ((Get-Item $destPath).LinkType -eq 'SymbolicLink') {
                    $currentTarget = (Get-Item $destPath).Target
                    if ($currentTarget -match [regex]::Escape($sourcePath)) {
                        Write-LogSkip "Symlink already correct: $destPath"
                        return
                    }
                }

                if ($PSCmdlet.ShouldProcess($destPath, "Backup and Symlink")) {
                    $backup = "$destPath.bak"
                    Write-LogBackup "Moving existing item to $backup"
                    Move-Item -Path $destPath -Destination $backup -Force
                    New-Item -ItemType SymbolicLink -Path $destPath -Target $sourcePath -Force | Out-Null
                    Write-LogOK "Symlinked: $destPath -> $sourceRel"
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess($destPath, "Symlink")) {
                    $destDir = Split-Path $destPath -Parent
                    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                    New-Item -ItemType SymbolicLink -Path $destPath -Target $sourcePath -Force | Out-Null
                    Write-LogOK "Symlinked: $destPath -> $sourceRel"
                }
            }
        }
    }
}

Export-ModuleMember -Function Resolve-DynamicPath, Get-AppInstallPath, Test-ManifestEntry, Deploy-Manifest
