# ManifestHelpers.psm1

function New-SymbolicLink {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DestPath,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )
    try {
        if (Test-Path $DestPath) {
            Write-Warning "$DestPath is already symlinked"
        }
        else {
            if ((Get-Item $SourcePath) -is [System.IO.DirectoryInfo]) {
                New-Item -ItemType SymbolicLink -Path $DestPath -Target $SourcePath | Out-Null
            }
            else {
                New-Item -ItemType SymbolicLink -Path $DestPath -Target $SourcePath | Out-Null
            }
            Write-Output "$DestPath has been symlinked"
        }
    }
    catch {
        Write-Error "Failed to create symlink for $DestPath. Error: $_"
    }
}

function Remove-SymbolicLink {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DestPath,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )
    try {
        if (Test-Path $DestPath) {
            Remove-Item -Path $DestPath -Force
            Write-Output "$DestPath has been unsymlinked"
        }
        else {
            Write-Warning "$DestPath doesn't exist"
        }
    }
    catch {
        Write-Error "Failed to remove symlink for $DestPath. Error: $_"
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
        if (Test-Path $DestPath) {
            Write-Warning "$DestPath already exists. Skipping copy."
        }
        else {
            if ((Get-Item $SourcePath) -is [System.IO.DirectoryInfo]) {
                Copy-Item -Path $SourcePath -Destination $DestPath -Recurse -Force
            }
            else {
                Copy-Item -Path $SourcePath -Destination $DestPath -Force
            }
            Write-Output "$DestPath has been copied"
        }
    }
    catch {
        Write-Error "Failed to copy $SourcePath to $DestPath. Error: $_"
    }
}

function Remove-Copy {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DestPath
    )
    try {
        if (Test-Path $DestPath) {
            Remove-Item -Path $DestPath -Recurse -Force
            Write-Output "$DestPath has been removed"
        }
        else {
            Write-Warning "$DestPath doesn't exist"
        }
    }
    catch {
        Write-Error "Failed to remove $DestPath. Error: $_"
    }
}

function Deploy-Manifest {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ManifestFile
    )
    Write-Output "Deploying $ManifestFile..."
    try {
        $Manifest = Import-Csv -Header ("file", "operation") -Delimiter ("|") -Path ".\$ManifestFile"
        $homeDir = $env:HOME
        foreach ($ManifestRow in $Manifest) {
            $DeployFile = $ManifestRow.file
            $DeployOp = $ManifestRow.operation
            $SourcePath = Join-Path $PSScriptRoot $DeployFile
            $DestPath = Join-Path $homeDir $DeployFile
            switch ($DeployOp) {
                "symlink" {
                    New-SymbolicLink -DestPath $DestPath -SourcePath $SourcePath
                }
                "copy" {
                    Copy-File -DestPath $DestPath -SourcePath $SourcePath
                }
                default {
                    Write-Warning "Unknown operation $DeployOp. Skipping..."
                }
            }
        }
    }
    catch {
        Write-Error "Failed to deploy manifest $ManifestFile. Error: $_"
    }
}

function Uninstall-Manifest {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ManifestFile
    )
    Write-Output "Undeploying $ManifestFile..."
    try {
        $Manifest = Import-Csv -Header ("file", "operation") -Delimiter ("|") -Path ".\$ManifestFile"
        $EmacsHome = $env:HOME
        foreach ($ManifestRow in $Manifest) {
            $DeployFile = $ManifestRow.file
            $DeployOp = $ManifestRow.operation
            $SourcePath = Join-Path $PSScriptRoot $DeployFile
            $DestPath = Join-Path $EmacsHome $DeployFile
            switch ($DeployOp) {
                "symlink" {
                    Remove-SymbolicLink -DestPath $DestPath -SourcePath $SourcePath
                }
                "copy" {
                    Remove-Copy -DestPath $DestPath
                }
                default {
                    Write-Warning "Unknown operation $DeployOp. Skipping..."
                }
            }
        }
    }
    catch {
        Write-Error "Failed to undeploy manifest $ManifestFile. Error: $_"
    }
}