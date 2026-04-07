### PowerShell Profile based on https://github.com/ChrisTitusTech/powershell-profile

# Opt-out of telemetry before doing anything, only if PowerShell is run as admin
if ($null -eq $env:POWERSHELL_TELEMETRY_OPTOUT -and [bool]([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem) {
    [System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'true', [System.EnvironmentVariableTarget]::Machine)
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
        $currentVersion = [version]$PSVersionTable.PSVersion.ToString()
        $gitHubApiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $latestReleaseInfo = Invoke-RestMethod -Uri $gitHubApiUrl
        $latestVersion = [version]$latestReleaseInfo.tag_name.Trim('v')
        if ($currentVersion -lt $latestVersion) {
            $updateNeeded = $true
        }

        if ($updateNeeded) {
            Write-Host "Updating PowerShell..." -ForegroundColor Yellow
            & winget upgrade --id Microsoft.PowerShell -e --source winget --accept-source-agreements --accept-package-agreements
            $upgradeExitCode = $LASTEXITCODE

            $installedVersion = [version](Get-Command pwsh).Version.ToString()
            if ($installedVersion -ge $latestVersion) {
                Write-Host "PowerShell has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
                return
            }

            $installerType = $null
            $uninstallKeys = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
            )

            foreach ($key in $uninstallKeys) {
                $entry = Get-ChildItem $key -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                    Where-Object {
                        $_.DisplayName -like 'PowerShell 7*' -and
                        $_.UninstallString -match 'MsiExec\.exe'
                    } |
                    Select-Object -First 1

                if ($entry) {
                    $installerType = 'MSI'
                    break
                }
            }

            if ($installerType -eq 'MSI') {
                Write-Warning "Winget could not upgrade this PowerShell install in place. The current installation is MSI-based."
                Write-Host "Clean reinstall commands:" -ForegroundColor Yellow
                Write-Host "  winget uninstall --id Microsoft.PowerShell -e --all-versions --force" -ForegroundColor Yellow
                Write-Host "  winget install --id Microsoft.PowerShell -e --scope machine --source winget --accept-source-agreements --accept-package-agreements" -ForegroundColor Yellow
                return
            }

            if ($upgradeExitCode -ne 0) {
                Write-Error "PowerShell upgrade failed with exit code $upgradeExitCode."
                return
            }

            Write-Warning "Winget finished, but the installed PowerShell version is still $installedVersion."
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

function Test-IsInteractiveTerminal {
    if (-not $Host.UI -or -not $Host.UI.RawUI) {
        return $false
    }

    try {
        return (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
    }
    catch {
        return $false
    }
}

function Test-IsSshSession {
    return (
        -not [string]::IsNullOrWhiteSpace($env:SSH_CONNECTION) -or
        -not [string]::IsNullOrWhiteSpace($env:SSH_CLIENT) -or
        -not [string]::IsNullOrWhiteSpace($env:SSH_TTY)
    )
}

function Test-SupportsVirtualTerminal {
    if (-not (Test-IsInteractiveTerminal)) {
        return $false
    }

    try {
        return [bool]$Host.UI.SupportsVirtualTerminal
    }
    catch {
        return $false
    }
}

function Get-ProfileSessionType {
    $requestedMode = "$env:POWERSHELL_PROFILE_MODE".Trim().ToLowerInvariant()
    switch ($requestedMode) {
        'full' { return 'desktop' }
        'interactive' { return 'desktop' }
        'desktop' { return 'desktop' }
        'ssh' { return 'ssh' }
        'remote' { return 'ssh' }
        'lean' { return 'noninteractive' }
        'minimal' { return 'noninteractive' }
        'noninteractive' { return 'noninteractive' }
    }

    if (-not (Test-IsInteractiveTerminal)) {
        return 'noninteractive'
    }

    if (Test-IsSshSession) {
        return 'ssh'
    }

    return 'desktop'
}

$script:ProfileSessionType = Get-ProfileSessionType
$script:IsSshSession = ($script:ProfileSessionType -eq 'ssh')
$script:IsDesktopProfile = ($script:ProfileSessionType -eq 'desktop')
$script:IsInteractiveProfile = $script:IsDesktopProfile -or $script:IsSshSession

function Write-SessionUnsupportedError {
    param([Parameter(Mandatory = $true)][string]$Feature)

    $sessionLabel = switch ($script:ProfileSessionType) {
        'ssh' { 'SSH' }
        'noninteractive' { 'non-interactive' }
        default { 'current' }
    }

    Write-Error "$Feature is not available in $sessionLabel PowerShell sessions."
}

function Test-CanUsePredictionListView {
    if (-not (Test-SupportsVirtualTerminal)) {
        return $false
    }

    try {
        $windowSize = $Host.UI.RawUI.WindowSize
        return ($windowSize.Width -ge 50) -and ($windowSize.Height -ge 5)
    }
    catch {
        return $false
    }
}

function Resolve-ExistingPathForNativeTool {
    param(
        [string]$Path,
        [ValidateSet('Any', 'Leaf', 'Container')]
        [string]$PathType = 'Any'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    catch {
        return $null
    }

    if ($PathType -eq 'Leaf' -and $item.PSIsContainer) {
        return $null
    }

    if ($PathType -eq 'Container' -and -not $item.PSIsContainer) {
        return $null
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

            if (Test-Path -LiteralPath $candidate -PathType $PathType -ErrorAction SilentlyContinue) {
                return $candidate
            }
        }
    }

    return $item.FullName
}

function Initialize-HomeAndGitEnvironment {
    $homeCandidates = @(
        $env:HOME,
        [Environment]::GetEnvironmentVariable('HOME', 'User'),
        $env:USERPROFILE,
        [Environment]::GetFolderPath('UserProfile'),
        ('{0}{1}' -f $env:HOMEDRIVE, $env:HOMEPATH)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $homeCandidates) {
        $resolvedHome = Resolve-ExistingPathForNativeTool -Path $candidate -PathType Container
        if ($resolvedHome) {
            $env:HOME = $resolvedHome
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE) -and -not [string]::IsNullOrWhiteSpace($env:HOME)) {
        $env:USERPROFILE = $env:HOME
    }

    $gitConfigCandidates = @(
        $env:GIT_CONFIG_GLOBAL,
        $(if ($env:HOME) { Join-Path $env:HOME '.gitconfig' }),
        $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.gitconfig' })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $gitConfigCandidates) {
        $resolvedGitConfig = Resolve-ExistingPathForNativeTool -Path $candidate -PathType Leaf
        if ($resolvedGitConfig) {
            $env:GIT_CONFIG_GLOBAL = $resolvedGitConfig
            break
        }
    }
}

if ($script:IsDesktopProfile) {
    $Host.UI.RawUI.WindowTitle = "PowerShell {0}$adminSuffix" -f $PSVersionTable.PSVersion.ToString()
}

Initialize-HomeAndGitEnvironment

$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
$script:ChocolateyProfileLoaded = $false

function Import-ChocolateyProfileOnDemand {
    if ($script:ChocolateyProfileLoaded) {
        return $true
    }

    if (-not (Test-Path $ChocolateyProfile -PathType Leaf)) {
        return $false
    }

    Import-Module $ChocolateyProfile -ErrorAction SilentlyContinue
    $script:ChocolateyProfileLoaded = $null -ne (Get-Command Update-SessionEnvironment -ErrorAction SilentlyContinue)
    return $script:ChocolateyProfileLoaded
}

function refreshenv {
    if (-not (Import-ChocolateyProfileOnDemand)) {
        Write-Error "Chocolatey profile is unavailable."
        return
    }

    Update-SessionEnvironment @args
}

function Resolve-ManagedExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [Parameter(Mandatory = $true)]
        [string]$ExecutableLeaf,
        [string[]]$AdditionalCandidates = @(),
        [string]$ScoopCurrentPath,
        [string]$WinGetPackagePattern,
        [switch]$AllowWinGetLink
    )

    $candidates = [System.Collections.Generic.List[string]]::new()

    $command = Get-Command $CommandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $commandSource = if ($command.Source) { $command.Source } elseif ($command.Path) { $command.Path } else { $null }
        if (
            $commandSource -and
            $commandSource -notlike '*\Microsoft\WindowsApps\*' -and
            ($AllowWinGetLink -or $commandSource -notlike '*\Microsoft\WinGet\Links\*')
        ) {
            $candidates.Add($commandSource)
        }
    }

    foreach ($candidate in $AdditionalCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $candidates.Add($candidate)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ScoopCurrentPath)) {
        $candidates.Add($ScoopCurrentPath)
    }

    if (-not [string]::IsNullOrWhiteSpace($WinGetPackagePattern)) {
        $wingetPackagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        if (Test-Path $wingetPackagesRoot -PathType Container) {
            $packagePath = Get-ChildItem -Path $wingetPackagesRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like $WinGetPackagePattern } |
                Sort-Object Name -Descending |
                Select-Object -First 1

            if ($packagePath) {
                $candidates.Add((Join-Path $packagePath.FullName $ExecutableLeaf))
            }
        }
    }

    if ($AllowWinGetLink -and -not $script:IsSshSession) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA ("Microsoft\WinGet\Links\{0}" -f $ExecutableLeaf)))
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        $resolvedPath = Resolve-ExistingPathForNativeTool -Path $candidate -PathType Leaf
        if ($resolvedPath) {
            return $resolvedPath
        }
    }

    return $null
}

function Get-OhMyPoshExecutable {
    return Resolve-ManagedExecutable -CommandName 'oh-my-posh' -ExecutableLeaf 'oh-my-posh.exe' -AdditionalCandidates @(
        (Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin\oh-my-posh.exe'),
        (Join-Path $env:ProgramFiles 'oh-my-posh\bin\oh-my-posh.exe')
    ) -ScoopCurrentPath (Join-Path $env:USERPROFILE 'scoop\apps\oh-my-posh\current\bin\oh-my-posh.exe')
}

function Get-ZoxideExecutable {
    return Resolve-ManagedExecutable -CommandName 'zoxide' -ExecutableLeaf 'zoxide.exe' -ScoopCurrentPath (Join-Path $env:USERPROFILE 'scoop\apps\zoxide\current\zoxide.exe') -WinGetPackagePattern 'ajeetdsouza.zoxide_*' -AllowWinGetLink
}

function Get-FzfExecutable {
    return Resolve-ManagedExecutable -CommandName 'fzf' -ExecutableLeaf 'fzf.exe' -AdditionalCandidates @(
        $(if ($env:ChocolateyInstall) { Join-Path $env:ChocolateyInstall 'bin\fzf.exe' })
    ) -ScoopCurrentPath (Join-Path $env:USERPROFILE 'scoop\apps\fzf\current\fzf.exe') -WinGetPackagePattern 'junegunn.fzf_*' -AllowWinGetLink
}

function Set-ZoxideCommandWrapper {
    param([string]$FilePath)

    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return
    }

    $script:ZoxideExecutable = $FilePath

    function global:zoxide {
        if (-not $script:ZoxideExecutable) {
            Write-Error "zoxide executable is not configured."
            return
        }

        & $script:ZoxideExecutable @args
    }
}

function Add-NativeToolDirectoryToPath {
    param([string]$FilePath)

    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return
    }

    $toolDirectory = Split-Path -Parent $FilePath
    if ([string]::IsNullOrWhiteSpace($toolDirectory) -or -not (Test-Path $toolDirectory -PathType Container)) {
        return
    }

    $pathEntries = @($env:PATH -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $normalizedDirectory = $toolDirectory.TrimEnd('\')
    $alreadyPresent = $pathEntries | Where-Object { $_.TrimEnd('\') -ieq $normalizedDirectory } | Select-Object -First 1
    if ($alreadyPresent) {
        return
    }

    $env:PATH = "$toolDirectory;$env:PATH"
}

function Sync-OhMyPoshExecutable {
    param(
        [int]$RefreshHours = 12
    )

    $targetPath = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin\oh-my-posh.exe'
    $targetDir = Split-Path -Parent $targetPath
    $packageStampPath = Join-Path $targetDir 'oh-my-posh.package.txt'

    if ((Test-Path $targetPath -PathType Leaf) -and (Test-Path $packageStampPath -PathType Leaf)) {
        $lastCheck = (Get-Item $packageStampPath -ErrorAction SilentlyContinue).LastWriteTime
        if ($lastCheck -and $lastCheck -gt (Get-Date).AddHours(-$RefreshHours)) {
            return $targetPath
        }
    }

    $appxRegistryKey = Get-ChildItem 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages' -ErrorAction SilentlyContinue |
        Where-Object PSChildName -like 'ohmyposh.cli_*' |
        Select-Object -First 1

    if (-not $appxRegistryKey) {
        return $null
    }

    $packageRoot = (Get-ItemProperty $appxRegistryKey.PSPath -ErrorAction SilentlyContinue).PackageRootFolder
    if (-not $packageRoot) {
        return $null
    }

    $sourcePath = Join-Path $packageRoot 'oh-my-posh.exe'
    if (-not (Test-Path $sourcePath -PathType Leaf)) {
        return $null
    }

    if (-not (Test-Path $targetDir -PathType Container)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $packageStamp = $appxRegistryKey.PSChildName
    $currentStamp = if (Test-Path $packageStampPath -PathType Leaf) {
        Get-Content $packageStampPath -Raw -ErrorAction SilentlyContinue
    }

    $shouldCopy = (-not (Test-Path $targetPath -PathType Leaf)) -or ($currentStamp -ne $packageStamp)
    if (-not $shouldCopy) {
        return $targetPath
    }

    if ($shouldCopy) {
        & robocopy $packageRoot $targetDir 'oh-my-posh.exe' /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS | Out-Null
        if ($LASTEXITCODE -ge 8 -or -not (Test-Path $targetPath -PathType Leaf)) {
            return $null
        }

        Set-Content -Path $packageStampPath -Value $packageStamp -Encoding ASCII
    }

    return $targetPath
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
$script:PreferredEditor = $null

function Get-PreferredEditor {
    if ($script:PreferredEditor) {
        return $script:PreferredEditor
    }

    $script:PreferredEditor = if (Get-Command code -CommandType Application -ErrorAction SilentlyContinue) { 'code' }
    elseif (Get-Command nvim -CommandType Application -ErrorAction SilentlyContinue) { 'nvim' }
    elseif (Get-Command vim -CommandType Application -ErrorAction SilentlyContinue) { 'vim' }
    elseif (Get-Command notepad++ -CommandType Application -ErrorAction SilentlyContinue) { 'notepad++' }
    else { 'notepad' }

    return $script:PreferredEditor
}

function vim {
    & (Get-PreferredEditor) @args
}

# Quick Access to Editing the Profile
function Edit-Profile {
    & (Get-PreferredEditor) $PROFILE.CurrentUserAllHosts
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

function Invoke-Profile {
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
        if ($script:IsDesktopProfile) {
            Set-Clipboard $url
        }
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
function Invoke-ProfileLocationChange {
    param([Parameter(Mandatory = $true)][string]$Path)

    $cdFunction = Get-Command cd -CommandType Function -ErrorAction SilentlyContinue
    if ($cdFunction) {
        & $cdFunction $Path
        return
    }

    Set-Location -LiteralPath $Path
}

function mkcd { param($dir) mkdir $dir -Force; Invoke-ProfileLocationChange -Path $dir }

function trash($path) {
    if (-not $script:IsDesktopProfile) {
        Write-SessionUnsupportedError -Feature 'trash'
        return
    }

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
    Invoke-ProfileLocationChange -Path $docs
}
function dtop {
    $dtop = if ([Environment]::GetFolderPath("Desktop")) { [Environment]::GetFolderPath("Desktop") } else { $HOME + "\Documents" }
    Invoke-ProfileLocationChange -Path $dtop
}
function dev { Invoke-ProfileLocationChange -Path 'D:\Code' }

# Simplified Process Management
function k9 { Stop-Process -Name $args[0] }

# Enhanced Listing
function la {
    if (-not (Get-Module -Name Terminal-Icons)) { Import-Module Terminal-Icons -ErrorAction SilentlyContinue }
    Get-ChildItem -Path . -Force | Format-Table -AutoSize
}
function ll {
    if (-not (Get-Module -Name Terminal-Icons)) { Import-Module Terminal-Icons -ErrorAction SilentlyContinue }
    Get-ChildItem -Path . | Format-Table -AutoSize
}

# Git Shortcuts
function gs { git status }
function ga { git add . }
function gc { param($m) git commit -m "$m" }
function gpush { git push }
function gpull { git pull }
function g {
    if (Get-Command __zoxide_z -ErrorAction SilentlyContinue) {
        __zoxide_z github
        return
    }

    Write-Error "zoxide is not initialized in $($script:ProfileSessionType) profile sessions."
}
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
function cpy {
    if (-not $script:IsDesktopProfile) {
        Write-SessionUnsupportedError -Feature 'cpy'
        return
    }

    Set-Clipboard $args[0]
}
function pst {
    if (-not $script:IsDesktopProfile) {
        Write-SessionUnsupportedError -Feature 'pst'
        return
    }

    Get-Clipboard
}

# Enhanced PowerShell Experience
# Enhanced PSReadLine Configuration with Gruber Darker Theme

function Initialize-PSReadLine {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    if (-not (Get-Module -Name PSReadLine)) {
        return
    }

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
        BellStyle                     = 'None'
        MaximumHistoryCount           = 10000
    }

    if (Test-SupportsVirtualTerminal) {
        $PSReadLineOptions.PredictionSource = 'HistoryAndPlugin'
        $PSReadLineOptions.PredictionViewStyle = if (Test-CanUsePredictionListView) { 'ListView' } else { 'InlineView' }
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

}

function Initialize-NativeArgumentCompleters {
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
            $customCompletions[$command] |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
    }
    Register-ArgumentCompleter -Native -CommandName git, npm, deno -ScriptBlock $scriptblock

    if (Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue) {
        $scriptblock = {
            param($wordToComplete, $commandAst, $cursorPosition)
            dotnet complete --position $cursorPosition $commandAst.ToString() |
                ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock $scriptblock
    }
}

function Initialize-OhMyPosh {
    # Set Theme
    if ($script:IsDesktopProfile) {
        try {
            $null = Sync-OhMyPoshExecutable
        }
        catch {
            Write-Verbose "Skipping oh-my-posh sync: $_"
        }
    }

    $ohMyPoshPath = Get-OhMyPoshExecutable
    if ($ohMyPoshPath) {
        $themePath = Join-Path (Split-Path -Parent $PROFILE) "oh-my-posh_cobalt2.omp.json"
        $themeConfig = if (Test-Path $themePath -PathType Leaf) {
            $themePath
        }
        else {
            'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/cobalt2.omp.json'
        }

        try {
            & $ohMyPoshPath init pwsh --config $themeConfig | Invoke-Expression
            $global:_ompExecutable = $ohMyPoshPath
        }
        catch {
            Write-Verbose "Skipping oh-my-posh initialization: $_"
        }
    }
}

function Initialize-Zoxide {
    # Set up zoxide
    $zoxidePath = Get-ZoxideExecutable
    if ($zoxidePath) {
        Set-ZoxideCommandWrapper -FilePath $zoxidePath
        $zoxideCache = Join-Path $env:TEMP "zoxide_cache.ps1"
        if (-not (Test-Path $zoxideCache)) {
            & $zoxidePath init --cmd cd powershell | Out-String | Out-File $zoxideCache -Encoding utf8
        }
        . $zoxideCache

        function global:z_and_list {
            __zoxide_z @args
            ll
        }
        Set-Alias -Name z -Value z_and_list -Option AllScope -Scope Global -Force
        Set-Alias -Name zi -Value __zoxide_zi -Option AllScope -Scope Global -Force
    }
}

function Initialize-PSFzf {
    if (-not (Get-Module -Name PSReadLine)) {
        return
    }

    $fzfPath = Get-FzfExecutable
    if (-not $fzfPath) {
        return
    }

    Add-NativeToolDirectoryToPath -FilePath $fzfPath

    if (Get-Module -Name PSFzf -ListAvailable) {
        try {
            Import-Module PSFzf -ErrorAction Stop
            if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
                Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -PSReadlineChordSetLocation 'Alt+c'
            }
        }
        catch {
            Write-Verbose "Skipping PSFzf initialization: $_"
        }
    }
}

function Initialize-InteractiveShell {
    Initialize-PSReadLine
    Initialize-NativeArgumentCompleters
    Initialize-OhMyPosh
    Initialize-Zoxide
    Initialize-PSFzf
}

if ($script:IsInteractiveProfile) {
    Initialize-InteractiveShell
}

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
$($PSStyle.Foreground.Green)Invoke-Profile$($PSStyle.Reset) - Reloads the current user's PowerShell profile.
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
