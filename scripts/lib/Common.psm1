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

function Test-CommandAvailable {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-CommandProbeArgs {
    param([string]$Name)

    $defaultArgs = @("--version")

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $defaultArgs
    }

    $overrides = @{
        "winfetch" = @("--help")
        "wt"       = @("--version")
    }

    if ($overrides.ContainsKey($Name)) {
        return $overrides[$Name]
    }

    return $defaultArgs
}

function Test-CommandAccessible {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return $false
    }

    $args = Get-CommandProbeArgs -Name $Name
    try {
        $filePath = if ($cmd.Path) { $cmd.Path } else { $Name }
        $proc = Start-Process -FilePath $filePath -ArgumentList $args -NoNewWindow -Wait -PassThru -ErrorAction Stop
        return ($proc.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

function Ensure-PathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Entry,
        [ValidateSet('User', 'Machine')]
        [string]$Scope = 'User'
    )

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return $false
    }

    $current = [System.Environment]::GetEnvironmentVariable("Path", $Scope)
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        $parts = $current.Split(';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    if ($parts -contains $Entry) {
        return $false
    }

    $newPath = if ($parts.Count -gt 0) { ($parts + $Entry) -join ';' } else { $Entry }
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, $Scope)
    return $true
}

function Ensure-StandardPaths {
    param(
        [bool]$IsAdmin = $false
    )

    $updated = $false

    # Always ensure WindowsApps for current user.
    $windowsApps = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
    if (Ensure-PathEntry -Entry $windowsApps -Scope User) {
        $updated = $true
    }

    # Ensure Scoop shims if Scoop is present.
    $scoopShims = Join-Path $env:USERPROFILE "scoop\shims"
    if (Test-Path $scoopShims) {
        if (Ensure-PathEntry -Entry $scoopShims -Scope User) {
            $updated = $true
        }
    }

    # Ensure Chocolatey bin for machine scope if running admin and choco is installed.
    if ($IsAdmin -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        $chocoBin = Join-Path $env:ProgramData "chocolatey\bin"
        if (Test-Path $chocoBin) {
            if (Ensure-PathEntry -Entry $chocoBin -Scope Machine) {
                $updated = $true
            }
        }
    }

    if ($updated) {
        Update-Path
    }

    return $updated
}

function Start-SetupTranscript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        return
    }

    try {
        if ($global:TranscriptRunning) {
            return
        }
        Start-Transcript -Path $LogPath -Append -ErrorAction Stop | Out-Null
        $global:TranscriptRunning = $true
    }
    catch {
        # Ignore transcript start failures (e.g., already running or no permission)
    }
}

function Stop-SetupTranscript {
    try {
        if ($global:TranscriptRunning) {
            Stop-Transcript | Out-Null
            $global:TranscriptRunning = $false
        }
    }
    catch {
        # Ignore stop failures (e.g., no transcript running)
    }
}

Export-ModuleMember -Function Test-InternetConnection, Test-IsAdmin, Test-SymlinkCapability, Update-Path, `
    Test-CommandAvailable, Get-CommandProbeArgs, Test-CommandAccessible, Ensure-PathEntry, Ensure-StandardPaths, `
    Start-SetupTranscript, Stop-SetupTranscript, `
    Write-Log, Write-LogOK, Write-LogInfo, Write-LogWarn, Write-LogError, Write-LogSkip, Write-LogBackup, Write-LogDryRun
