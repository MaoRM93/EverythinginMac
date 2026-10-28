import SwiftUI

struct AdvancedSettingsView: View {
    @State private var extensions: [String] = []
    @State private var newExtension: String = ""
    @State private var maxFileSizeMB: Double = 1.0
    @State private var indexedCount: UInt32 = 0

    @State private var initialExtensions: [String] = []
    @State private var initialMaxFileSizeMB: Double = 1.0

    private let bridge = MacSearchBridge.shared()

    private var isDirty: Bool {
        extensions != initialExtensions || maxFileSizeMB != initialMaxFileSizeMB
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("已索引文件") {
                    Text("\(indexedCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                LabeledContent {
                    HStack(spacing: 10) {
                        // No `step:` here: macOS 26 draws a tick line under a
                        // stepped slider, which looked like a stray grey rule.
                        Slider(value: $maxFileSizeMB, in: 0.1...10.0)
                            .frame(width: 150)
                        Text(String(format: "%.1f MB", maxFileSizeMB))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                } label: {
                    SettingsRowLabel(title: "最大文件大小",
                                     detail: "超过该大小的文件不参与内容索引。")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("参与内容索引的文件类型")

                    FlowLayout(spacing: 6) {
                        ForEach(extensions, id: \.self) { ext in
                            extensionChip(ext)
                        }
                    }

                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        TextField("添加扩展名", text: $newExtension)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .onSubmit { addExtension() }

                        Button("添加") { addExtension() }
                            .controlSize(.small)
                            .disabled(newExtension.isEmpty)
                    }
                }
                .padding(.vertical, 2)

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button("应用更改") { applySettings() }
                        .controlSize(.small)
                        .disabled(!isDirty)
                }
            } header: {
                Text("内容索引")
            } footer: {
                Text("内容索引用于 infile: 内容搜索，只读取指定类型的文本文件片段。")
            }

            Section {
                ForEach(MCPClient.allCases, id: \.self) { client in
                    Toggle(client.displayName, isOn: Binding(
                        get: { MCPConfigManager.isEnabled(for: client) },
                        set: { MCPConfigManager.setEnabled($0, for: client) }
                    ))
                    .toggleStyle(.switch)
                }
            } header: {
                Text("MCP 集成")
            } footer: {
                Text("开启后会将本程序的搜索能力接入对应的 AI 客户端。")
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    private func extensionChip(_ ext: String) -> some View {
        HStack(spacing: 3) {
            Text(".\(ext)")
                .font(.system(size: 11.5))
            Button {
                removeExtension(ext)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private func loadSettings() {
        indexedCount = bridge.contentIndexedFileCount()
        extensions = (bridge.contentGetExtensions() as? [String]) ?? []
        maxFileSizeMB = Double(bridge.contentGetMaxFileSize()) / (1024.0 * 1024.0)

        initialExtensions = extensions
        initialMaxFileSizeMB = maxFileSizeMB
    }

    private func addExtension() {
        let ext = newExtension.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: ".", with: "")
        guard !ext.isEmpty, !extensions.contains(ext) else { return }
        extensions.append(ext)
        newExtension = ""
    }

    private func removeExtension(_ ext: String) {
        extensions.removeAll { $0 == ext }
    }

    private func applySettings() {
        let dirty = extensions != initialExtensions || maxFileSizeMB != initialMaxFileSizeMB
        guard dirty else { return }
        // The slider is continuous now, so round to the displayed 0.1 MB.
        let sizeMB = (maxFileSizeMB * 10).rounded() / 10
        bridge.setContentMaxFileSize(UInt64(sizeMB * 1024 * 1024))
        bridge.setContentExtensions(extensions)
        DispatchQueue.global().async {
            bridge.rebuildContentIndex()
        }
        initialExtensions = extensions
        initialMaxFileSizeMB = maxFileSizeMB
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, point) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
