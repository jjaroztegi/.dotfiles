[CmdletBinding()]
param(
    [string]$SshTarget,
    [string[]]$SshOption = @(),
    [switch]$SshBatchMode,
    [switch]$SshDisableStrictHostKeyChecking,
    [switch]$CompareSsh,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$commandsToProbe = @('node', 'npm', 'npx', 'python', 'pip')

$probeScript = @'
$ErrorActionPreference = "Continue"
$commandsToProbe = @("node", "npm", "npx", "python", "pip")

function Get-VersionArguments {
    param([string]$Name)

    switch ($Name) {
        "python" { return @("--version") }
        "pip" { return @("--version") }
        default { return @("--version") }
    }
}

$results = foreach ($commandName in $commandsToProbe) {
    $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $path = if ($command) {
        if ($command.Source) { $command.Source } else { $command.Path }
    }
    else {
        $null
    }

    $version = $null
    $exitCode = $null
    if ($path) {
        try {
            $versionOutput = & $path @(Get-VersionArguments -Name $commandName) 2>&1
            $exitCode = $LASTEXITCODE
            $version = @($versionOutput | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -First 1)[0]
        }
        catch {
            $version = "ERROR: $($_.Exception.Message)"
            $exitCode = -1
        }
    }

    [pscustomobject]@{
        command = $commandName
        path = $path
        version = $version
        exitCode = $exitCode
    }
}

$results | ConvertTo-Json -Compress
'@

$encodedProbe = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probeScript))

function Invoke-ProbeScript {
    $scriptBlock = [scriptblock]::Create($probeScript)
    return @(& $scriptBlock)
}

function ConvertTo-ProbeRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Context,
        [Parameter(Mandatory = $true)]
        [string]$Kind,
        [Parameter(Mandatory = $true)]
        [object[]]$Rows,
        [int]$NativeExitCode = 0,
        [string]$ErrorText
    )

    if ($Rows.Count -eq 1 -and $Rows[0] -is [array]) {
        $Rows = @($Rows[0])
    }

    foreach ($row in $Rows) {
        [pscustomobject]@{
            context = $Context
            kind = $Kind
            command = $row.command
            path = $row.path
            version = $row.version
            commandExitCode = $row.exitCode
            nativeExitCode = $NativeExitCode
            error = $ErrorText
        }
    }
}

function Invoke-JsonContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Context,
        [Parameter(Mandatory = $true)]
        [string]$Kind,
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $jsonLine = @($output | ForEach-Object { "$_" } | Where-Object { $_.TrimStart().StartsWith('[') -or $_.TrimStart().StartsWith('{') } | Select-Object -Last 1)[0]

    if (-not $jsonLine) {
        return ConvertTo-ProbeRecords -Context $Context -Kind $Kind -Rows @(
            foreach ($commandName in $commandsToProbe) {
                [pscustomobject]@{ command = $commandName; path = $null; version = $null; exitCode = $null }
            }
        ) -NativeExitCode $exitCode -ErrorText (($output | ForEach-Object { "$_" }) -join "`n")
    }

    $rows = @($jsonLine | ConvertFrom-Json)
    return ConvertTo-ProbeRecords -Context $Context -Kind $Kind -Rows $rows -NativeExitCode $exitCode
}

function Normalize-CommandPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $normalized = $Path.Trim().Trim('"') -replace '/', '\'
    if ($normalized -match '^\\([A-Za-z])\\') {
        $normalized = ('{0}:\{1}' -f $matches[1].ToUpperInvariant(), $normalized.Substring(3))
    }

    $normalized = $normalized -replace '\.(exe|cmd|bat|ps1|com)$', ''
    return $normalized.TrimEnd('\')
}

function Test-PathContainsEntry {
    param(
        [string]$PathValue,
        [string]$ExpectedEntry
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedEntry)) {
        return $false
    }

    $expected = Normalize-CommandPath -Path $ExpectedEntry
    foreach ($entry in @($PathValue -split ';')) {
        if ((Normalize-CommandPath -Path $entry) -ieq $expected) {
            return $true
        }
    }

    return $false
}

function Get-PathEntryIndex {
    param(
        [string]$PathValue,
        [string]$ExpectedEntry
    )

    $expected = Normalize-CommandPath -Path $ExpectedEntry
    $entries = @($PathValue -split ';')
    for ($i = 0; $i -lt $entries.Count; $i++) {
        if ((Normalize-CommandPath -Path $entries[$i]) -ieq $expected) {
            return $i
        }
    }

    return -1
}

function Get-GitShPath {
    $candidates = @(
        (Get-Command sh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
        (Join-Path $env:ProgramFiles 'Git\bin\sh.exe'),
        (Join-Path $env:ProgramFiles 'Git\usr\bin\sh.exe'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Git\bin\sh.exe' }),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Git\usr\bin\sh.exe' })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Invoke-GitShDirectContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GitShPath,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $shellProbe = @'
for command_name in node npm npx python pip; do
  command_path="$(command -v "$command_name" 2>/dev/null || true)"
  if [ -n "$command_path" ] && command -v cygpath >/dev/null 2>&1; then
    command_path="$(cygpath -w "$command_path" 2>/dev/null || printf '%s' "$command_path")"
  fi

  version=""
  exit_code=""
  if [ -n "$command_path" ]; then
    version="$("$command_name" --version 2>&1 | tr -d '\r' | head -n 1)"
    exit_code="$?"
  fi

  printf '%s\t%s\t%s\t%s\n' "$command_name" "$command_path" "$version" "$exit_code"
done
'@

    $output = @(& $GitShPath -lc $shellProbe 2>&1)
    $exitCode = $LASTEXITCODE
    $rows = foreach ($line in $output) {
        $text = "$line"
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $parts = $text -split "`t", 4
        if ($parts.Count -lt 4) {
            continue
        }

        [pscustomobject]@{
            command = $parts[0]
            path = if ([string]::IsNullOrWhiteSpace($parts[1])) { $null } else { $parts[1] }
            version = if ([string]::IsNullOrWhiteSpace($parts[2])) { $null } else { $parts[2] }
            exitCode = if ([string]::IsNullOrWhiteSpace($parts[3])) { $null } else { [int]$parts[3] }
        }
    }

    $seenCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($rows)) {
        if ($row.command) {
            $seenCommands.Add($row.command) | Out-Null
        }
    }
    foreach ($commandName in $commandsToProbe) {
        if (-not $seenCommands.Contains($commandName)) {
            $rows += [pscustomobject]@{
                command = $commandName
                path = $null
                version = $null
                exitCode = $null
            }
        }
    }

    return ConvertTo-ProbeRecords -Context $Context -Kind 'local' -Rows @($rows) -NativeExitCode $exitCode
}

$contextResults = [System.Collections.Generic.List[object]]::new()

$currentRows = @(Invoke-ProbeScript | ConvertFrom-Json)
foreach ($record in @(ConvertTo-ProbeRecords -Context 'current-pwsh' -Kind 'local' -Rows $currentRows)) {
    $contextResults.Add($record)
}

$pwshCommand = (Get-Command pwsh -CommandType Application -ErrorAction Stop).Source
foreach ($record in @(Invoke-JsonContext -Context 'pwsh-profile-child' -Kind 'local' -FilePath $pwshCommand -Arguments @('-NoLogo', '-EncodedCommand', $encodedProbe))) {
    $contextResults.Add($record)
}
foreach ($record in @(Invoke-JsonContext -Context 'pwsh-NoProfile-NonInteractive' -Kind 'local' -FilePath $pwshCommand -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedProbe))) {
    $contextResults.Add($record)
}
foreach ($record in @(Invoke-JsonContext -Context 'cmd-husky-like' -Kind 'local' -FilePath "$env:SystemRoot\System32\cmd.exe" -Arguments @('/d', '/c', 'pwsh', '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedProbe))) {
    $contextResults.Add($record)
}

$gitShPath = Get-GitShPath
if ($gitShPath) {
    foreach ($record in @(Invoke-GitShDirectContext -Context 'git-sh-husky-like' -GitShPath $gitShPath)) {
        $contextResults.Add($record)
    }
}
else {
    foreach ($commandName in $commandsToProbe) {
        $contextResults.Add([pscustomobject]@{
            context = 'git-sh-husky-like'
            kind = 'local'
            command = $commandName
            path = $null
            version = $null
            commandExitCode = $null
            nativeExitCode = 127
            error = 'Git sh.exe was not found.'
        })
    }
}

if (-not [string]::IsNullOrWhiteSpace($SshTarget)) {
    $sshCommand = "pwsh -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedProbe"
    $effectiveSshOptions = [System.Collections.Generic.List[string]]::new()
    foreach ($option in @($SshOption)) {
        if (-not [string]::IsNullOrWhiteSpace($option)) {
            $effectiveSshOptions.Add($option) | Out-Null
        }
    }
    if ($SshBatchMode) {
        $effectiveSshOptions.Add('-oBatchMode=yes') | Out-Null
    }
    if ($SshDisableStrictHostKeyChecking) {
        $effectiveSshOptions.Add('-oStrictHostKeyChecking=no') | Out-Null
    }

    $sshArguments = @($effectiveSshOptions) + @($SshTarget, $sshCommand)
    foreach ($record in @(Invoke-JsonContext -Context "ssh:$SshTarget" -Kind 'ssh' -FilePath 'ssh' -Arguments $sshArguments)) {
        $contextResults.Add($record)
    }
}

$records = @($contextResults)
$comparisonKinds = @('local')
if ($CompareSsh) {
    $comparisonKinds += 'ssh'
}

$failures = [System.Collections.Generic.List[string]]::new()

$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$expectedPathEntries = @(
    (Join-Path $env:USERPROFILE '.pyenv\pyenv-win\shims'),
    (Join-Path $env:USERPROFILE '.pyenv\pyenv-win\bin'),
    (Join-Path $env:APPDATA 'fnm\aliases\default'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
)

foreach ($entry in $expectedPathEntries) {
    if ((Test-Path -LiteralPath $entry -PathType Container) -and -not (Test-PathContainsEntry -PathValue $userPath -ExpectedEntry $entry)) {
        $failures.Add("persistent User PATH does not contain expected entry '$entry'.") | Out-Null
    }
}

$pyenvShims = Join-Path $env:USERPROFILE '.pyenv\pyenv-win\shims'
$pyenvBin = Join-Path $env:USERPROFILE '.pyenv\pyenv-win\bin'
$pyenvShimsIndex = Get-PathEntryIndex -PathValue $userPath -ExpectedEntry $pyenvShims
$pyenvBinIndex = Get-PathEntryIndex -PathValue $userPath -ExpectedEntry $pyenvBin
if ($pyenvShimsIndex -ge 0 -and $pyenvBinIndex -ge 0 -and $pyenvShimsIndex -gt $pyenvBinIndex) {
    $failures.Add("persistent User PATH has pyenv-win bin before shims.") | Out-Null
}

$expectedFnmDir = Join-Path $env:APPDATA 'fnm'
$fnmDir = [System.Environment]::GetEnvironmentVariable('FNM_DIR', 'User')
if ((Test-Path -LiteralPath $expectedFnmDir -PathType Container) -and ((Normalize-CommandPath -Path $fnmDir) -ine (Normalize-CommandPath -Path $expectedFnmDir))) {
    $failures.Add("persistent User FNM_DIR is '$fnmDir', expected '$expectedFnmDir'.") | Out-Null
}

$expectedPyenvRoot = (Join-Path $env:USERPROFILE '.pyenv\pyenv-win').TrimEnd('\') + '\'
foreach ($name in @('PYENV', 'PYENV_ROOT', 'PYENV_HOME')) {
    $value = [System.Environment]::GetEnvironmentVariable($name, 'User')
    if ((Test-Path -LiteralPath $expectedPyenvRoot -PathType Container) -and ($value -cne $expectedPyenvRoot)) {
        $failures.Add("persistent User $name is '$value', expected '$expectedPyenvRoot'.") | Out-Null
    }
}

foreach ($commandName in $commandsToProbe) {
    $rows = @($records | Where-Object { $_.command -eq $commandName -and $comparisonKinds -contains $_.kind })
    $missing = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.path) -or $_.nativeExitCode -ne 0 -or $null -eq $_.commandExitCode -or $_.commandExitCode -ne 0 })
    foreach ($row in $missing) {
        $failures.Add("$($row.context): $commandName did not resolve cleanly. $($row.error)") | Out-Null
    }

    $resolvedRows = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.path) -and $_.nativeExitCode -eq 0 -and $_.commandExitCode -eq 0 })
    if ($resolvedRows.Count -gt 1) {
        $canonicalPath = Normalize-CommandPath -Path $resolvedRows[0].path
        foreach ($row in $resolvedRows) {
            $candidatePath = Normalize-CommandPath -Path $row.path
            if ($candidatePath -ine $canonicalPath) {
                $failures.Add("$($row.context): $commandName resolved to '$($row.path)', expected '$($resolvedRows[0].path)'.") | Out-Null
            }
        }
    }
}

$summary = [pscustomobject]@{
    computer = $env:COMPUTERNAME
    user = "$env:USERDOMAIN\$env:USERNAME"
    elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
    comparedKinds = $comparisonKinds
    ok = ($failures.Count -eq 0)
    failures = @($failures)
    records = $records
}

if ($Json) {
    $summary | ConvertTo-Json -Depth 6
}
else {
    "Runtime environment validation"
    "Computer : $($summary.computer)"
    "User     : $($summary.user)"
    "Elevated : $($summary.elevated)"
    "Compared : $($summary.comparedKinds -join ', ')"
    ""
    $records |
        Sort-Object context, command |
        Format-Table context, command, path, version, nativeExitCode, commandExitCode -AutoSize

    if ($failures.Count -gt 0) {
        ""
        "Failures:"
        $failures | ForEach-Object { " - $_" }
    }
}

if ($failures.Count -gt 0) {
    exit 1
}
