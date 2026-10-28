import SwiftUI
import Combine
import ServiceManagement

// MARK: - Categories

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case search
    case scope
    case advanced
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .search: return "搜索"
        case .scope: return "搜索范围"
        case .advanced: return "高级选项"
        case .shortcuts: return "快捷键"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .search: return "magnifyingglass"
        case .scope: return "folder.fill"
        case .advanced: return "slider.horizontal.3"
        case .shortcuts: return "command"
        case .about: return "info"
        }
    }

    /// Lighter pastel tint for the rounded-square tile. The saturated System
    /// Settings colours looked too heavy inside this light sidebar.
    var iconColor: Color {
        switch self {
        case .general:   return Color(hex: 0xA1A1A6)
        case .search:    return Color(hex: 0x47A8FF)
        case .scope:     return Color(hex: 0x8B89F2)
        case .advanced:  return Color(hex: 0xFFBC54)
        case .shortcuts: return Color(hex: 0xFF6E8E)
        case .about:     return Color(hex: 0x54DB7E)
        }
    }
}

/// Shared selection so menu items can open the settings window on a specific
/// page instead of all landing on "通用".
final class SettingsSelection: ObservableObject {
    static let shared = SettingsSelection()

    @Published var category: SettingsCategory = .general

    private init() {}
}

// MARK: - Window

class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(category: SettingsCategory) {
        SettingsSelection.shared.category = category

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: hostingController)
        win.title = "设置"
        // A normal, opaque window with the native window background. The
        // transparent title bar keeps the traffic lights while letting the
        // sidebar material run to the top edge, exactly like System Settings.
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.titlebarSeparatorStyle = .none
        win.isOpaque = true
        win.backgroundColor = .windowBackgroundColor
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.isRestorable = false
        win.setContentSize(NSSize(width: 760, height: 560))
        win.minSize = NSSize(width: 700, height: 460)
        win.setFrameAutosaveName("MacEverythingSettings")
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

// MARK: - Settings root

struct SettingsView: View {
    @ObservedObject private var selection = SettingsSelection.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(minWidth: 700, minHeight: 460)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        ZStack {
            // Native sidebar material: the same translucent grey Finder and
            // System Settings use. No extra tint is layered on top.
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)

            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.leading, 8)
                    .padding(.bottom, 12)

                ForEach(SettingsCategory.allCases) { category in
                    SidebarRow(category: category,
                               isSelected: selection.category == category) {
                        selection.category = category
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            // Clear the traffic lights and keep a generous margin from the
            // window edge; the title belongs to the sidebar, not the page.
            .padding(.top, 46)
            .padding(.bottom, 12)
        }
        .frame(width: 212)
        .frame(maxHeight: .infinity)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            Text(selection.category.title)
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 6)

            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var page: some View {
        switch selection.category {
        case .general:
            GeneralSettingsView()
        case .search:
            SearchSettingsView()
        case .scope:
            SearchScopeSettingsView()
        case .advanced:
            AdvancedSettingsView()
        case .shortcuts:
            ShortcutSettingsView()
        case .about:
            AboutView()
        }
    }
}

// MARK: - Sidebar pieces

private struct SidebarRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SettingsCategoryIcon(category: category)
                Text(category.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Always the vivid system accent colour when selected — never a
    /// desaturated grey, which is what made the old sidebar look washed out.
    private var fillColor: Color {
        if isSelected { return Color.accentColor }
        if isHovered { return Color.primary.opacity(0.07) }
        return .clear
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// 20×20 rounded tile with a white glyph, matching the icon language of
/// Apple's System Settings sidebar.
struct SettingsCategoryIcon: View {
    let category: SettingsCategory

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(category.iconColor)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Label + description used by the rows inside a grouped `Form`.
struct SettingsRowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Shared settings helpers

/// Single source of truth for the launch-at-login switch so the onboarding and
/// the settings window always write to the same place.
enum LaunchAtLoginSetting {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            AppLogger.error("App", "Failed to toggle launch at login: \(error)")
            return false
        }
    }
}

/// Menu bar icon visibility, persisted under the same key the status bar item
/// reads at launch.
enum MenuBarIconSetting {
    static var isVisible: Bool {
        !UserDefaults.standard.bool(forKey: AppDelegate.statusIconHiddenKey)
    }

    static func setVisible(_ visible: Bool) {
        if visible {
            NotificationCenter.default.post(name: .showStatusBarIcon, object: nil)
        } else {
            NotificationCenter.default.post(name: .hideStatusBarIconPermanently, object: nil)
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @State private var launchAtLogin = LaunchAtLoginSetting.isEnabled
    @State private var showMenuBarIcon = MenuBarIconSetting.isVisible

    var body: some View {
        Form {
            Section("启动") {
                Toggle(isOn: $launchAtLogin) {
                    SettingsRowLabel(title: "登录时启动 MacEverything",
                                     detail: "登录系统后在后台自动启动，随时可用快捷键唤起。")
                }
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, enabled in
                    if !LaunchAtLoginSetting.set(enabled) {
                        launchAtLogin = LaunchAtLoginSetting.isEnabled
                    }
                }
            }

            Section("菜单栏") {
                Toggle(isOn: $showMenuBarIcon) {
                    SettingsRowLabel(title: "在菜单栏显示图标",
                                     detail: "隐藏图标后仍可使用全局快捷键唤起搜索窗口。")
                }
                .toggleStyle(.switch)
                .onChange(of: showMenuBarIcon) { _, shown in
                    MenuBarIconSetting.setVisible(shown)
                }
            }

            Section("更新") {
                LabeledContent {
                    Button("立即检查…") {
                        UpdateService.shared.checkManually()
                    }
                    .controlSize(.small)
                } label: {
                    Text("检查更新")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Search

struct SearchSettingsView: View {
    @ObservedObject private var options = SearchOptions.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $options.isRegex) {
                    SettingsRowLabel(title: "正则表达式",
                                     detail: "将搜索词按正则表达式解析，可使用 ^、$、.* 等语法。")
                }
                .toggleStyle(.switch)

                Toggle(isOn: $options.isCaseSensitive) {
                    SettingsRowLabel(title: "区分大小写",
                                     detail: "只返回大小写完全一致的结果。")
                }
                .toggleStyle(.switch)

                Toggle(isOn: $options.isWholeWord) {
                    SettingsRowLabel(title: "全词匹配",
                                     detail: "只匹配完整单词，不匹配单词中间的片段。")
                }
                .toggleStyle(.switch)

                Toggle(isOn: $options.isMatchFilename) {
                    SettingsRowLabel(title: "仅匹配文件名",
                                     detail: "只在文件名中查找，忽略路径中的匹配。")
                }
                .toggleStyle(.switch)
            } header: {
                Text("默认匹配方式")
            } footer: {
                Text("这些选项也可以在“搜索”菜单或搜索框右侧的标记中随时切换。")
            }
        }
        .formStyle(.grouped)
    }
}
