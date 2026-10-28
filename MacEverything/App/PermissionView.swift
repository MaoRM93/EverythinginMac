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

/// One-time authorization gate.
///
/// Full Disk Access is the only permission this app asks for. Once it is
/// granted the scanner can read every directory, so macOS stops asking about
/// individual folders. The version marker makes users upgrading from 128 or
/// earlier go through the request once instead of silently inheriting the old
/// permission state.
enum PermissionGate {
    /// Bumped when every existing installation must re-authorize.
    static let onboardingVersion = 2

    private static let completedKey = "hasCompletedOnboarding"
    private static let versionKey = "onboardingVersion"
    private static let requestedKey = "permissionRequestedVersion"

    static var isComplete: Bool {
        let defaults = UserDefaults.standard
        // Also re-check the live TCC state: moving or re-signing the app can
        // revoke Full Disk Access while the stored flags still say "done",
        // which used to jump straight to search with no permission at all.
        return defaults.bool(forKey: completedKey)
            && defaults.integer(forKey: versionKey) >= onboardingVersion
            && PermissionHelper.hasFullDiskAccess
    }

    static var hasRequestedReauthorization: Bool {
        UserDefaults.standard.integer(forKey: requestedKey) >= onboardingVersion
    }

    /// Resume on the permission page when the app restarts after the user has
    /// already been sent to System Settings.
    static var shouldResumeAtPermission: Bool {
        hasRequestedReauthorization && PermissionHelper.hasFullDiskAccess
    }

    static func markPermissionRequested() {
        UserDefaults.standard.set(onboardingVersion, forKey: requestedKey)
    }

    static func markComplete() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: completedKey)
        defaults.set(onboardingVersion, forKey: versionKey)
    }

    /// Called once at launch, before SwiftUI reads the stored flags.
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: versionKey) < onboardingVersion,
           defaults.bool(forKey: completedKey) {
            // Old (128 and earlier) users must request Full Disk Access again
            // rather than inheriting the previous onboarding state.
            defaults.set(false, forKey: completedKey)
        }

        // Drop legacy permission flags that could bypass the gate.
        defaults.removeObject(forKey: "PermissionGranted")
        defaults.removeObject(forKey: "HasFullDiskAccess")
    }
}

struct PermissionView: View {
    @State private var hasFullDiskAccess: Bool = PermissionHelper.hasFullDiskAccess

    var body: some View {
        Group {
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
        .onAppear { checkAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkAccess()
        }
    }

    private func checkAccess() {
        hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
    }
}
