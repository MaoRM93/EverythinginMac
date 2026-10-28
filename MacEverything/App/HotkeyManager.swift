import Cocoa
import Carbon.HIToolbox

/// Default global shortcut: ⌘⇧F.
enum DefaultHotkey {
    static let keyCode = UInt32(kVK_ANSI_F)
    static let modifiers = UInt32(cmdKey | shiftKey)
}

/// Brings the main window back on screen and centres it on the display under
/// the pointer, so a summoned window never reappears at a stale corner.
enum WindowPresenter {
    static func presentMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.title == "MacEverything" }) else { return }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        let pointerScreen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }
        if let visible = (pointerScreen ?? NSScreen.main)?.visibleFrame {
            let size = window.frame.size
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - visible.height * 0.18
            )
            window.setFrame(NSRect(origin: origin, size: size), display: false)
        }

        window.makeKeyAndOrderFront(nil)

        // The window is now key, so the search field can take first responder.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusSearchField, object: nil)
        }
    }
}

class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var observer: NSObjectProtocol?

    func register() {
        migrateLegacyDefault()
        registerCurrentHotkey()

        observer = NotificationCenter.default.addObserver(
            forName: .hotkeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.unregisterHotkey()
            self?.registerCurrentHotkey()
        }
    }

    /// Older builds defaulted to ⌥Space. Replace only that untouched default
    /// with the new ⌘⇧F; user-customised shortcuts are preserved.
    private func migrateLegacyDefault() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "hotkeyKeyCode") != nil else { return }
        let keyCode = UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
        let modifiers = UInt32(defaults.integer(forKey: "hotkeyModifiers"))
        if keyCode == UInt32(kVK_Space) && modifiers == UInt32(optionKey) {
            defaults.set(Int(DefaultHotkey.keyCode), forKey: "hotkeyKeyCode")
            defaults.set(Int(DefaultHotkey.modifiers), forKey: "hotkeyModifiers")
        }
    }

    private func registerCurrentHotkey() {
        let defaults = UserDefaults.standard
        let keyCode: UInt32
        let modifiers: UInt32

        if defaults.object(forKey: "hotkeyKeyCode") != nil {
            keyCode = UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
            modifiers = UInt32(defaults.integer(forKey: "hotkeyModifiers"))
        } else {
            keyCode = DefaultHotkey.keyCode
            modifiers = DefaultHotkey.modifiers
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D455648), id: 1)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                          GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            AppLogger.error("Hotkey", "Failed to register hotkey: status \(status)")
        }

        // Only install event handler once
        if eventHandlerRef == nil {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
                // Always show the window and put the caret in the search field.
                NSApp.unhide(nil)
                NSApp.activate(ignoringOtherApps: true)
                WindowPresenter.presentMainWindow()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .focusSearchField, object: nil)
                }
                return noErr
            }, 1, &eventSpec, nil, &eventHandlerRef)
        }
    }

    private func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    deinit {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
        }
        unregisterHotkey()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
