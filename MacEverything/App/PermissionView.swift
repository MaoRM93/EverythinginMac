import SwiftUI

enum PermissionHelper {
    /// Full Disk Access cannot be requested through an API. The only reliable
    /// local probe is reading a TCC-protected directory.
    static var hasFullDiskAccess: Bool {
        FileManager.default.isReadableFile(atPath: NSHomeDirectory() + "/Library/Safari")
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PermissionView: View {
    @State private var hasFullDiskAccess: Bool = true

    var body: some View {
        Group {}.onAppear { checkAccess() }
            .task {
                while !hasFullDiskAccess {
                    try? await Task.sleep(for: .seconds(3))
                    checkAccess()
                }
            }

        if !hasFullDiskAccess {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("需要“完全磁盘访问权限”才能索引所有文件。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                Button("打开系统设置") {
                    PermissionHelper.openFullDiskAccessSettings()
                }
                .font(.caption)
                .buttonStyle(.link)
            }
            .padding(.bottom, 8)
        }
    }

    private func checkAccess() {
        hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
    }
}
