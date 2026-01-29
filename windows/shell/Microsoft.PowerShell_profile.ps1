### PowerShell Profile based on https://github.com/ChrisTitusTech/powershell-profile

# Opt-out of telemetry before doing anything, only if PowerShell is run as admin
if ([bool]([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem) {
    [System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'true', [System.EnvironmentVariableTarget]::Machine)
}

# Import Modules and External Profiles
if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module -Name Terminal-Icons

$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
    Import-Module "$ChocolateyProfile"
}

$PSFzfModule = "PSFzf"
if (Get-Module -ListAvailable -Name $PSFzfModule) {
    Import-Module -Name PSFzf
}

function Update-Profile {
    try {
        $url = "https://raw.githubusercontent.com/jjaroztegi/.dotfiles/main/windows/shell/Microsoft.PowerShell_profile.ps1"
        $oldhash = Get-FileHash $PROFILE
        Invoke-RestMethod $url -OutFile "$env:temp/Microsoft.PowerShell_profile.ps1"
        $newhash = Get-FileHash "$env:temp/Microsoft.PowerShell_profile.ps1"
        if ($newhash.Hash -ne $oldhash.Hash) {
            Copy-Item -Path "$env:temp/Microsoft.PowerShell_profile.ps1" -Destination $PROFILE -Force
            Write-Host "Profile has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
        }
        else {
            Write-Host "Profile is up to date." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Unable to check for `$profile updates: $_"
    }
    finally {
        Remove-Item "$env:temp/Microsoft.PowerShell_profile.ps1" -ErrorAction SilentlyContinue
    }
}

function Update-PowerShell {
    try {
        Write-Host "Checking for PowerShell updates..." -ForegroundColor Cyan
        $updateNeeded = $false
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $gitHubApiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $latestReleaseInfo = Invoke-RestMethod -Uri $gitHubApiUrl
        $latestVersion = $latestReleaseInfo.tag_name.Trim('v')
        if ($currentVersion -lt $latestVersion) {
            $updateNeeded = $true
        }

        if ($updateNeeded) {
            Write-Host "Updating PowerShell..." -ForegroundColor Yellow
            Start-Process powershell.exe -ArgumentList "-NoProfile -Command winget upgrade Microsoft.PowerShell --accept-source-agreements --accept-package-agreements" -Wait -NoNewWindow
            Write-Host "PowerShell has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
        }
        else {
            Write-Host "Your PowerShell is up to date." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to update PowerShell. Error: $_"
    }
}

function Clear-Cache {
    Write-Host "Clearing cache..." -ForegroundColor Cyan
    # Clear Windows Prefetch
    Write-Host "Clearing Windows Prefetch..." -ForegroundColor Yellow
    Remove-Item -Path "$env:SystemRoot\Prefetch\*" -Force -ErrorAction SilentlyContinue
    # Clear Windows Temp
    Write-Host "Clearing Windows Temp..." -ForegroundColor Yellow
    Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    # Clear User Temp
    Write-Host "Clearing User Temp..." -ForegroundColor Yellow
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    # Clear Internet Explorer Cache
    Write-Host "Clearing Internet Explorer Cache..." -ForegroundColor Yellow
    Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cache clearing completed." -ForegroundColor Green
}

# Admin Check and Prompt Customization
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function prompt {
    if ($isAdmin) { "[" + (Get-Location) + "] # " } else { "[" + (Get-Location) + "] $ " }
}
$adminSuffix = if ($isAdmin) { " [ADMIN]" } else { "" }
$Host.UI.RawUI.WindowTitle = "PowerShell {0}$adminSuffix" -f $PSVersionTable.PSVersion.ToString()

# Utility Functions
function Test-CommandExists {
    param($command)
    return $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
}

# POSIX-like timing wrapper
function time {
    param($Command, [string[]]$CommandArgs)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Command @CommandArgs
    $sw.Stop()
    Write-Host "`nElapsed: $($sw.Elapsed.TotalSeconds) seconds"
}

# Editor Configuration
$EDITOR = if (Test-CommandExists code) { 'code' }
elseif (Test-CommandExists nvim) { 'nvim' }
elseif (Test-CommandExists vim) { 'vim' }
elseif (Test-CommandExists notepad++) { 'notepad++' }
else { 'notepad' }
Set-Alias -Name vim -Value $EDITOR

# Quick Access to Editing the Profile
function Edit-Profile {
    vim $PROFILE.CurrentUserAllHosts
}
Set-Alias -Name ep -Value Edit-Profile

function touch($file) { "" | Out-File $file -Encoding ASCII }
function ff($name) {
    Get-ChildItem -recurse -filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output "$($_.FullName)"
    }
}

# Network Utilities
function Get-PubIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }
function pubip { Get-PubIP }

# Open WinUtil
function winutil {
    Invoke-Expression (Invoke-RestMethod https://christitus.com/win)
}

# System Utilities
function uptime {
    try {
        if (Get-Command -Name Get-Uptime -ErrorAction SilentlyContinue) {
            $uptime = Get-Uptime
            $since = Get-Uptime -Since
            Write-Host "System started on: $($since.ToString('dddd, MMMM dd, yyyy HH:mm:ss'))" -ForegroundColor DarkGray
            Write-Host ("Uptime: {0} days, {1} hours, {2} minutes, {3} seconds" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor Blue
        }
        else {
            $lastBoot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
            $uptime = (Get-Date) - $lastBoot
            Write-Host "System started on: $($lastBoot.ToString('dddd, MMMM dd, yyyy HH:mm:ss'))" -ForegroundColor DarkGray
            Write-Host ("Uptime: {0} days, {1} hours, {2} minutes, {3} seconds" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor Blue
        }
    }
    catch {
        Write-Error "An error occurred while retrieving system uptime."
    }
}

function update-profile {
    & $PROFILE
}

function unzip ($file) {
    Write-Output("Extracting", $file, "to", $pwd)
    $fullFile = Get-ChildItem -Path $pwd -Filter $file | ForEach-Object { $_.FullName }
    Expand-Archive -Path $fullFile -DestinationPath $pwd
}

function hb {
    if ($args.Length -eq 0) {
        Write-Error "No file path specified."
        return
    }
    $FilePath = $args[0]
    if (Test-Path $FilePath) {
        $Content = Get-Content $FilePath -Raw
    }
    else {
        Write-Error "File path does not exist."
        return
    }
    $uri = "http://bin.christitus.com/documents"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $Content -ErrorAction Stop
        $hasteKey = $response.key
        $url = "http://bin.christitus.com/$hasteKey"
        Set-Clipboard $url
        Write-Output $url
    }
    catch {
        Write-Error "Failed to upload the document. Error: $_"
    }
}

function df { Get-Volume }
function sed($file, $find, $replace) {
    (Get-Content $file).replace("$find", $replace) | Set-Content $file
}
function which($name) {
    Get-Command $name | Select-Object -ExpandProperty Definition
}
function export($name, $value) {
    set-item -force -path "env:$name" -value $value;
}
function pkill($name) {
    Get-Process $name -ErrorAction SilentlyContinue | Stop-Process
}
function pgrep($name) {
    Get-Process $name
}
function head {
    param($Path, $n = 10)
    Get-Content $Path -Head $n
}
function tail {
    param($Path, $n = 10, [switch]$f = $false)
    Get-Content $Path -Tail $n -Wait:$f
}

function du {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Path
    )
    process {
        foreach ($p in $Path) {
            if (-not (Test-Path -Path $p)) {
                Write-Error "Cannot access '$p': No such file or directory"
                continue
            }
            $bytes = (Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($null -eq $bytes) { $bytes = 0 }
            if ($bytes -ge 1GB) { "{0:N2} GB`t{1}" -f ($bytes / 1GB), $p }
            elseif ($bytes -ge 1MB) { "{0:N2} MB`t{1}" -f ($bytes / 1MB), $p }
            elseif ($bytes -ge 1KB) { "{0:N2} KB`t{1}" -f ($bytes / 1KB), $p }
            else { "{0} Bytes`t{1}" -f $bytes, $p }
        }
    }
}

# Quick File Creation
function nf { param($name) New-Item -ItemType "file" -Path . -Name $name }

# Directory Management
function mkcd { param($dir) mkdir $dir -Force; Set-Location $dir }

function trash($path) {
    $fullPath = (Resolve-Path -Path $path).Path
    if (Test-Path $fullPath) {
        $item = Get-Item $fullPath
        $parentPath = if ($item.PSIsContainer) { $item.Parent.FullName } else { $item.DirectoryName }
        $shell = New-Object -ComObject 'Shell.Application'
        $shellItem = $shell.NameSpace($parentPath).ParseName($item.Name)
        if ($item) {
            $shellItem.InvokeVerb('delete')
            Write-Host "Item '$fullPath' has been moved to the Recycle Bin."
        }
        else {
            Write-Host "Error: Could not find the item '$fullPath' to trash."
        }
    }
    else {
        Write-Host "Error: Item '$fullPath' does not exist."
    }
}

# Navigation Shortcuts
function docs {
    $docs = if (([Environment]::GetFolderPath("MyDocuments"))) { ([Environment]::GetFolderPath("MyDocuments")) } else { $HOME + "\Documents" }
    Set-Location -Path $docs
}
function dtop {
    $dtop = if ([Environment]::GetFolderPath("Desktop")) { [Environment]::GetFolderPath("Desktop") } else { $HOME + "\Documents" }
    Set-Location -Path $dtop
}
function dev { Set-Location 'D:\Code' }

# Simplified Process Management
function k9 { Stop-Process -Name $args[0] }

# Enhanced Listing
function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . | Format-Table -AutoSize }

# Git Shortcuts
function gs { git status }
function ga { git add . }
function gc { param($m) git commit -m "$m" }
function gpush { git push }
function gpull { git pull }
function g { __zoxide_z github }
function gcl { git clone "$args" }
function gcom {
    git add .
    git commit -m "$args"
}
function lazyg {
    git add .
    git commit -m "$args"
    git push
}

# Quick Access to System Information
function sysinfo { Get-ComputerInfo }

# Networking Utilities
function flushdns {
    Clear-DnsClientCache
    Write-Host "DNS has been flushed"
}

# System Management
function Restart-System { C:\Windows\System32\shutdown.exe /r /t 0 }
function Restart-Uefi { C:\Windows\System32\shutdown.exe /r /fw /f /t 0 }
Set-Alias -Name reboot -Value Restart-System
Set-Alias -Name reboot-uefi -Value Restart-Uefi

# Clipboard Utilities
function cpy { Set-Clipboard $args[0] }
function pst { Get-Clipboard }

# Enhanced PowerShell Experience
# Enhanced PSReadLine Configuration with Gruber Darker Theme
$PSReadLineOptions = @{
    EditMode                      = 'Emacs'
    HistoryNoDuplicates           = $true
    HistorySearchCursorMovesToEnd = $true
    Colors                        = @{
        Command   = '#E4E4E4'
        Parameter = '#73D936'
        Operator  = '#95A6C8'
        Variable  = '#A8A9A7'
        String    = '#FFDD33'
        Number    = '#FF5757'
        Type      = '#E4E4E4'
        Comment   = '#515151'
        Keyword   = '#9E94C8'
        Error     = '#F43841'
    }
    PredictionSource              = 'History'
    PredictionViewStyle           = 'ListView'
    BellStyle                     = 'None'
}
Set-PSReadLineOption @PSReadLineOptions

# Custom key handlers
Set-PSReadLineKeyHandler -Key   UpArrow           -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key   DownArrow         -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key   Tab               -Function MenuComplete
Set-PSReadLineKeyHandler -Chord 'Ctrl+d'          -Function DeleteChar
Set-PSReadLineKeyHandler -Chord 'Ctrl+w'          -Function BackwardDeleteWord
Set-PSReadLineKeyHandler -Chord 'Alt+d'           -Function DeleteWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow'  -Function BackwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+z'          -Function Undo
Set-PSReadLineKeyHandler -Chord 'Ctrl+y'          -Function Redo

# Custom functions for PSReadLine
Set-PSReadLineOption -AddToHistoryHandler {
    param($line)
    $sensitive = @('password', 'secret', 'token', 'apikey', 'connectionstring')
    $hasSensitive = $sensitive | Where-Object { $line -match $_ }
    return ($null -eq $hasSensitive)
}

# Custom key bindings for PSFzf
if (Get-Module -Name PSFzf) {
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -PSReadlineChordSetLocation 'Alt+c'
}

# Improved prediction settings
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -MaximumHistoryCount 10000

# Custom completion for common commands
$scriptblock = {
    param($wordToComplete, $commandAst, $cursorPosition)
    $customCompletions = @{
        'git'  = @('status', 'add', 'commit', 'push', 'pull', 'clone', 'checkout', 'switch', 'merge', 'rebase', 'tag', 'log', 'reflog', 'reset', 'revert', 'stash', 'fetch', 'remote', 'config', 'init', 'help')
        'npm'  = @('install', 'start', 'run', 'test', 'build')
        'deno' = @('run', 'compile', 'bundle', 'test', 'lint', 'fmt', 'cache', 'info', 'doc', 'upgrade')
    }
    $command = $commandAst.CommandElements[0].Value
    if ($customCompletions.ContainsKey($command)) {
        $customCompletions[$command] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
Register-ArgumentCompleter -Native -CommandName git, npm, deno -ScriptBlock $scriptblock

$scriptblock = {
    param($wordToComplete, $commandAst, $cursorPosition)
    dotnet complete --position $cursorPosition $commandAst.ToString() |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock $scriptblock

# Set Theme
$profileDir_omp = Split-Path -Parent $PROFILE
$themePath = "$profileDir_omp\oh-my-posh_cobalt2.omp.json"
if (Test-Path $themePath) {
    oh-my-posh init pwsh --config $themePath | Invoke-Expression
}
else {
    oh-my-posh init pwsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/cobalt2.omp.json | Invoke-Expression
}

# Set up zoxide
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
}

function z_and_list {
    __zoxide_z @args
    ll
}
Set-Alias -Name z -Value z_and_list -Option AllScope -Scope Global -Force
Set-Alias -Name zi -Value __zoxide_zi -Option AllScope -Scope Global -Force

# Help Function
function Show-Help {
    $helpText = @"
$($PSStyle.Foreground.Cyan)PowerShell Profile Help$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)
$($PSStyle.Foreground.Green)Update-PowerShell$($PSStyle.Reset) - Checks for the latest PowerShell release and updates if a new version is available.
$($PSStyle.Foreground.Green)Update-Profile$($PSStyle.Reset) - Updates the current user's PowerShell profile from the GitHub repository.
$($PSStyle.Foreground.Green)Edit-Profile$($PSStyle.Reset) - Opens the current user's profile for editing using the configured editor.
$($PSStyle.Foreground.Green)Clear-Cache$($PSStyle.Reset) - Clears Windows prefetch, temp files, and browser cache.
$($PSStyle.Foreground.Green)touch$($PSStyle.Reset) <file> - Creates a new empty file.
$($PSStyle.Foreground.Green)ff$($PSStyle.Reset) <name> - Finds files recursively with the specified name.
$($PSStyle.Foreground.Green)Get-PubIP$($PSStyle.Reset) - Retrieves the public IP address of the machine.
$($PSStyle.Foreground.Green)winutil$($PSStyle.Reset) - Runs the latest WinUtil full-release script from Chris Titus Tech.
$($PSStyle.Foreground.Green)uptime$($PSStyle.Reset) - Displays the system uptime.
$($PSStyle.Foreground.Green)update-profile$($PSStyle.Reset) - Reloads the current user's PowerShell profile.
$($PSStyle.Foreground.Green)unzip$($PSStyle.Reset) <file> - Extracts a zip file to the current directory.
$($PSStyle.Foreground.Green)hb$($PSStyle.Reset) <file> - Uploads the specified file's content to a hastebin-like service and returns the URL.
$($PSStyle.Foreground.Green)df$($PSStyle.Reset) - Displays information about volumes.
$($PSStyle.Foreground.Green)sed$($PSStyle.Reset) <file> <find> <replace> - Replaces text in a file.
$($PSStyle.Foreground.Green)which$($PSStyle.Reset) <name> - Shows the path of the command.
$($PSStyle.Foreground.Green)export$($PSStyle.Reset) <name> <value> - Sets an environment variable.
$($PSStyle.Foreground.Green)pkill$($PSStyle.Reset) <name> - Kills processes by name.
$($PSStyle.Foreground.Green)pgrep$($PSStyle.Reset) <name> - Lists processes by name.
$($PSStyle.Foreground.Green)head$($PSStyle.Reset) <path> [n] - Displays the first n lines of a file (default 10).
$($PSStyle.Foreground.Green)tail$($PSStyle.Reset) <path> [n] [-f] - Displays the last n lines of a file (default 10). Use -f to continuously monitor.
$($PSStyle.Foreground.Green)du$($PSStyle.Reset) <path> - Shows disk usage of the specified path(s).
$($PSStyle.Foreground.Green)nf$($PSStyle.Reset) <name> - Creates a new file with the specified name.
$($PSStyle.Foreground.Green)mkcd$($PSStyle.Reset) <dir> - Creates and changes to a new directory.
$($PSStyle.Foreground.Green)trash$($PSStyle.Reset) <path> - Moves a file or directory to the Recycle Bin instead of permanently deleting.
$($PSStyle.Foreground.Green)docs$($PSStyle.Reset) - Changes the current directory to the user's Documents folder.
$($PSStyle.Foreground.Green)dtop$($PSStyle.Reset) - Changes the current directory to the user's Desktop folder.
$($PSStyle.Foreground.Green)dev$($PSStyle.Reset) - Changes the current directory to D:\Code.
$($PSStyle.Foreground.Green)ep$($PSStyle.Reset) - Alias for Edit-Profile, opens the profile for editing.
$($PSStyle.Foreground.Green)vim$($PSStyle.Reset) - Alias for the configured editor ($EDITOR).
$($PSStyle.Foreground.Green)k9$($PSStyle.Reset) <name> - Kills a process by name.
$($PSStyle.Foreground.Green)la$($PSStyle.Reset) - Lists all files in the current directory with detailed formatting.
$($PSStyle.Foreground.Green)ll$($PSStyle.Reset) - Lists all files, including hidden, in the current directory with detailed formatting.
$($PSStyle.Foreground.Green)sysinfo$($PSStyle.Reset) - Displays detailed system information.
$($PSStyle.Foreground.Green)flushdns$($PSStyle.Reset) - Clears the DNS cache.
$($PSStyle.Foreground.Green)reboot$($PSStyle.Reset) - Alias for Restart-System, restarts the computer immediately.
$($PSStyle.Foreground.Green)reboot-uefi$($PSStyle.Reset) - Alias for Restart-Uefi, restarts the computer and boots into UEFI/BIOS.
$($PSStyle.Foreground.Green)cpy$($PSStyle.Reset) <text> - Copies the specified text to the clipboard.
$($PSStyle.Foreground.Green)pst$($PSStyle.Reset) - Retrieves text from the clipboard.
$($PSStyle.Foreground.Green)z$($PSStyle.Reset) <dir> - Smart directory navigation using zoxide (jump to frequently used directories).
$($PSStyle.Foreground.Green)zi$($PSStyle.Reset) <dir> - Interactive directory selection using zoxide with fzf.

"@
    Write-Host $helpText
}
