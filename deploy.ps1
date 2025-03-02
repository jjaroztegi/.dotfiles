Import-Module .\ManifestHelpers.psm1

# Check and set HOME environment variable
$HomeExists = Test-Path Env:HOME
if ($HomeExists -ne $True) {
    Write-Output "Creating HOME environment variable and targeting it to $env:USERPROFILE"
    [Environment]::SetEnvironmentVariable("HOME", $env:USERPROFILE, "User")
}
else {
    Write-Warning "HOME environment variable already exists. Not modifying the existing value."
}

Deploy-Manifest MANIFEST.windows
