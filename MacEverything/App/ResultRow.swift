import SwiftUI
import AppKit

/// Display-only path shortening. Never affects queries, opening files,
/// revealing in Finder, or copying paths — those always use the real path.
enum PathDisplay {
    static func shorten(_ path: String) -> String {
        let home = NSHomeDirectory()
        let cloudDocs = home + "/Library/Mobile Documents/com~apple~CloudDocs"

        // iCloud Drive container → readable label
        if path == cloudDocs { return "iCloud云盘" }
        if path.hasPrefix(cloudDocs + "/") {
            return "iCloud云盘" + String(path.dropFirst(cloudDocs.count))
        }

        var display: String
        if path == home {
            display = "~"
        } else if path.hasPrefix(home + "/") {
            display = "~" + String(path.dropFirst(home.count))
        } else {
            display = path
        }

        // Remaining references to the cloud container keep the same readable name
        if display.contains("com~apple~CloudDocs") {
            display = display
                .replacingOccurrences(of: "/Library/Mobile Documents/com~apple~CloudDocs", with: "")
                .replacingOccurrences(of: "com~apple~CloudDocs", with: "iCloud云盘")
        }
        return display
    }
}

/// Shared icon cache to avoid repeated NSWorkspace.shared.icon(forFile:) calls.
/// - App bundles (type=5): cached by full path (each app has a unique icon)
/// - Regular files (type=1): cached by file extension (same ext → same icon)
/// - Directories/symlinks/other: cached by type (one icon per type)
final class FileIconCache {
    static let shared = FileIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 500
    }

    /// Dedicated artwork for symlinks ("快捷方式"). macOS draws a generic
    /// document glyph with a small arrow badge for these, which reads as an
    /// unfinished file icon in the result list.
    private static let shortcutIcon: NSImage? = NSImage(named: "ShortcutIcon")

    func icon(for item: FileItem) -> NSImage {
        // Symlinks are their own visual category; every one shares an icon.
        if item.type == 3, let shortcut = Self.shortcutIcon {
            return shortcut
        }

        // Detect app bundles by name suffix (handles both type=5 and legacy type=2)
        let isApp = item.name.hasSuffix(".app")

        let key: String
        if isApp {
            // App bundles — unique icon per app
            key = "app:" + item.path + "/" + item.name
        } else if item.type == 1 {
            // Regular file — same icon per extension
            let ext = (item.name as NSString).pathExtension.lowercased()
            key = "ext:" + (ext.isEmpty ? "__no_ext__" : ext)
        } else {
            // Dir, symlink, other — one icon per type
            key = "type:\(item.type)"
        }

        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) {
            return cached
        }

        let fullPath = item.path + "/" + item.name
        let nsImage = NSWorkspace.shared.icon(forFile: fullPath)
        nsImage.size = NSSize(width: 24, height: 24)
        cache.setObject(nsImage, forKey: nsKey)
        return nsImage
    }

    func icon(forPath path: String) -> NSImage {
        let ext = (path as NSString).pathExtension.lowercased()
        let key = "ext:" + (ext.isEmpty ? "__no_ext__" : ext) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let nsImage = NSWorkspace.shared.icon(forFile: path)
        nsImage.size = NSSize(width: 24, height: 24)
        cache.setObject(nsImage, forKey: key)
        return nsImage
    }
}

/// File actions shared by the result rows and the keyboard handler.
enum FileActions {
    static func open(_ item: FileItem) {
        let fullPath = item.path + "/" + item.name
        if item.type == 5 {
            let url = URL(fileURLWithPath: fullPath)
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            if !NSWorkspace.shared.open(URL(fileURLWithPath: fullPath)) {
                NSSound.beep()
            }
        }
    }

    static func reveal(_ item: FileItem) {
        let fullPath = item.path + "/" + item.name
        NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: "")
    }

    static func copyPath(_ item: FileItem) {
        let fullPath = item.path + "/" + item.name
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullPath, forType: .string)
    }

    /// Copy the file itself so it can be pasted in Finder.
    static func copyFile(_ item: FileItem) {
        let fullPath = item.path + "/" + item.name
        let url = URL(fileURLWithPath: fullPath)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }
}

struct ResultRow: View {
    let item: FileItem
    let hints: [HighlightHint]
    var isSelected: Bool = false
    var onSelect: () -> Void = {}
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 11) {
            fileIcon(for: item)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                let highlighted = highlightCrossMatches(
                    path: PathDisplay.shorten(item.path), name: item.name, hints: hints,
                    nameFont: .system(size: 15), nameColor: .primary,
                    pathFont: .custom("Menlo", size: 12), pathColor: .secondary)
                highlighted.nameText
                    .lineLimit(1)
                    .truncationMode(.tail)
                highlighted.pathText
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            Text(item.type == 1 && item.size > 0 ? formatSize(item.size) : "")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundColor(.secondary.opacity(0.85))
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.10)
                      : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("打开文件") { FileActions.open(item) }
            Button("打开所在的文件夹") { FileActions.reveal(item) }
            Divider()
            Button("复制文件") { FileActions.copyFile(item) }
            Button("复制路径") { FileActions.copyPath(item) }
        }
        .onDrag {
            let fullPath = item.path + "/" + item.name
            return NSItemProvider(object: NSURL(fileURLWithPath: fullPath))
        }
        .onTapGesture(count: 2) {
            if NSEvent.modifierFlags.contains(.command) {
                FileActions.reveal(item)
            } else {
                FileActions.open(item)
            }
        }
        .onTapGesture(count: 1) {
            onSelect()
            if NSEvent.modifierFlags.contains(.command) {
                FileActions.reveal(item)
            }
        }
        .accessibilityIdentifier("resultRow")
    }

    private func fileIcon(for item: FileItem) -> Image {
        Image(nsImage: FileIconCache.shared.icon(for: item))
    }

    private func formatSize(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(bytes) B" }
        return String(format: "%.1f %@", size, units[unitIndex])
    }
}
