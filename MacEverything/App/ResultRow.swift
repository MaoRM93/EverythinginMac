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

    func icon(for item: FileItem) -> NSImage {
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

struct ResultRow: View {
    let item: FileItem
    let hints: [HighlightHint]
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            fileIcon(for: item)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                let highlighted = highlightCrossMatches(
                    path: PathDisplay.shorten(item.path), name: item.name, hints: hints,
                    nameFont: .system(size: 13), nameColor: .primary,
                    pathFont: .custom("Menlo", size: 11), pathColor: .secondary)
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
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(minHeight: 58)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("打开文件") { openFile(item) }
            Button("打开所在的文件夹") { revealInFinder(item) }
            Divider()
            Button("复制文件") { copyFile(item) }
            Button("复制路径") { copyPath(item) }
        }
        .onDrag {
            let fullPath = item.path + "/" + item.name
            return NSItemProvider(object: NSURL(fileURLWithPath: fullPath))
        }
        .onTapGesture(count: 2) {
            if NSEvent.modifierFlags.contains(.command) {
                revealInFinder(item)
            } else {
                openFile(item)
            }
        }
        .onTapGesture(count: 1) {
            if NSEvent.modifierFlags.contains(.command) {
                revealInFinder(item)
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

    private func openFile(_ item: FileItem) {
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

    private func revealInFinder(_ item: FileItem) {
        let fullPath = item.path + "/" + item.name
        NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: "")
    }

    private func copyPath(_ item: FileItem) {
        let fullPath = item.path + "/" + item.name
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullPath, forType: .string)
    }

    /// Copy the file itself so it can be pasted in Finder.
    private func copyFile(_ item: FileItem) {
        let fullPath = item.path + "/" + item.name
        let url = URL(fileURLWithPath: fullPath)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }
}
