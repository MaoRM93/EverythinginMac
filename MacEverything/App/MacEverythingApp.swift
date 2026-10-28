import SwiftUI

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static let originalRepo = URL(string: "https://github.com/joshua-wu/MacEverything")!
    static let currentRepo = URL(string: "https://github.com/MaoRM93/EverythinginMac")!
}

@main
struct MacEverythingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var searchOptions = SearchOptions.shared

    init() {
        // Must run before any view reads the onboarding flags.
        PermissionGate.migrateIfNeeded()
    }

    var body: some Scene {
        Window("MacEverything", id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: GlassTheme.contentWidth + GlassTheme.windowPadding * 2,
                     height: GlassTheme.collapsedHeight + GlassTheme.windowPadding * 2)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 MacEverything") {
                    SettingsWindowController.shared.show(category: .about)
                }
                Button("检查更新…") {
                    UpdateService.shared.checkManually()
                }
                Button("显示菜单栏图标") {
                    NotificationCenter.default.post(name: .showStatusBarIcon, object: nil)
                }
            }

            CommandMenu("搜索") {
                Button("聚焦搜索框") {
                    NotificationCenter.default.post(name: .focusSearchField, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
                Divider()
                Toggle("正则表达式", isOn: $searchOptions.isRegex)
                    .keyboardShortcut("r", modifiers: [.command])
                Toggle("区分大小写", isOn: $searchOptions.isCaseSensitive)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Toggle("全词匹配", isOn: $searchOptions.isWholeWord)
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Toggle("匹配文件名", isOn: $searchOptions.isMatchFilename)
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("搜索语法帮助") {
                    SearchSyntaxHelpWindowController.shared.showWindow()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    SettingsWindowController.shared.show(category: .general)
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button("重建索引") {
                    NotificationCenter.default.post(name: .rebuildIndex, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let rebuildIndex = Notification.Name("rebuildIndex")
    static let focusSearchField = Notification.Name("focusSearchField")
    static let showStatusBarIcon = Notification.Name("showStatusBarIcon")
    static let hideStatusBarIconPermanently = Notification.Name("hideStatusBarIconPermanently")
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)

                    Text("MacEverything")
                        .font(.system(size: 18, weight: .semibold))

                    Text("版本 \(AppInfo.version)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Text("本地磁盘文件名搜索工具")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button("检查更新…") {
                        UpdateService.shared.checkManually()
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("项目地址") {
                Link(destination: AppInfo.originalRepo) {
                    Label("原作者仓库：joshua-wu/MacEverything", systemImage: "link")
                }
                Link(destination: AppInfo.currentRepo) {
                    Label("本版本仓库：MaoRM93/EverythinginMac", systemImage: "link")
                }
            }

            Section("我们关注您的隐私") {
                Text("文件索引仅保存在本机，不会上传任何数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("许可证") {
                Text("本版本基于原作者 joshua-wu 的 MacEverything（MIT 许可证）修改，仅供个人学习与使用，不进行任何商业销售或盈利。原项目版权归原作者所有，本版本中的修改部分由 MaoRM93 维护，并同样以 MIT 许可证公开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

class SearchSyntaxHelpWindowController {
    static let shared = SearchSyntaxHelpWindowController()
    private var window: NSWindow?

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let helpView = SearchSyntaxHelpView()
        let hostingController = NSHostingController(rootView: helpView)
        let win = NSWindow(contentViewController: hostingController)
        win.title = "搜索语法帮助"
        win.styleMask = [.titled, .closable, .resizable]
        win.setContentSize(NSSize(width: 580, height: 720))
        win.minSize = NSSize(width: 450, height: 400)
        win.center()
        win.makeKeyAndOrderFront(nil)
        window = win
    }
}
