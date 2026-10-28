import SwiftUI
import AppKit
import Combine
import ObjectiveC

// MARK: - Glass theme

enum GlassTheme {
    /// Invisible margin outside the glass shape so its shadow can render
    /// without being clipped by the window bounds.
    ///
    /// A 10pt blur with a 4pt downward offset fades out roughly 19pt beyond the
    /// card edge. A 16pt margin cut that fade with a hard straight line at the
    /// window bottom, so the margin now clears the whole shadow tail.
    static let windowPadding: CGFloat = 26

    static let contentWidth: CGFloat = 720

    /// The search field has no shape of its own: the window itself is the
    /// field, exactly like Spotlight. The same radius is used when the panel
    /// opens, so the rounded corners never break apart.
    static let fieldHeight: CGFloat = 64
    static let searchCorner: CGFloat = 28
    static let collapsedHeight: CGFloat = fieldHeight
    static let collapsedCorner: CGFloat = searchCorner
    static let expandedCorner: CGFloat = searchCorner

    static let onboardingSize = CGSize(width: 720, height: 580)

    /// Height of the transparent title bar that hosts the traffic lights.
    /// Only the onboarding flow shows them, but the window still has to cover
    /// that strip so SwiftUI's safe area does not clip the card.
    static let titleBarHeight: CGFloat = 28

    static func maxExpandedHeight() -> CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 900
        return min(540, max(320, visible * 0.60))
    }
}

/// Backing material. macOS 26+ uses the native Liquid Glass effect; older
/// systems get a visually compatible vibrancy surface.
///
/// The glass is layered rather than tuned with a single opacity:
/// 1. the system material (blur + environmental blending),
/// 2. a neutral veil that limits how much of the desktop bleeds through, so a
///    saturated wallpaper can no longer fight the text,
/// 3. the content, which always sits above the veil.
struct GlassSurface<S: InsettableShape>: View {
    let shape: S

    /// The floating search panel only needs the faintest edge — Spotlight has
    /// no visible frame around the field; the onboarding card keeps a stronger
    /// outline so it reads as a window.
    var subtleEdge: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    /// White keeps light mode airy; black keeps dark mode from washing out.
    /// Light mode needs a noticeably stronger veil: black text on a pale
    /// wallpaper has almost no contrast once the blur is applied, whereas
    /// white text on a dark blur already reads well.
    private var veil: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.36)
            : Color.white.opacity(0.52)
    }

    /// Hairline edge. Without it the white glass card dissolves into a light
    /// desktop and the window appears to have no boundary at all.
    private var borderColor: Color {
        if subtleEdge {
            return colorScheme == .dark
                ? Color.white.opacity(0.10)
                : Color.black.opacity(0.09)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.22)
    }

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: shape)
            } else {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.40))
            }
            shape.fill(veil)
            shape.strokeBorder(borderColor, lineWidth: 1)
            // Top specular highlight so the surface still reads as raised
            // glass instead of a flat translucent rectangle.
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.20 : 0.50),
                             Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 1
            )
        }
        .clipShape(shape)
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

/// Native macOS spinner (the system “菊花”) so indexing and incremental sync
/// use the same animation as the rest of AppKit instead of a custom symbol.
struct MacSpinner: NSViewRepresentable {
    var controlSize: NSControl.ControlSize = .small

    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = controlSize
        indicator.isIndeterminate = true
        indicator.isDisplayedWhenStopped = false
        indicator.startAnimation(nil)
        return indicator
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {
        nsView.controlSize = controlSize
        nsView.startAnimation(nil)
    }
}

/// Lets the frameless search panel be moved by dragging its glass surface.
/// macOS 15 ships a dedicated gesture for this; older systems rely on the
/// window's `isMovableByWindowBackground` instead.
extension View {
    @ViewBuilder
    func draggableWindowSurface() -> some View {
        if #available(macOS 15.0, *) {
            gesture(WindowDragGesture())
        } else {
            self
        }
    }
}

/// Rounded card outline whose height can be animated on its own. Used as a
/// clip rather than as a layout height: the card is laid out at its final size
/// in one frame (so the window never has to chase it), while this shape decides
/// how much of it is on screen.
struct RevealShape: Shape {
    var height: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let visible = min(max(height, 0), rect.height)
        return Path(roundedRect: CGRect(x: rect.minX, y: rect.minY,
                                        width: rect.width, height: visible),
                    cornerRadius: radius, style: .continuous)
    }
}

// MARK: - Window state

enum MainWindowMode {
    case onboarding
    case collapsed
    case expanded
}

final class MainWindowState: ObservableObject {
    static let shared = MainWindowState()

    @Published var mode: MainWindowMode = PermissionGate.isComplete ? .collapsed : .onboarding

    /// Height of the expanded panel. ContentView sizes it to the result count
    /// so a handful of hits does not leave a tall empty block below them.
    @Published var expandedContentHeight: CGFloat = GlassTheme.maxExpandedHeight()

    private init() {}

    func contentSize(for mode: MainWindowMode) -> CGSize {
        switch mode {
        case .onboarding:
            return GlassTheme.onboardingSize
        case .collapsed:
            return CGSize(width: GlassTheme.contentWidth, height: GlassTheme.collapsedHeight)
        case .expanded:
            return CGSize(width: GlassTheme.contentWidth, height: expandedContentHeight)
        }
    }

    /// The window frame always equals the card plus the transparent shadow
    /// margin. The onboarding card draws its own traffic lights, so no extra
    /// title-bar strip is reserved.
    func windowSize(for mode: MainWindowMode) -> CGSize {
        let content = contentSize(for: mode)
        return CGSize(width: content.width + GlassTheme.windowPadding * 2,
                      height: content.height + GlassTheme.windowPadding * 2)
    }
}

/// A `.borderless` window answers `false` to `canBecomeKey`, so it can never
/// take keyboard focus and the search field would be unclickable. Overriding
/// that single getter on the window's own class keeps the class identity (and
/// therefore SwiftUI's KVO registration) untouched — swapping the class
/// outright crashed NSHostingView with a dangling key-path observer.
private enum KeyWindowSupport {
    private static var patchedClasses: Set<ObjectIdentifier> = []

    static func allowKeyStatus(for window: NSWindow) {
        guard let cls: AnyClass = object_getClass(window) else { return }
        let identifier = ObjectIdentifier(cls)
        guard !patchedClasses.contains(identifier) else { return }
        patchedClasses.insert(identifier)

        let selector = NSSelectorFromString("canBecomeKeyWindow")
        let block = { (_: NSWindow) -> Bool in true } as @convention(block) (NSWindow) -> Bool
        let implementation = imp_implementationWithBlock(block)
        class_replaceMethod(cls, selector, implementation, "B@:")
    }
}

/// Configures the main SwiftUI window once AppKit has created it and animates
/// its size between the capsule and expanded panel states.
final class MainWindowController {
    static let shared = MainWindowController()

    private weak var window: NSWindow?
    private var modeSink: AnyCancellable?
    private var heightSink: AnyCancellable?
    /// Last frame size this controller asked for, used to drop redundant
    /// resize requests that would otherwise restart a running animation.
    private var lastAppliedSize: NSSize = .zero
    /// Pending instant shrink, cancelled when a new size arrives meanwhile.
    private var pendingShrink: DispatchWorkItem?

    private init() {}

    func attach(_ window: NSWindow) {
        if self.window === window { return }
        self.window = window
        lastAppliedSize = .zero

        modeSink = MainWindowState.shared.$mode
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.apply(mode)
            }

        // Results can arrive one by one; resize to fit them while the panel is
        // already open so it never keeps a fixed tall empty area.
        heightSink = MainWindowState.shared.$expandedContentHeight
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard MainWindowState.shared.mode == .expanded else { return }
                self?.apply(.expanded)
            }

        // `attach` is called from `updateNSView` / `viewDidMoveToWindow`, i.e.
        // from inside an AppKit layout pass. Swapping the style mask rebuilds
        // the window's content view; doing that while AppKit is still walking
        // the old view tree leaves it laying out freed views and crashed with
        // EXC_BAD_ACCESS in -[NSView _layoutSubtreeWithOldSize:]. Configure and
        // size the window on the next run loop turn instead, once the current
        // layout transaction has been committed.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.configure(window)
            self.apply(MainWindowState.shared.mode)
        }
    }

    private func configure(_ window: NSWindow) {
        window.title = "MacEverything"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior.insert(.fullScreenNone)
        window.styleMask = [.titled, .fullSizeContentView, .closable, .miniaturizable]
    }

    /// The onboarding flow is a normal titled window and keeps its native
    /// close/minimise buttons; the chromeless search capsule is frameless.
    /// Using `.titled` at all forces AppKit to reserve a 28–32pt title-bar
    /// strip, which inflates the compact capsule and leaves empty grey space
    /// around it — so the search window must drop `.titled` entirely.
    private func setTrafficLightsVisible(_ visible: Bool, applying mask: NSWindow.StyleMask) {
        guard let window else { return }
        if !mask.contains(.titled) {
            KeyWindowSupport.allowKeyStatus(for: window)
        }
        window.standardWindowButton(.closeButton)?.isHidden = !visible
        window.standardWindowButton(.miniaturizeButton)?.isHidden = !visible
        window.standardWindowButton(.zoomButton)?.isHidden = !visible
        // Re-assigning an identical style mask still makes AppKit re-tile the
        // frame, which fights the height animation on every result batch.
        if window.styleMask != mask {
            window.styleMask = mask
        }
        // Changing the style mask recreates the window frame and can restore
        // AppKit's default shadow, which showed up as a rim around the panel.
        window.hasShadow = false

        // Safety net: if the getter override did not take effect the window
        // could never become key and typing would silently stop working, so
        // fall back to a normal titled window instead.
        if !window.canBecomeKey {
            window.styleMask = [.titled, .fullSizeContentView, .closable, .miniaturizable]
        }
    }

    /// Search capsule: frameless, no title bar, no resizing chrome, opaque
    /// content drawn edge-to-edge. Onboarding: normal titled window so the
    /// card can be moved and zoomed, with AppKit's traffic lights hidden —
    /// the card draws its own so they keep a comfortable inset.
    private func styleMask(for mode: MainWindowMode) -> NSWindow.StyleMask {
        switch mode {
        case .onboarding:
            return [.titled, .fullSizeContentView, .closable, .miniaturizable]
        case .collapsed, .expanded:
            return [.borderless]
        }
    }

    func apply(_ mode: MainWindowMode) {
        guard let window else { return }

        let mask = styleMask(for: mode)
        // The onboarding card draws its own traffic lights so they can keep a
        // real margin inside the rounded card; the system buttons are hidden
        // in every mode.
        setTrafficLightsVisible(false, applying: mask)

        let content = MainWindowState.shared.contentSize(for: mode)
        let size = NSSize(width: content.width + GlassTheme.windowPadding * 2,
                          height: content.height + GlassTheme.windowPadding * 2)

        guard size != lastAppliedSize else { return }
        lastAppliedSize = size

        // The window is invisible around the glass card, so its frame must
        // never be animated: any AppKit frame animation runs on its own
        // display-link clock and fights SwiftUI's height animation, which is
        // what produced the visible twitch. Growing is applied at once (it
        // only reveals more of the card); shrinking is deferred until the
        // card's collapse animation has finished so nothing gets clipped.
        pendingShrink?.cancel()
        pendingShrink = nil

        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        if size.height >= window.frame.height {
            window.setFrame(targetFrame(size: size, top: window.frame.maxY, visible: visible),
                            display: true)
        } else {
            let item = DispatchWorkItem { [weak self] in
                guard let window = self?.window else { return }
                window.setFrame(self?.targetFrame(size: size,
                                                 top: window.frame.maxY,
                                                 visible: visible) ?? window.frame,
                                display: true)
            }
            pendingShrink = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19, execute: item)
        }
    }

    /// Builds a frame with the requested size while keeping the existing top
    /// edge and horizontal centre — the one invariant that must never move.
    private func targetFrame(size: NSSize, top: CGFloat, visible: NSRect) -> NSRect {
        var frame = NSRect.zero
        frame.size = size
        frame.origin.x = min(max((window?.frame.midX ?? visible.midX) - size.width / 2,
                                 visible.minX + 8),
                             visible.maxX - size.width - 8)
        frame.origin.y = max(top - size.height, visible.minY + 8)
        return frame
    }
}

/// Zero-sized bridge that hands the SwiftUI window to MainWindowController.
struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        AccessorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            MainWindowController.shared.attach(window)
        }
    }

    private final class AccessorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                MainWindowController.shared.attach(window)
            }
        }
    }
}

/// Shared keyboard selection for the result list. The search text view stays
/// first responder (so typing and IME keep working) while this drives the
/// visual selection and key navigation.
final class SearchSelectionState: ObservableObject {
    static let shared = SearchSelectionState()

    @Published var index: Int?
    @Published var isListFocused = false

    private init() {}
}

// MARK: - Main content

struct ContentView: View {
    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject private var searchOptions = SearchOptions.shared
    @ObservedObject private var windowState = MainWindowState.shared
    @ObservedObject private var selection = SearchSelectionState.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingVersion") private var onboardingVersion = 0
    @State private var searchSettled = false
    @State private var hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
    @State private var scrollViewID = 0
    /// Height the card is actually laid out at. It switches instantly: any
    /// animation of the layout makes the window resize and the card grow on
    /// two different clocks, which is what showed up as the panel twitching.
    @State private var cardLayoutHeight: CGFloat = GlassTheme.collapsedHeight
    /// The part of the card that is visible. This is animated purely as a
    /// clipping effect, so it never takes part in layout and can never move the
    /// card's top edge or the window frame.
    @State private var revealHeight: CGFloat = GlassTheme.collapsedHeight
    /// Keeps the results mounted until the collapse reveal has finished.
    @State private var panelPresent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFieldFocused: Bool

    /// Soft drop shadow that separates the floating panel from the desktop.
    /// The window itself stays shadowless, so this is the only shadow the
    /// glass card gets — kept within `windowPadding` so it is never clipped.
    private var glassShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.55) : Color.black.opacity(0.22)
    }

    private var onboardingDone: Bool {
        hasCompletedOnboarding
            && onboardingVersion >= PermissionGate.onboardingVersion
            && hasFullDiskAccess
    }

    private var isExpanded: Bool {
        onboardingDone && !viewModel.searchText.isEmpty && searchSettled
    }

    private var panelAnimation: Animation {
        // Only the clip that reveals the panel is animated, never the layout.
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.18)
    }

    /// Panel height sized to what is actually shown. The field and its top
    /// inset are constant, so the search box stays put while the panel below
    /// grows just enough for the current results.
    private var expandedContentHeight: CGFloat {
        let footer: CGFloat = (viewModel.isScanning || viewModel.isSyncing) ? 44 : 28
        let results: CGFloat
        if viewModel.isContentSearch {
            results = 340
        } else if viewModel.displayItems.isEmpty {
            // Spinner or “未找到相关项”.
            results = 92
        } else {
            let rows = min(viewModel.displayItems.count, 7)
            results = CGFloat(rows) * 62 + 14
        }
        let total = GlassTheme.fieldHeight + 1 + results + footer + 8
        return min(total, GlassTheme.maxExpandedHeight())
    }

    var body: some View {
        Group {
            if onboardingDone {
                topAlignedCard { searchSurface }
            } else {
                topAlignedCard {
                    WelcomeView(onComplete: completeOnboarding)
                        .frame(width: GlassTheme.onboardingSize.width,
                               height: GlassTheme.onboardingSize.height)
                        .background(
                            GlassSurface(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: glassShadow, radius: 10, y: 4)
                        // The traffic lights are drawn inside the card instead of
                        // floating on the window corner, so they keep a comfortable
                        // margin from the edge at every window size.
                        .overlay(alignment: .topLeading) {
                            TrafficLights()
                                .padding(.top, 18)
                                .padding(.leading, 18)
                        }
                }
            }
        }
        .background(MainWindowAccessor().frame(width: 0, height: 0))
        .onAppear {
            hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
            if onboardingDone {
                windowState.mode = .collapsed
                viewModel.start()
            } else {
                windowState.mode = .onboarding
            }
            refocusSearchField()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refocusSearchField()
        }
        .onReceive(NotificationCenter.default.publisher(for: .excludedPathsChanged)) { _ in
            viewModel.reloadExcludedPaths()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .rebuildIndex)) { _ in
            viewModel.rebuildIndex()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
            if onboardingDone {
                viewModel.start()
            }
            viewModel.onWindowFocusChanged(true)
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            viewModel.onWindowFocusChanged(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
            scrollViewID += 1
        }
        .onChange(of: isExpanded) { _, expanded in
            guard onboardingDone else { return }
            applyExpansion(expanded)
        }
        .onChange(of: expandedContentHeight) { _, height in
            guard isExpanded else { return }
            cardLayoutHeight = height
            withAnimation(panelAnimation) { revealHeight = height }
            windowState.expandedContentHeight = height
        }
        .task(id: viewModel.searchText) {
            guard !viewModel.searchText.isEmpty else {
                searchSettled = false
                return
            }
            // Once the panel is open, keep it open while the user keeps typing;
            // only the first expansion is debounced.
            guard !searchSettled else { return }
            try? await Task.sleep(for: .milliseconds(240))
            if !Task.isCancelled {
                searchSettled = true
            }
        }
    }

    /// Explicit top anchor for the card.
    ///
    /// The `Spacer` makes the stack take the full height it is offered and the
    /// `.top` alignment then pins the card to the window's top edge, so a
    /// height change below the field can never re-centre the card.
    /// `ignoresSafeArea` stays outermost (the window itself is borderless in
    /// search mode, so there is no title-bar inset to fight).
    private func topAlignedCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let card = content()
        return VStack(spacing: 0) {
            card
                .padding(GlassTheme.windowPadding)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    /// The layout switches in a single frame; the only thing that animates is
    /// the clip that reveals the panel. Animating the layout as well made the
    /// panel and the window chase each other, producing the visible twitch.
    private func applyExpansion(_ expanded: Bool) {
        if expanded {
            panelPresent = true
            cardLayoutHeight = expandedContentHeight
            withAnimation(panelAnimation) { revealHeight = expandedContentHeight }
        } else {
            withAnimation(panelAnimation) { revealHeight = GlassTheme.collapsedHeight }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
                guard MainWindowState.shared.mode == .collapsed else { return }
                panelPresent = false
                cardLayoutHeight = GlassTheme.collapsedHeight
            }
        }
        // The height has to be current before the mode change resizes the
        // window, otherwise it would briefly open at the old size.
        windowState.expandedContentHeight = expandedContentHeight
        windowState.mode = expanded ? .expanded : .collapsed
    }

    private func completeOnboarding() {
        hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
        guard hasFullDiskAccess else { return }
        PermissionGate.markComplete()
        hasCompletedOnboarding = true
        onboardingVersion = PermissionGate.onboardingVersion
        windowState.mode = .collapsed
        viewModel.start()
        refocusSearchField()
    }

    /// Force the search field to become first responder even if the focus
    /// state was already `true` (SwiftUI would otherwise skip `updateNSView`).
    private func refocusSearchField() {
        isSearchFieldFocused = false
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }

    // MARK: - Search surface
    //
    // Copied from Spotlight: the window *is* the search field. There is no
    // inner pill, no second outline and no inset frame — collapsed it is a
    // single glass capsule, expanded the same surface grows downward, keeps
    // the field in the same spot and separates the results with a hairline.

    private var searchSurface: some View {
        VStack(spacing: 0) {
            searchFieldContent
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: GlassTheme.fieldHeight)

            if panelPresent {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 1)

                expandedPanel
            }
        }
        .frame(width: GlassTheme.contentWidth,
               height: cardLayoutHeight,
               alignment: .top)
        // Belt and braces: the layout height must never be interpolated, even
        // if a caller happens to be inside an animation transaction. Only the
        // reveal clip is allowed to animate.
        .animation(nil, value: cardLayoutHeight)
        .background(
            GlassSurface(shape: RoundedRectangle(cornerRadius: GlassTheme.searchCorner,
                                                   style: .continuous),
                         subtleEdge: true)
        )
        // The clip — not the layout — carries the open/close animation, so the
        // card's top edge and the window frame stay put for every frame.
        .clipShape(RevealShape(height: revealHeight, radius: GlassTheme.searchCorner))
        .shadow(color: glassShadow, radius: 10, y: 4)
    }

    private var searchFieldContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(isSearchFieldFocused ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
                .onTapGesture { isSearchFieldFocused = true }

            HighlightedSearchField(
                text: $viewModel.searchText,
                placeholder: "搜索文件与文件夹",
                ghostSuggestion: viewModel.ghostSuggestion,
                isFocused: $isSearchFieldFocused,
                isListFocused: selection.isListFocused,
                onTab: { shift in handleTab(shift: shift) },
                onDownArrow: { focusFirstResult() },
                onListKey: { handleListKey($0) }
            )
            .frame(height: 24)
            .onChange(of: viewModel.searchText) {
                viewModel.onSearchTextChanged()
                if selection.isListFocused {
                    selection.isListFocused = false
                    selection.index = nil
                }
            }

            if !viewModel.searchText.isEmpty && !searchSettled {
                ProgressView()
                    .controlSize(.mini)
            }

            SearchOptionBadges(options: searchOptions)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    selection.isListFocused = false
                    selection.index = nil
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clearButton")
            }
        }
        .draggableWindowSurface()
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            resultsArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var resultsArea: some View {
        if viewModel.isContentSearch {
            contentResultsArea
        } else if !viewModel.displayItems.isEmpty {
            fileResultsArea
        } else if viewModel.scanComplete {
            lightweightStatus("未找到相关项", showSpinner: false)
                .accessibilityIdentifier("noResultsLabel")
        } else {
            lightweightStatus("正在搜索…", showSpinner: true)
        }
    }

    private var fileResultsArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.displayItems.enumerated()), id: \.element.id) { index, item in
                        ResultRow(
                            item: item,
                            hints: viewModel.highlightHints,
                            isSelected: selection.isListFocused && selection.index == index,
                            onSelect: {
                                selection.isListFocused = true
                                selection.index = index
                            }
                        )
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
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .id(scrollViewID)
            .accessibilityIdentifier("fileResultsList")
            .onChange(of: selection.index) { _, newValue in
                guard let index = newValue,
                      index >= 0,
                      index < viewModel.displayItems.count else { return }
                let target = viewModel.displayItems[index].id
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            .onChange(of: viewModel.displayItems.count) { _, count in
                if let index = selection.index, index >= count {
                    selection.index = count > 0 ? count - 1 : nil
                }
                if count == 0 {
                    selection.index = nil
                    selection.isListFocused = false
                }
            }
        }
    }

    @ViewBuilder
    private var contentResultsArea: some View {
        if viewModel.contentKeyword.isEmpty {
            lightweightStatus("在 infile: 后输入关键词以搜索文件内容", showSpinner: false)
        } else if viewModel.contentResults.isEmpty {
            if viewModel.isContentIndexing {
                VStack(spacing: 6) {
                    MacSpinner(controlSize: .regular)
                        .frame(width: 16, height: 16)
                    if let progress = viewModel.contentIndexProgress {
                        Text("正在建立内容索引… \(progress.indexed)/\(progress.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .padding(.horizontal, 6)
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
                    MacSpinner()
                        .frame(width: 14, height: 14)
                }
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleResultCount: Int {
        viewModel.isContentSearch ? viewModel.contentResults.count : viewModel.displayItems.count
    }

    /// Bottom status line lives inside the expanded panel only.
    private var footer: some View {
        VStack(spacing: 6) {
            if viewModel.isScanning || viewModel.isSyncing {
                HStack(spacing: 5) {
                    MacSpinner()
                        .frame(width: 12, height: 12)
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
                }
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityIdentifier("statusBar")
    }

    // MARK: - Keyboard navigation

    private func handleTab(shift: Bool) -> Bool {
        guard !shift else { return false }
        return focusFirstResult()
    }

    @discardableResult
    private func focusFirstResult() -> Bool {
        guard !viewModel.isContentSearch, !viewModel.displayItems.isEmpty else { return false }
        selection.isListFocused = true
        selection.index = 0
        return true
    }

    private func handleListKey(_ event: NSEvent) -> Bool {
        guard selection.isListFocused, !viewModel.isContentSearch else { return false }
        let count = viewModel.displayItems.count
        guard count > 0 else { return false }

        switch event.keyCode {
        case 125: // ↓
            selection.index = min((selection.index ?? -1) + 1, count - 1)
            return true

        case 126: // ↑
            if (selection.index ?? 0) <= 0 {
                selection.isListFocused = false
                selection.index = nil
                isSearchFieldFocused = true
            } else {
                selection.index = (selection.index ?? 0) - 1
            }
            return true

        case 36, 76: // Return / keypad Enter
            if let index = selection.index, index < count {
                FileActions.open(viewModel.displayItems[index])
            }
            return true

        case 48: // Tab
            selection.isListFocused = false
            selection.index = nil
            isSearchFieldFocused = true
            return true

        default:
            return false
        }
    }
}

// MARK: - Welcome / onboarding

private struct WelcomeView: View {
    let onComplete: () -> Void

    /// When the app restarts after the permission is granted, resume directly on
    /// the permission step so the user sees the granted state instead of the
    /// welcome page again.
    @State private var step = PermissionGate.shouldResumeAtPermission ? 1 : 0
    @State private var hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
    @State private var permissionRequested = PermissionGate.hasRequestedReauthorization

    @State private var launchAtLogin = LaunchAtLoginSetting.isEnabled
    @State private var showMenuBarIcon = MenuBarIconSetting.isVisible
    @State private var isRecordingShortcut = false
    @State private var shortcutKeyCode: UInt32 = DefaultHotkey.keyCode
    @State private var shortcutModifiers: UInt32 = DefaultHotkey.modifiers
    @State private var shortcutText = ""

    private let contentWidth: CGFloat = 440

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Group {
                switch step {
                case 0:
                    introduction
                case 1:
                    permissionExplanation
                case 2:
                    startupPage
                case 3:
                    shortcutPage
                default:
                    indexPage
                }
            }
            .frame(width: step >= 2 ? 600 : contentWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: step >= 2 ? .top : .center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .onAppear {
            loadShortcut()
            hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
            permissionRequested = PermissionGate.hasRequestedReauthorization
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
            permissionRequested = PermissionGate.hasRequestedReauthorization
        }
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
                welcomePoint("slider.horizontal.3", "快捷键、菜单栏图标与索引范围都可以按你的习惯自定义")
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
            Image(systemName: showsGranted ? "checkmark.shield.fill" : "checkmark.shield")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 18)

            Text(showsGranted ? "已获得授权" : "需要你的授权")
                .font(.system(size: 24, weight: .semibold))

            Text(showsGranted
                 ? "已成功授予“完全磁盘访问权限”，可以继续完成初始设置。"
                 : "macOS 要求应用获得“完全磁盘访问权限”后，才能读取所有目录中的文件。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            if showsGranted {
                VStack(alignment: .leading, spacing: 13) {
                    welcomePoint("eye.slash", "只读取文件名、路径、大小和修改时间")
                    welcomePoint("doc.text", "内容索引只读取你指定类型的文本片段")
                    welcomePoint("hand.raised", "权限可随时在“系统设置 › 隐私与安全性”中撤销")
                }
                .padding(.top, 26)
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    welcomePoint("externaldrive", "只需授权一次，之后不会再逐项询问文件夹访问权限")
                    welcomePoint("lock.shield", "所有索引结果只保存在本机，不会上传任何文件、目录或数据")
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 16, height: 17)
                        Text("授予权限时 macOS 会退出并重新打开 MacEverything，重启后会自动回到本页。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 26)
            }

            centeredButton {
                if showsGranted {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { step = 2 }
                    } label: {
                        Text("下一步")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        PermissionGate.markPermissionRequested()
                        hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
                        permissionRequested = true
                        if !hasFullDiskAccess {
                            PermissionHelper.openFullDiskAccessSettings()
                        }
                    } label: {
                        Text("好")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private var showsGranted: Bool {
        hasFullDiskAccess && permissionRequested
    }

    // MARK: - Onboarding pages

    private var startupPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            pageHeading("启动与显示",
                        "这些选项之后都可以在“设置”（⌘,）中随时修改。")

            Form {
                Section("启动") {
                    Toggle("登录时启动 MacEverything", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            if !LaunchAtLoginSetting.set(enabled) {
                                launchAtLogin = LaunchAtLoginSetting.isEnabled
                            }
                        }

                    Toggle("在菜单栏显示图标", isOn: $showMenuBarIcon)
                        .onChange(of: showMenuBarIcon) { _, shown in
                            MenuBarIconSetting.setVisible(shown)
                        }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)

            pageNavigation(nextTitle: "下一步") { advance(to: 3) }
        }
        .padding(.top, 26)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var shortcutPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            pageHeading("快捷启动",
                        "在任意应用中按下该快捷键，即可唤起搜索窗口。")

            Form {
                Section("全局快捷键") {
                    HStack {
                        Text("当前快捷键")
                        Spacer()
                        Button {
                            isRecordingShortcut.toggle()
                        } label: {
                            Text(isRecordingShortcut ? "请按下组合键…" : shortcutText)
                                .fontWeight(.medium)
                                .foregroundStyle(isRecordingShortcut ? Color.accentColor : Color.primary)
                                .frame(minWidth: 150)
                        }
                        .buttonStyle(.bordered)
                    }

                    if isRecordingShortcut {
                        ShortcutRecorderView(
                            onKeyCombo: { newKeyCode, newModifiers in
                                shortcutKeyCode = newKeyCode
                                shortcutModifiers = newModifiers
                                shortcutText = describeShortcut(keyCode: newKeyCode, modifiers: newModifiers)
                                isRecordingShortcut = false
                                saveShortcut()
                            },
                            onCancel: {
                                isRecordingShortcut = false
                            }
                        )
                        .frame(width: 0, height: 0)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)

            pageNavigation(nextTitle: "下一步") { advance(to: 4) }
        }
        .padding(.top, 26)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var indexPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            pageHeading("索引例外",
                        "被勾选的目录不会进入索引，也不会出现在搜索结果中。")

            Form {
                Section {
                    Text("勾选后，这些目录不会参与索引，也不会出现在搜索结果中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(ExcludedPathsStore.presets) { preset in
                        Toggle(isOn: Binding(
                            get: { ExcludedPathsStore.shared.isEnabled(preset.path) },
                            set: { ExcludedPathsStore.shared.setEnabled($0, path: preset.path) }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(preset.title)
                                    Text(preset.path)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .monospacedDigit()
                                }
                                Text(preset.detail)
                                    .font(.caption2)
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
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)

            if !hasFullDiskAccess {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("尚未检测到“完全磁盘访问权限”。")
                    Spacer(minLength: 0)
                    Button("重新检测") {
                        hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
                    }
                    Button("打开系统设置") {
                        PermissionHelper.openFullDiskAccessSettings()
                    }
                }
                .font(.caption)
            }

            pageNavigation(nextTitle: "开始使用",
                           nextEnabled: hasFullDiskAccess) { onComplete() }
        }
        .padding(.top, 26)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            hasFullDiskAccess = PermissionHelper.hasFullDiskAccess
        }
    }

    private func pageHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Grouped forms inset their content; matching that inset keeps the
        // title, the section boxes and the footer buttons on one left edge.
        .padding(.horizontal, 20)
    }

    private func pageNavigation(nextTitle: String,
                                nextEnabled: Bool = true,
                                next: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button("上一步") {
                advance(to: step - 1)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer(minLength: 0)

            Button(nextTitle, action: next)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!nextEnabled)
        }
        .padding(.top, 2)
        .padding(.horizontal, 20)
    }

    private func advance(to next: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            step = next
        }
    }

    // MARK: - Actions

    private func loadShortcut() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hotkeyKeyCode") != nil {
            shortcutKeyCode = UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
            shortcutModifiers = UInt32(defaults.integer(forKey: "hotkeyModifiers"))
        }
        shortcutText = describeShortcut(keyCode: shortcutKeyCode, modifiers: shortcutModifiers)
    }

    private func saveShortcut() {
        UserDefaults.standard.set(Int(shortcutKeyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(shortcutModifiers), forKey: "hotkeyModifiers")
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
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

// MARK: - Traffic lights

/// Onboarding traffic lights drawn inside the glass card.
///
/// The system buttons are pinned to the window corner by AppKit, so on a card
/// that is inset from the window they end up hugging its edge. Drawing them
/// here keeps the native close/minimise/zoom behaviour while giving them a
/// comfortable 18pt margin from the card edge.
private struct TrafficLights: View {
    private enum Kind { case close, minimize, zoom }

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered: Kind?

    var body: some View {
        HStack(spacing: 8) {
            light(.close,
                  color: Color(red: 1.00, green: 0.37, blue: 0.34),
                  symbol: "xmark",
                  label: "关闭")
            light(.minimize,
                  color: Color(red: 0.99, green: 0.74, blue: 0.25),
                  symbol: "minus",
                  label: "最小化")
            light(.zoom,
                  color: Color(red: 0.27, green: 0.85, blue: 0.32),
                  symbol: "plus",
                  label: "缩放")
        }
    }

    private func light(_ kind: Kind, color: Color, symbol: String, label: String) -> some View {
        Button {
            perform(kind)
        } label: {
            ZStack {
                Circle().fill(color)
                Circle().strokeBorder(
                    Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14),
                    lineWidth: 0.5
                )
                if hovered == kind {
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .frame(width: 12, height: 12)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hovered = kind
            } else if hovered == kind {
                hovered = nil
            }
        }
        .accessibilityLabel(label)
    }

    private func perform(_ kind: Kind) {
        guard let window = NSApp.windows.first(where: { $0.title == "MacEverything" }) else { return }
        switch kind {
        case .close: window.performClose(nil)
        case .minimize: window.performMiniaturize(nil)
        case .zoom: window.performZoom(nil)
        }
    }
}
