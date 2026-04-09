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
    $probeUris = @(
        'https://www.microsoft.com',
        'https://github.com'
    )

    foreach ($probeUri in $probeUris) {
        try {
            Invoke-WebRequest -Uri $probeUri -Method Head -UseBasicParsing -TimeoutSec 15 | Out-Null
            return $true
        }
        catch {
            continue
        }
    }

    Write-LogWarn "Internet connection is required but not available."
    return $false
}

function Test-InteractiveSession {
    if ($env:DOTFILES_NONINTERACTIVE -eq '1') {
        return $false
    }

    if (-not [Environment]::UserInteractive) {
        return $false
    }

    return $Host.Name -eq 'ConsoleHost'
}

function Wait-BootstrapExit {
    param([string]$Prompt = "Press any key to exit...")

    if (-not (Test-InteractiveSession)) {
        return
    }

    Write-Host "`n$Prompt" -ForegroundColor Gray
    try {
        $null = [Console]::ReadKey($true)
    }
    catch {
        # Some hosts do not expose a readable console even when UserInteractive is true.
    }
}

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
}

function Test-SymlinkCapability {
    $testLink = Join-Path $env:TEMP "symlink_test_$([guid]::NewGuid())"
    $testTarget = $env:TEMP
    try {
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
    $userPath = if (-not [string]::IsNullOrWhiteSpace($env:DOTFILES_SESSION_USER_PATH)) {
        $env:DOTFILES_SESSION_USER_PATH
    }
    else {
        [System.Environment]::GetEnvironmentVariable("Path", "User")
    }
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
        "go"       = @("version")
        "ffmpeg"   = @("-version")
        "pyenv"    = @("--version")
        "7z"       = @("i")
        "gswin64c" = @("-version")
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

    $resolutionOnlyCommands = @('wt', 'QuickLook')
    if ($resolutionOnlyCommands -contains $Name) {
        return $true
    }

    $probeArgs = Get-CommandProbeArgs -Name $Name
    try {
        $stdoutLog = "$env:TEMP\\codex-$Name-out.log"
        $stderrLog = "$env:TEMP\\codex-$Name-err.log"
        $filePath = if ($cmd.Path) { $cmd.Path } else { $Name }
        $startInfo = @{
            NoNewWindow = $true
            Wait = $true
            PassThru = $true
            RedirectStandardOutput = $stdoutLog
            RedirectStandardError = $stderrLog
            ErrorAction = 'Stop'
        }

        if ($cmd.CommandType -eq [System.Management.Automation.CommandTypes]::ExternalScript -or $filePath -like '*.ps1') {
            $hostCommand = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
            $scriptArgs = [System.Collections.Generic.List[string]]::new()
            [void]$scriptArgs.Add('-NoLogo')
            [void]$scriptArgs.Add('-NoProfile')
            [void]$scriptArgs.Add('-File')
            [void]$scriptArgs.Add($filePath)
            foreach ($arg in $probeArgs) {
                [void]$scriptArgs.Add($arg)
            }

            $startInfo.FilePath = $hostCommand
            $startInfo.ArgumentList = @($scriptArgs)
        }
        else {
            $startInfo.FilePath = $filePath
            $startInfo.ArgumentList = @($probeArgs)
        }

        $proc = Start-Process @startInfo
        return ($proc.ExitCode -eq 0)
    }
    catch {
        return $false
    }
    finally {
        Remove-Item "$env:TEMP\\codex-$Name-out.log" -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\\codex-$Name-err.log" -ErrorAction SilentlyContinue
    }
}

function Get-DotfilesRoot {
    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

function Get-DotfilesConfigPath {
    param([Parameter(Mandatory = $true)][string]$Name)

    return (Join-Path (Join-Path (Get-DotfilesRoot) "config") $Name)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    return (Get-Content $Path -Raw | ConvertFrom-Json)
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
    }
}

Export-ModuleMember -Function Test-InternetConnection, Test-IsAdmin, Test-SymlinkCapability, Update-Path, `
    Test-InteractiveSession, Wait-BootstrapExit, Test-CommandAvailable, Get-CommandProbeArgs, Test-CommandAccessible, Get-DotfilesRoot, Get-DotfilesConfigPath, Read-JsonFile, `
    Start-SetupTranscript, Stop-SetupTranscript, `
    Write-Log, Write-LogOK, Write-LogInfo, Write-LogWarn, Write-LogError, Write-LogSkip, Write-LogBackup, Write-LogDryRun
