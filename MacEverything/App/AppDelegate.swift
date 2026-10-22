import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var hotkeyManager: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var mcpMenuItems: [MCPClient: NSMenuItem] = [:]
    private(set) var mainSearchWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MacSearchBridge.initializeLogger()

        let shouldMinimize = Self.shouldStartMinimized()

        // Delay by one frame to let SwiftUI create the window
        DispatchQueue.main.async { [weak self] in
            self?.mainSearchWindow = NSApp.windows.first { $0.title == "MacEverything" }
            if shouldMinimize {
                self?.mainSearchWindow?.orderOut(nil)
                NSApp.hide(nil)
            } else {
                self?.configureMainWindow()
            }
        }
        hotkeyManager = HotkeyManager()
        hotkeyManager?.register()
        NotificationCenter.default.addObserver(self, selector: #selector(showStatusIcon),
                                               name: .showStatusBarIcon, object: nil)
        UpdateService.shared.start()
        setupStatusBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DispatchQueue.global(qos: .userInitiated).async {
            MacSearchBridge.shared().prepareForTermination()
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Safety net: shutdown is idempotent (compare_exchange_strong guard)
        MacSearchBridge.shared().prepareForTermination()
    }

    /// Blend the native title bar into the content area while keeping the
    /// standard traffic lights, fullscreen and drag behaviour intact.
    private func configureMainWindow() {
        guard let window = mainSearchWindow else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        WindowPresenter.presentMainWindow()
        NSApp.activate()
    }

    // MARK: - Status Bar

    private static let statusIconHiddenKey = "StatusIconHiddenPermanently"

    private func setupStatusBar() {
        guard !UserDefaults.standard.bool(forKey: Self.statusIconHiddenKey) else { return }
        createStatusItem()
    }

    private func createStatusItem() {
        guard statusItem == nil else {
            statusItem?.isVisible = true
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // Line-only template glyph so the icon follows the menu bar's
            // light/dark appearance automatically.
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "MacEverything")
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "显示 MacEverything", action: #selector(toggleWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "重建索引", action: #selector(rebuildIndex), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "快捷键设置…", action: #selector(openShortcutSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "内容设置…", action: #selector(openContentSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "搜索语法帮助…", action: #selector(openSearchSyntaxHelp), keyEquivalent: ""))

        let mcpSubmenu = NSMenu(title: "MCP 集成")
        for client in MCPClient.allCases {
            let item = NSMenuItem(title: client.displayName, action: #selector(toggleMCPClient(_:)), keyEquivalent: "")
            item.representedObject = client
            mcpMenuItems[client] = item
            mcpSubmenu.addItem(item)
        }
        let mcpItem = NSMenuItem(title: "MCP 集成", action: nil, keyEquivalent: "")
        mcpItem.submenu = mcpSubmenu
        menu.addItem(mcpItem)

        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem = loginItem
        menu.addItem(loginItem)

        let hideSubmenu = NSMenu(title: "隐藏菜单栏图标")
        let hideOnceItem = NSMenuItem(title: "隐藏一次（下次启动恢复）",
                                      action: #selector(hideStatusIconOnce), keyEquivalent: "")
        hideOnceItem.target = self
        hideSubmenu.addItem(hideOnceItem)
        let hideForeverItem = NSMenuItem(title: "永久隐藏",
                                         action: #selector(hideStatusIconPermanently), keyEquivalent: "")
        hideForeverItem.target = self
        hideSubmenu.addItem(hideForeverItem)
        let hideItem = NSMenuItem(title: "隐藏菜单栏图标", action: nil, keyEquivalent: "")
        hideItem.submenu = hideSubmenu
        menu.addItem(hideItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "关于 MacEverything…", action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出 MacEverything", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        if let item = menu.items.first {
            let isVisible = mainSearchWindow?.isVisible ?? false
            item.title = isVisible ? "隐藏 MacEverything" : "显示 MacEverything"
        }
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        for (client, item) in mcpMenuItems {
            item.state = MCPConfigManager.isEnabled(for: client) ? .on : .off
        }
    }

    // MARK: - Menu Actions

    @objc private func toggleWindow() {
        if let window = mainSearchWindow, window.isVisible {
            NSApp.hide(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            WindowPresenter.presentMainWindow()
        }
    }

    @objc private func rebuildIndex() {
        NSApp.activate(ignoringOtherApps: true)
        mainSearchWindow?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .rebuildIndex, object: nil)
    }

    @objc private func openShortcutSettings() {
        NSApp.activate(ignoringOtherApps: true)
        ShortcutSettingsWindowController.shared.showWindow()
    }

    @objc private func openContentSettings() {
        NSApp.activate(ignoringOtherApps: true)
        ContentSettingsWindowController.shared.showWindow()
    }

    @objc private func openSearchSyntaxHelp() {
        NSApp.activate(ignoringOtherApps: true)
        SearchSyntaxHelpWindowController.shared.showWindow()
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        AboutWindowController.shared.showWindow()
    }

    // MARK: - Status Icon Visibility

    @objc private func hideStatusIconOnce() {
        // 只在本次运行期间隐藏，下次启动自动恢复。
        statusItem?.isVisible = false
    }

    @objc private func hideStatusIconPermanently() {
        UserDefaults.standard.set(true, forKey: Self.statusIconHiddenKey)
        statusItem?.isVisible = false
    }

    @objc func showStatusIcon() {
        UserDefaults.standard.set(false, forKey: Self.statusIconHiddenKey)
        if statusItem == nil {
            createStatusItem()
        } else {
            statusItem?.isVisible = true
        }
    }

    @objc private func toggleMCPClient(_ sender: NSMenuItem) {
        guard let client = sender.representedObject as? MCPClient else { return }
        let currentlyEnabled = MCPConfigManager.isEnabled(for: client)
        MCPConfigManager.setEnabled(!currentlyEnabled, for: client)
        sender.state = !currentlyEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            AppLogger.error("App", "Failed to toggle launch at login: \(error)")
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch Mode Detection

    private static func shouldStartMinimized() -> Bool {
        if CommandLine.arguments.contains("--minimized") {
            return true
        }
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.stringValue == "com.apple.loginwindow" {
            return true
        }
        return false
    }
}
