import SwiftUI

struct ExcludedPathPreset: Identifiable {
    let path: String
    let title: String
    let detail: String

    var id: String { path }
}

/// User-selected directories that must not be indexed and must not appear in
/// search results. Stored in UserDefaults; the C++ engine receives the same
/// list through MacSearchBridge.
final class ExcludedPathsStore {
    static let shared = ExcludedPathsStore()

    static let presets: [ExcludedPathPreset] = [
        ExcludedPathPreset(path: "/System", title: "系统核心",
                           detail: "macOS 运行所需的系统文件，通常不包含个人文件资料。"),
        ExcludedPathPreset(path: "/Library", title: "系统资源库",
                           detail: "系统与应用程序所共用的文件，可能包括插件、字体等内容以及微信等 App 的默认下载文件。"),
        ExcludedPathPreset(path: "/usr", title: "Unix 工具",
                           detail: "命令行工具与开发组件；/usr/local 可能包含用户安装的软件。"),
        ExcludedPathPreset(path: "/bin", title: "系统命令",
                           detail: "系统自带的基础命令。"),
        ExcludedPathPreset(path: "/sbin", title: "系统管理命令",
                           detail: "系统启动、网络与磁盘管理命令。"),
        ExcludedPathPreset(path: "/private/etc", title: "系统配置",
                           detail: "系统与服务的配置文件。"),
        ExcludedPathPreset(path: "/private/var", title: "系统运行数据",
                           detail: "系统运行期间产生的缓存、日志与状态数据。"),
        ExcludedPathPreset(path: "/private/tmp", title: "临时文件",
                           detail: "系统临时目录，重启后可能被自动清理。"),
        ExcludedPathPreset(path: "/opt", title: "可选软件包",
                           detail: "第三方可选软件；Apple Silicon 上的 Homebrew 通常位于 /opt/homebrew。"),
        ExcludedPathPreset(path: "/cores", title: "核心转储",
                           detail: "程序崩溃时生成的核心转储文件，通常为空。"),
    ]

    /// Directories that are pure macOS system data and would otherwise flood
    /// results with files the user can neither open nor act on. `/opt` is left
    /// unchecked on purpose: on Apple Silicon it hosts Homebrew packages.
    static let defaultPaths: [String] = [
        "/System", "/usr", "/bin", "/sbin",
        "/private/etc", "/private/var", "/private/tmp",
        "/cores",
    ]

    private static let key = "ExcludedSearchPaths"

    private init() {}

    var paths: [String] {
        if let stored = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            return stored
        }
        return Self.defaultPaths
    }

    func isEnabled(_ path: String) -> Bool {
        paths.contains(path)
    }

    func setEnabled(_ enabled: Bool, path: String) {
        var current = paths
        if enabled {
            guard !current.contains(path) else { return }
            current.append(path)
        } else {
            current.removeAll { $0 == path }
        }
        UserDefaults.standard.set(current, forKey: Self.key)
        NotificationCenter.default.post(name: .excludedPathsChanged, object: nil)
    }
}

extension Notification.Name {
    static let excludedPathsChanged = Notification.Name("excludedPathsChanged")
}

struct SearchScopeSettingsView: View {
    private let store = ExcludedPathsStore.shared

    var body: some View {
        Form {
            Section {
                Text("勾选后，这些目录不会参与索引，也不会出现在搜索结果中，修改立即生效。已存在于旧索引中的文件会立即从结果中隐藏；如需彻底清理请执行“重建索引”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(ExcludedPathsStore.presets) { preset in
                    Toggle(isOn: Binding(
                        get: { store.isEnabled(preset.path) },
                        set: { store.setEnabled($0, path: preset.path) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                Text(preset.title)
                                Text(preset.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }

                            Text(preset.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            } header: {
                Text("不检索的目录")
            }
        }
        .formStyle(.grouped)
    }
}
