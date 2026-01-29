function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('OK', 'INFO', 'WARN', 'ERROR', 'SKIP', 'BACKUP', 'DRY-RUN')]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $colors = @{
        'OK'      = 'Green'
        'INFO'    = 'Cyan'
        'WARN'    = 'Yellow'
        'ERROR'   = 'Red'
        'SKIP'    = 'DarkGray'
        'BACKUP'  = 'Yellow'
        'DRY-RUN' = 'Magenta'
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = "[$Level]".PadRight(10)

    Write-Host "$timestamp $prefix $Message" -ForegroundColor $colors[$Level]
}

function Write-LogOK { param($Msg) Write-Log -Level 'OK' -Message $Msg }
function Write-LogInfo { param($Msg) Write-Log -Level 'INFO' -Message $Msg }
function Write-LogWarn { param($Msg) Write-Log -Level 'WARN' -Message $Msg }
function Write-LogError { param($Msg) Write-Log -Level 'ERROR' -Message $Msg }
function Write-LogSkip { param($Msg) Write-Log -Level 'SKIP' -Message $Msg }
function Write-LogBackup { param($Msg) Write-Log -Level 'BACKUP' -Message $Msg }
function Write-LogDryRun { param($Msg) Write-Log -Level 'DRY-RUN' -Message $Msg }

function Test-InternetConnection {
    try {
        Test-Connection -ComputerName "www.google.com" -Count 1 -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-LogWarn "Internet connection is required but not available."
        return $false
    }
}

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
}

function Test-SymlinkCapability {
    $testLink = Join-Path $env:TEMP "symlink_test_$([guid]::NewGuid())"
    $testTarget = $env:TEMP
    try {
        # Requires Administrator privileges or Developer Mode.
        New-Item -ItemType SymbolicLink -Path $testLink -Target $testTarget -ErrorAction Stop | Out-Null
        Remove-Item $testLink -Force
        return $true
    }
    catch {
        return $false
    }
}

function Update-Path {
    Write-LogInfo "Refreshing environment PATH..."
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

Export-ModuleMember -Function Test-InternetConnection, Test-IsAdmin, Test-SymlinkCapability, Update-Path, `
    Write-Log, Write-LogOK, Write-LogInfo, Write-LogWarn, Write-LogError, Write-LogSkip, Write-LogBackup, Write-LogDryRun
