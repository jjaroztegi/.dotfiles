function Install-DevTools {
    Write-LogInfo "Installing Developer Tools..."

    Install-Software -Name "Windows Terminal" -ExecutableName "wt" -WingetId "Microsoft.WindowsTerminal" -ScoopId "main/windows-terminal" -ChocoId "microsoft-windows-terminal"
    Install-Software -Name "PowerShell 7"   -ExecutableName "pwsh" -WingetId "Microsoft.PowerShell"      -ScoopId "main/pwsh"             -ChocoId "powershell-core"
    Install-Software -Name "fzf"      -ExecutableName "fzf" -ChocoId "fzf"      -ScoopId "main/fzf"      -WingetId "junegunn.fzf"
    Install-Software -Name "zoxide"   -ExecutableName "zoxide" -ChocoId "zoxide"   -ScoopId "main/zoxide"   -WingetId "ajeetdsouza.zoxide"
    Install-Software -Name "ripgrep"  -ExecutableName "rg" -ChocoId "ripgrep"  -ScoopId "main/ripgrep"  -WingetId "BurntSushi.ripgrep.MSVC"
    Install-Software -Name "oh-my-posh" -ExecutableName "oh-my-posh" -WingetId "JanDeDobbeleer.OhMyPosh" -ScoopId "main/oh-my-posh" -ChocoId "oh-my-posh"
    Install-Software -Name "winfetch" -ExecutableName "winfetch" -ChocoId "winfetch" -ScoopId "main/winfetch"
}

Export-ModuleMember -Function Install-DevTools
