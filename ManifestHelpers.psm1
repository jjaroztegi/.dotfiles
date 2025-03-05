# ManifestHelpers.psm1

# Helper function to determine the destination path
function Get-DestinationPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [string]$Destination
    )
    if ($Destination) {
        return $Destination -replace "^~", $env:HOME
    } else {
        $baseName = Split-Path -Leaf $Source
        return Join-Path $env:HOME $baseName
    }
}

function New-SymbolicLink {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DestPath,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )
    try {
        $parentDir = Split-Path $DestPath -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        if (Test-Path $DestPath) {
            Write-Warning "$DestPath already exists. Skipping."
        } else {
            New-Item -ItemType SymbolicLink -Path $DestPath -Target $SourcePath | Out-Null
            Write-Output "$DestPath has been symlinked"
        }
    } catch {
        Write-Error "Failed to create symlink for $DestPath. Error: $_"
    }
}

function Copy-File {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DestPath,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )
    try {
        $parentDir = Split-Path $DestPath -Parent
        if ($parentDir -and -not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        if (Test-Path $DestPath) {
            Write-Warning "$DestPath already exists. Skipping."
        } else {
            if ((Get-Item $SourcePath) -is [System.IO.DirectoryInfo]) {
                Copy-Item -Path $SourcePath -Destination $DestPath -Recurse -Force
            } else {
                Copy-Item -Path $SourcePath -Destination $DestPath -Force
            }
            Write-Output "$DestPath has been copied"
        }
    } catch {
        Write-Error "Failed to copy $SourcePath to $DestPath. Error: $_"
    }
}

function Deploy-Manifest {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ManifestFile
    )
    Write-Output "Deploying $ManifestFile..."
    try {
        $Manifest = Import-Csv -Header ("source", "operation", "destination") -Delimiter "|" -Path ".\$ManifestFile"
        foreach ($ManifestRow in $Manifest) {
            $SourcePath = Join-Path $PSScriptRoot $ManifestRow.source
            $DestPath = Get-DestinationPath -Source $ManifestRow.source -Destination $ManifestRow.destination
            switch ($ManifestRow.operation) {
                "symlink" {
                    New-SymbolicLink -DestPath $DestPath -SourcePath $SourcePath
                }
                "copy" {
                    Copy-File -DestPath $DestPath -SourcePath $SourcePath
                }
                default {
                    Write-Warning "Unknown operation $($ManifestRow.operation). Skipping..."
                }
            }
        }
    } catch {
        Write-Error "Failed to deploy manifest $ManifestFile. Error: $_"
    }
}
