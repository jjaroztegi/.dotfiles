[CmdletBinding()]
param(
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'

$modulesDir = Join-Path $PSScriptRoot "modules"

Import-Module (Join-Path $modulesDir "RuntimeTooling.psm1") -Force

Invoke-RuntimeToolingSetup -Execute:$Execute
