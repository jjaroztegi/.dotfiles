;==== Environment Variables ====
LocalAppData := EnvGet("LocalAppData")

;=========== Hotkeys ===========

; Alt+Shift+1 -> Chrome
!+1:: ToggleApp("chrome.exe", "chrome")

; Alt+Shift+2 -> VSCode
!+2:: ToggleApp("Code.exe", "code")

; Alt+Shift+D -> Discord
!+d:: ToggleApp("Discord.exe", LocalAppData . "\Discord\Update.exe --processStart Discord.exe")

; Alt+Shift+E -> Explorer
!+e:: ToggleExplorer()

; Alt+Shift+W -> WhatsApp
!+w:: ToggleApp("WhatsApp.exe", "shell:AppsFolder\5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App")

; Alt+Shift+T -> Windows Terminal
!+t:: ToggleApp("WindowsTerminal.exe", "shell:AppsFolder\Microsoft.WindowsTerminal_8wekyb3d8bbwe!App")

;=========== Functions ===========

/**
 * Toggles a standard application.
 */
ToggleApp(ProcessName, RunCommand) {
    WinTitle := "ahk_exe " . ProcessName
    if WinExist(WinTitle) {
        if WinActive(WinTitle)
            WinMinimize(WinTitle)
        else
            WinActivate(WinTitle)
    } else {
        Run(RunCommand)
    }
}

/**
 * Toggles a File Explorer window (special case).
 */
ToggleExplorer() {
    WinTitle := "ahk_exe explorer.exe ahk_class CabinetWClass"
    if WinExist(WinTitle) {
        if WinActive(WinTitle)
            WinMinimize(WinTitle)
        else
            WinActivate(WinTitle)
    } else {
        Run("explorer.exe")
    }
}
