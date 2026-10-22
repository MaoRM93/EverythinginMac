import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject private var searchOptions = SearchOptions.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var scrollViewID = 0
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainContent
            } else {
                WelcomeView {
                    hasCompletedOnboarding = true
                    viewModel.start()
                    isSearchFieldFocused = true
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if hasCompletedOnboarding {
                viewModel.start()
            }
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .rebuildIndex)) { _ in
            viewModel.rebuildIndex()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.onWindowFocusChanged(true)
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            viewModel.onWindowFocusChanged(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
            scrollViewID += 1
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Everything in Mac")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 26)

            searchBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)

            PermissionView()
                .padding(.horizontal, 20)

            resultsArea

            footer
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isSearchFieldFocused ? Color.accentColor : Color.secondary)
                .frame(width: 18, height: 26)
                .contentShape(Rectangle())
                .onTapGesture { isSearchFieldFocused = true }

            HighlightedSearchField(
                text: $viewModel.searchText,
                placeholder: "键入以搜索",
                ghostSuggestion: viewModel.ghostSuggestion,
                isFocused: $isSearchFieldFocused,
                onTab: {
                    if viewModel.ghostSuggestion != nil {
                        viewModel.acceptGhostSuggestion()
                        return true
                    }
                    return false
                }
            )
            .frame(height: 26)
            .onChange(of: viewModel.searchText) {
                viewModel.onSearchTextChanged()
            }

            SearchOptionBadges(options: searchOptions)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clearButton")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 43)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSearchFieldFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.09),
                    lineWidth: isSearchFieldFocused ? 1.5 : 1
                )
        )
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        if viewModel.searchText.isEmpty {
            emptyState
        } else if viewModel.isContentSearch {
            contentResultsArea
        } else if !viewModel.displayItems.isEmpty {
            fileResultsArea
        } else if viewModel.scanComplete {
            lightweightStatus("未找到相关项", showSpinner: false)
                .accessibilityIdentifier("noResultsLabel")
        } else {
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        Spacer(minLength: 0)
    }

    private var visibleResultCount: Int {
        viewModel.isContentSearch ? viewModel.contentResults.count : viewModel.displayItems.count
    }

    private var fileResultsArea: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.displayItems) { item in
                    ResultRow(item: item, hints: viewModel.highlightHints)
                        .padding(.horizontal, 8)
                        .id(item.id)
                }
                if viewModel.hasMoreResults {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在加载更多…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .onAppear {
                        viewModel.loadMore()
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .id(scrollViewID)
        .accessibilityIdentifier("fileResultsList")
    }

    /// Bottom bar. The version always sits in the bottom-right corner, and the
    /// indexing state is reported here instead of near the search field so that
    /// it never interferes with text input or the input method.
    private var footer: some View {
        VStack(spacing: 4) {
            if viewModel.isScanning || viewModel.isSyncing {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                    Text("正在更新数据，搜索结果可能不全或有延迟")
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                if viewModel.isMonitoring {
                    Circle()
                        .fill(Color.green.opacity(0.75))
                        .frame(width: 5, height: 5)
                    Text("实时")
                        .foregroundStyle(.tertiary)
                }
                Text("已收录 \(viewModel.totalRecords.formatted()) 项")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("indexedCount")
                Spacer()
                if viewModel.totalMatches > 0 {
                    Text("已显示 \(visibleResultCount) / \(viewModel.totalMatches) 项")
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("matchCount")
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(String(format: "%.1f 毫秒", viewModel.queryTimeMs))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                }
                Text("v\(AppInfo.version)")
                    .monospacedDigit()
                    .foregroundStyle(.quaternary)
                    .accessibilityIdentifier("versionLabel")
            }
            .font(.caption2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .accessibilityIdentifier("statusBar")
    }

    @ViewBuilder
    private var contentResultsArea: some View {
        if viewModel.contentKeyword.isEmpty {
            lightweightStatus("在 infile: 后输入关键词以搜索文件内容", showSpinner: false)
        } else if viewModel.contentResults.isEmpty {
            if viewModel.isContentIndexing {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    if let progress = viewModel.contentIndexProgress {
                        Text("正在建立内容索引… \(progress.indexed)/\(progress.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                lightweightStatus("未找到相关内容", showSpinner: false)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.contentResults) { item in
                        ContentResultRow(item: item, keyword: viewModel.contentKeyword)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 12)
            }
            .id(scrollViewID)
            .accessibilityIdentifier("contentResultsList")
        }
    }

    private func lightweightStatus(_ text: String, showSpinner: Bool) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                if showSpinner {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Welcome / onboarding

private struct WelcomeView: View {
    let onComplete: () -> Void

    @State private var step = 0

    private let contentWidth: CGFloat = 440

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // The whole content group is centred in the window; icons and text
            // are left-aligned inside the group, buttons stay centred.
            HStack {
                Spacer(minLength: 0)
                Group {
                    if step == 0 {
                        introduction
                    } else {
                        permissionExplanation
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("v\(AppInfo.version)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 40)
    }

    private var appIcon: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 84, height: 84)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            appIcon
                .padding(.bottom, 20)

            Text("欢迎使用 MacEverything")
                .font(.system(size: 26, weight: .semibold))

            Text("Everything in Mac")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 14) {
                welcomePoint("bolt", "为整个磁盘建立本地索引，搜索在毫秒级完成")
                welcomePoint("lock.shield", "索引与搜索全部在本机完成，不会上传任何文件或数据")
                welcomePoint("doc.text.magnifyingglass", "只有使用内容搜索时才会读取文件片段，且可随时关闭")
            }
            .padding(.top, 26)

            centeredButton {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { step = 1 }
                } label: {
                    Text("继续")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var permissionExplanation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 18)

            Text("需要你的授权")
                .font(.system(size: 24, weight: .semibold))

            Text("macOS 要求应用获得“完全磁盘访问权限”后，才能读取所有目录中的文件。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 13) {
                welcomePoint("eye.slash", "只读取文件名、路径、大小和修改时间")
                welcomePoint("doc.text", "内容索引只读取你指定类型的文本片段")
                welcomePoint("hand.raised", "权限可随时在“系统设置 › 隐私与安全性”中撤销")
                welcomePoint("externaldrive", "索引缓存保存在本机，可随时清理")
            }
            .padding(.top, 26)

            centeredButton {
                Button {
                    PermissionHelper.openFullDiskAccessSettings()
                    onComplete()
                } label: {
                    Text("请求权限")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func centeredButton<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
        .padding(.top, 38)
    }

    private func welcomePoint(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16, height: 17)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
