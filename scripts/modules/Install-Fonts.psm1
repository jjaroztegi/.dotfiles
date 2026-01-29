function Install-NerdFonts {
    param (
        [string]$FontName = "Iosevka Nerd Font"
    )

    Write-LogInfo "Ensuring Nerd Fonts ($FontName) are installed..."

    if (-not (Test-IsAdmin)) {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                Install-Software -Name "Git" -ExecutableName "git" -ScoopId "main/git"
            }

            $buckets = scoop bucket list
            if ($buckets -notmatch "nerd-fonts") {
                Write-LogInfo "Adding nerd-fonts bucket to Scoop..."
                scoop bucket add nerd-fonts
            }
        }
    }

    Install-Software -Name "$FontName" -ChocoId "nerd-fonts-iosevka" -ScoopId "nerd-fonts/iosevka-nf-mono"
}

Export-ModuleMember -Function Install-NerdFonts
