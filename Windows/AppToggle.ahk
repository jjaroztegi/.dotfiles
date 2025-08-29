#Requires AutoHotkey >=v2.0.0+ 64-bit

;==== Environment Variables ====
LocalAppData := EnvGet("LocalAppData")

;=========== Hotkeys ===========
; Short press: select window
; Long press: enter cycle mode

; Alt+Shift+1 -> Chrome
!+1::AppHotkey("chrome.exe", "chrome", "1")
!+1 Up::AppHotkeyUp("1")

; Alt+Shift+2 -> VS Code
!+2::AppHotkey("Code.exe", "code", "2")
!+2 Up::AppHotkeyUp("2")

; Alt+Shift+A -> Task Manager
!+a::AppHotkey("Taskmgr.exe", "taskmgr", "a")
!+a Up::AppHotkeyUp("a")

; Alt+Shift+C -> Clash of Clans
!+c::AppHotkey("crosvm.exe", "googleplaygames://launch/?id=com.supercell.clashofclans&lid=1&pid=1", "c")
!+c Up::AppHotkeyUp("c")

; Alt+Shift+D -> Discord
!+d::AppHotkey("Discord.exe", LocalAppData . "\Discord\Update.exe --processStart Discord.exe", "d")
!+d Up::AppHotkeyUp("d")

; Alt+Shift+E -> File Explorer
!+e::ToggleExplorer()

; Alt+Shift+N -> Notepad
!+n::AppHotkey("Notepad.exe", "notepad", "n")
!+n Up::AppHotkeyUp("n")

; Alt+Shift+S -> Settings
!+s::AppHotkey("SystemSettings.exe", "ms-settings:", "s")
!+s Up::AppHotkeyUp("s")

; Alt+Shift+W -> WhatsApp
!+w::AppHotkey("WhatsApp.exe", "shell:AppsFolder\5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App", "w")
!+w Up::AppHotkeyUp("w")

; Alt+Shift+T -> Windows Terminal
!+t::AppHotkey("WindowsTerminal.exe", "shell:AppsFolder\Microsoft.WindowsTerminal_8wekyb3d8bbwe!App", "t")
!+t Up::AppHotkeyUp("t")

; Global context for long-press cycle mode
global appCycle := { active:false
    , key:""
    , processName:""
    , runCmd:""
    , pressTimer: false
    , startTick: 0
    , threshold: 100
    , lb: false
    , windowMap: false
    , count: 0
    , downPressed: false ; debounce flag
    , gui: false
    , longPressTriggered: false
    , cycleInitPending: false
    , releasedDuringInit: false
    , finalizeTimer: false }

global appCycleSuppressUntil := 0 ; tick count to suppress immediate reopen

AppHotkey(processName, runCmd, key) {
    global appCycle, appCycleSuppressUntil
    if (A_TickCount < appCycleSuppressUntil)
        return
    ; If already in cycle mode and same key pressed again: advance
    if (appCycle.active && appCycle.key = key) {
        CycleAdvance()
        return
    }
    if (appCycle.active) {
        return
    }
    ; Start long press detection
    appCycle.key := key
    appCycle.processName := processName
    appCycle.runCmd := runCmd
    appCycle.pressTimer := True
    appCycle.startTick := A_TickCount
    appCycle.longPressTriggered := false
    appCycle.cycleInitPending := false
    appCycle.releasedDuringInit := false
    SetTimer(LongPressCheck, -appCycle.threshold)
}

AppHotkeyUp(key) {
    global appCycle
    if (appCycle.key != key)
        return
    if (appCycle.active) {
        appCycle.downPressed := false
        return
    }
    ; If long press path already triggered but GUI still initializing, mark release.
    if (appCycle.longPressTriggered && appCycle.cycleInitPending) {
        appCycle.releasedDuringInit := true
        return
    }
    elapsed := A_TickCount - appCycle.startTick
    if (elapsed < appCycle.threshold && appCycle.pressTimer && !appCycle.longPressTriggered) {
        ; Short press
        appCycle.pressTimer := False
        SetTimer(LongPressCheck, 0)
        ToggleApp(appCycle.processName, appCycle.runCmd)
        appCycle.key := ""
        appCycle.processName := ""
        appCycle.runCmd := ""
    } else {
        ; Long press pending: do nothing, LongPressCheck will handle
    }
}

LongPressCheck() {
    global appCycle
    if (!appCycle.pressTimer)
        return
    if !(GetKeyState("Alt", "P") && GetKeyState("Shift", "P")) {
        ToggleApp(appCycle.processName, appCycle.runCmd)
        appCycle.pressTimer := False
        appCycle.key := ""
        appCycle.longPressTriggered := false
        return
    }
    appCycle.longPressTriggered := true
    appCycle.cycleInitPending := true
    ToggleApp(appCycle.processName, appCycle.runCmd, true)
    if (!appCycle.active) {
        appCycle.pressTimer := False
        appCycle.key := ""
        appCycle.longPressTriggered := false
        appCycle.cycleInitPending := false
        appCycle.releasedDuringInit := false
    }
}

CycleAdvance() {
    global appCycle
    if !(appCycle.active && appCycle.lb)
        return
    if (appCycle.downPressed)
        return
    appCycle.downPressed := true
        curr := appCycle.lb.Value
    max := appCycle.count
    if (max = 0) {
        max := DllCall("SendMessage", "Ptr", appCycle.lb.Hwnd, "UInt", 0x018B, "Ptr", 0, "Ptr", 0, "Int")
        appCycle.count := max
    }
    curr := (curr >= max) ? 1 : curr + 1
    appCycle.lb.Value := curr
}

CycleFinalizeCheck() {
    global appCycle, appCycleSuppressUntil
    if !appCycle.active
        return
    if !(GetKeyState("Alt", "P") && GetKeyState("Shift", "P")) {
    ; finalize selection
        selectedTitle := appCycle.lb.Text
        if (appCycle.windowMap.Has(selectedTitle)) {
            WinActivate(appCycle.windowMap[selectedTitle])
        }
        ; cleanup
        try (appCycle.gui ? appCycle.gui.Destroy() : appCycle.lb.Gui.Destroy())
        appCycle.active := false
        appCycle.lb := false
        appCycle.windowMap := false
        appCycle.key := ""
        appCycle.processName := ""
        appCycle.runCmd := ""
        appCycle.gui := false
        appCycle.downPressed := false
        appCycle.pressTimer := false
    appCycle.longPressTriggered := false
    appCycle.cycleInitPending := false
    appCycle.releasedDuringInit := false
        appCycleSuppressUntil := A_TickCount + 250
        SetTimer(CycleFinalizeCheck, 0)
    }
}

;=========== Functions ===========

/**
 * Toggles a standard application. If multiple windows exist, it shows a modern,
 * auto-sizing, dark-theme selector.
 */
ToggleApp(ProcessName, RunCommand, cycleMode := false) {
    WinTitle := "ahk_exe " . ProcessName
    hwnds := WinGetList(WinTitle)

    if (hwnds.Length > 1) {
        ; --- 1. Data Preparation ---
        titles := []
        windowMap := Map()
        usedTitles := Map()
        for hwnd in hwnds {
            original := WinGetTitle(hwnd)
            if (original = "")
                continue
            ; Trim final " - Something" segment (e.g. "File.txt - Notepad")
            display := RegExReplace(original, "\s-\s[^-]+$")
            if (display = "")
                display := original
            ; Ensure uniqueness
            if (usedTitles.Has(display)) {
                usedTitles[display] += 1
                displayUnique := display " (" usedTitles[display] ")"
            } else {
                usedTitles[display] := 1
                displayUnique := display
            }
            titles.Push(displayUnique)
            windowMap[displayUnique] := hwnd
        }

        if (titles.Length = 0) {
            if (hwnds.Length > 0) WinActivate(hwnds[1])
                return
        }

        ; --- 2. Dynamic Width Calculation ---
        measureGui := Gui()
        measureGui.SetFont("s12", "Iosevka NFM")
        measureCtl := measureGui.AddText("Hidden", "")
        ; WM_GETFONT = 0x31 to retrieve HFONT from the control.
        hFont := DllCall("SendMessage", "Ptr", measureCtl.Hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")

        hDC := DllCall("GetDC", "Ptr", 0, "UPtr")
        oldObj := DllCall("SelectObject", "Ptr", hDC, "Ptr", hFont, "Ptr")

        maxWidth := 0
        size := Buffer(8) ; SIZE struct {LONG cx; LONG cy;}
        for title in titles {
            DllCall("GetTextExtentPoint32W", "Ptr", hDC, "WStr", title, "Int", StrLen(title), "Ptr", size)
            width := NumGet(size, 0, "Int")
            if (width > maxWidth)
                maxWidth := width
        }
        ; Restore and release
        DllCall("SelectObject", "Ptr", hDC, "Ptr", oldObj)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)
        measureGui.Destroy()

        guiWidth := maxWidth + 15

        ; --- 3. GUI Creation ---
        myGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "Select a Window")
        myGui.BackColor := "2B2B2B"
        myGui.MarginX := 0
        myGui.MarginY := 0
        myGui.SetFont("s12 c000000", "Iosevka NFM")

        lb := myGui.Add("ListBox", "x0 y0 w" . guiWidth . " h1 vSelectedWindow", titles)
        lb.Value := 1
        itemHeight := DllCall("SendMessage", "Ptr", lb.Hwnd, "UInt", 0x01A1, "Ptr", 0, "Ptr", 0, "Int")
        visibleItems := Min(titles.Length, 18)
        listHeight := itemHeight * visibleItems + 4
        lb.Move(0, 0, guiWidth, listHeight)

        myGui.OnEvent("Close", (*) => myGui.Destroy())
        myGui.Show("w" guiWidth " h" listHeight " Center")

        if (!cycleMode) {
            ; --- 4. Keyboard Shortcuts ---
            cond := (*) => WinActive("ahk_id " myGui.Hwnd)
            HotIf cond
            Hotkey "Esc", CancelSelection, "On"     ; cancel
            Hotkey "^n", NextItem, "On"             ; next
            Hotkey "^p", PrevItem, "On"             ; prev
            Hotkey "Enter", activateSelected, "On"  ; activate
            HotIf                                   ; reset context 

            lb.OnEvent("DoubleClick", activateSelected)

            ; Timer to auto-cancel on lose focus
            guiAlive := true
            WatchFocus := (*) => (guiAlive && !WinActive("ahk_id " myGui.Hwnd)) ? CancelSelection() : ''
            SetTimer(WatchFocus, 100)
        } else {
            ; Cycle mode
            global appCycle
            appCycle.active := true
            appCycle.lb := lb
            appCycle.windowMap := windowMap
            appCycle.count := titles.Length
            appCycle.gui := myGui
            appCycle.pressTimer := false
                appCycle.downPressed := !appCycle.releasedDuringInit
                appCycle.cycleInitPending := false
                appCycle.releasedDuringInit := false

            SetTimer(CycleFinalizeCheck, 50)
        }

        if (!cycleMode) {
            activateSelected(*) {
                selectedTitle := lb.Text
                if (windowMap.Has(selectedTitle)) {
                    WinActivate(windowMap[selectedTitle])
                }
                CleanupHotkeys()
            }

            CancelSelection(*) {
                CleanupHotkeys()
            }

            NextItem(*) {
                curr := lb.Value
                max := titles.Length
                curr := (curr >= max) ? 1 : curr + 1
                lb.Value := curr
            }

            PrevItem(*) {
                curr := lb.Value
                max := titles.Length
                curr := (curr <= 1) ? max : curr - 1
                lb.Value := curr
            }

            CleanupHotkeys() {
                if !guiAlive
                    return
                guiAlive := false
                SetTimer(WatchFocus, 0)
                HotIf cond
                Hotkey "Esc", "Off"
                Hotkey "^n", "Off"
                Hotkey "^p", "Off"
                Hotkey "Enter", "Off"
                HotIf
                myGui.Destroy()
            }
        }
        return
    }

    if (hwnds.Length = 1) {
        hwnd := hwnds[1]
        if WinActive(hwnd)
            WinMinimize(hwnd)
        else
            WinActivate(hwnd)
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
