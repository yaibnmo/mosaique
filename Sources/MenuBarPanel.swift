import AppKit
import SwiftUI
import Combine

/// The menu bar item and its panel: a borderless glass panel under the item, 324 pt wide.
/// It opens on a click on the item and closes on Esc, a click elsewhere, or a second click on the item.
final class MenuBarController: NSObject {
    private let engine: WindowEngine
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var openSettings: ((String?) -> Void)?

    private let model = MenuBarModel()
    private var panel: MenuBarWindow?
    private var host: MenuBarHost?
    private var screenID: String?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var changes: AnyCancellable?
    private var pending = false
    private var timer: Timer?
    private var iconKey = ""
    private(set) var isOpen = false

    init(engine: WindowEngine) {
        self.engine = engine
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(itemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.setAccessibilityLabel("Mosaïque")
        }
        model.actions = makeActions()
        // Published engine changes (switches, permission, Secure Input…) refresh the icon and the open panel, once per run loop turn.
        changes = engine.objectWillChange.sink { [weak self] _ in self?.scheduleUpdate() }
        refresh()
    }

    deinit {
        timer?.invalidate()
        monitors.forEach(NSEvent.removeMonitor)
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
    }

    /// Called whenever the engine state changes, to refresh the icon (filled, outlined, Clean Space mark).
    func refresh() {
        let filled = engine.statusKind == .active
        let mark = engine.cleanSpace
        let key = "\(filled)-\(mark)"
        if key != iconKey {
            iconKey = key
            item.button?.image = MenuBarGlyph.image(filled: filled, cleanMark: mark)
        }
        item.button?.toolTip = "Mosaïque · " + engine.statusLine
        if isOpen { model.snapshot = makeSnapshot() }
    }

    private func scheduleUpdate() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in self?.pending = false; self?.refresh() }
    }

    // MARK: Snapshot and actions

    private var screen: DisplayOption? {
        engine.displays.first { $0.id == screenID } ?? engine.pointerDisplay
    }

    private func makeSnapshot() -> MenuBarSnapshot {
        var s = MenuBarSnapshot()
        s.status = engine.statusKind
        s.statusLine = engine.statusLine
        s.autoTiling = engine.autoStart
        s.trusted = engine.trusted
        s.setupDone = engine.setupDone
        s.enabled = engine.enabled && engine.trusted
        s.secureInput = engine.secureInput && engine.shortcutsEnabled
        s.shortcutsEnabled = engine.shortcutsEnabled
        s.shortcutIssue = engine.shortcutIssue
        s.focusActive = engine.focusActive
        if let screen {
            s.screenSize = screen.frame.size
            let config = engine.config(for: screen)
            s.kind = config.kind
            s.capacity = config.capacity
            s.customSizes = engine.hasCustomSizes(screen)
            s.columnCapacity = engine.columnCapacity(screen)
            if s.enabled && s.setupDone && !engine.stageManager { s.panes = engine.preview(for: screen) }
        }
        s.bordersOn = engine.highlight == "all"
        s.hoverFocus = engine.hoverFocus
        s.cleanSpace = engine.cleanSpace
        s.noPeek = engine.noPeek
        s.dimAmount = engine.dimAmount
        if let app = engine.frontApp, let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier {
            s.frontApp = app.localizedName ?? bundle
            s.frontAppIcon = app.icon
            s.frontAppTiled = engine.isTiled(bundle: bundle)
        }
        return s
    }

    /// The panel answers at once: the snapshot changes first, the engine (which moves windows) runs a frame later.
    private func instant(_ edit: (inout MenuBarSnapshot) -> Void, then work: @escaping () -> Void) {
        edit(&model.snapshot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in work(); self?.refresh() }
    }

    /// Preview panes laid out for a new layout or count before the engine has moved anything.
    private func predictedPanes(kind: LayoutKind, count: Int) -> [PreviewPane]? {
        guard let screen else { return nil }
        let panes = model.snapshot.panes
        let current = engine.config(for: screen)
        let settings = DisplaySettings(kind: kind, capacity: count, ratios: kind == current.kind ? current.ratios : [])
        let gap = CGFloat(engine.effectiveGap)
        let n = min(panes.count, TileLayout.capacity(settings, bounds: screen.frame, gap: gap))
        guard n > 0, let frames = TileLayout.plan(in: screen.frame, minimums: Array(repeating: .zero, count: n), settings: settings, gap: gap)?.frames else { return nil }
        let f = screen.frame
        return frames.enumerated().map { i, r in
            let old = panes[i]
            // Panes that no longer fit join the last tile's stack, as the engine does.
            let stack = i == n - 1 ? panes[i...].reduce(0) { $0 + $1.stackCount } : old.stackCount
            return PreviewPane(id: old.id, unit: CGRect(x: (r.minX - f.minX) / f.width, y: (r.minY - f.minY) / f.height, width: r.width / f.width, height: r.height / f.height),
                               app: old.app, icon: old.icon, active: old.active, stackCount: stack, focus: false)
        }
    }

    private func makeActions() -> MenuBarActions {
        var a = MenuBarActions()
        a.setAutomaticTiling = { [weak self] on in
            self?.instant({ $0.autoTiling = on }) { self?.engine.setAutomaticTiling(on) }
        }
        a.grantAccess = { [weak self] in
            guard let self else { return }
            self.engine.requestAccess()
            if !self.engine.trusted { self.engine.openAccessibility() }
            self.refresh()
        }
        a.tidy = { [weak self] in self?.instant({ $0.setupDone = true }) { self?.engine.completeSetup() } }
        a.showKeyboard = { [weak self] in self?.close(animated: false); self?.openSettings?("keyboard") }
        a.resetSizes = { [weak self] in
            guard let self, let screen = self.screen else { return }
            self.instant({ $0.customSizes = false }) { self.engine.resetSizes(for: screen) }
        }
        a.setKind = { [weak self] kind in
            guard let self, let screen = self.screen else { return }
            let panes = self.predictedPanes(kind: kind, count: self.model.snapshot.capacity)
            self.instant({ $0.kind = kind; $0.customSizes = false; if let panes { $0.panes = panes } }) {
                self.engine.changeSettings(for: screen, notify: false) { $0.kind = kind }
            }
        }
        a.setCapacity = { [weak self] count in
            guard let self, let screen = self.screen else { return }
            let panes = count < self.model.snapshot.panes.count ? self.predictedPanes(kind: self.model.snapshot.kind, count: count) : nil
            self.instant({ $0.capacity = count; if let panes { $0.panes = panes } }) {
                self.engine.changeSettings(for: screen, notify: false) { $0.capacity = count }
            }
        }
        a.retile = { [weak self] in self?.instant({ _ in }) { self?.engine.retile() } }
        a.toggleBorders = { [weak self] in self?.instant({ $0.bordersOn.toggle() }) { self?.engine.toggleBorders() } }
        a.toggleHoverFocus = { [weak self] in self?.instant({ $0.hoverFocus.toggle() }) { self?.engine.hoverFocus.toggle() } }
        a.toggleCleanSpace = { [weak self] in
            guard let self else { return }
            self.instant({ $0.cleanSpace.toggle() }) {
                self.engine.toggleCleanSpace()
                // Clean Space hides the panel, like every other overlay.
                if self.engine.cleanSpace { self.close(animated: true) }
            }
        }
        a.toggleNoPeek = { [weak self] in self?.instant({ $0.noPeek.toggle() }) { self?.engine.toggleNoPeek() } }
        a.setDim = { [weak self] value in self?.model.snapshot.dimAmount = value; self?.engine.dimAmount = value }
        a.setFrontAppTiled = { [weak self] on in
            guard let self, let bundle = self.engine.frontApp?.bundleIdentifier else { return }
            self.instant({ $0.frontAppTiled = on }) { self.engine.setTiled(bundle: bundle, on) }
        }
        a.openSettings = { [weak self] in self?.close(animated: false); self?.openSettings?(nil) }
        a.quit = { NSApp.terminate(nil) }
        return a
    }

    // MARK: Opening and closing

    @objc private func itemClicked() { isOpen ? close(animated: true) : open() }

    private func open() {
        guard !isOpen, let button = item.button, let buttonWindow = button.window else { return }
        isOpen = true
        screenID = engine.pointerDisplay?.id
        model.snapshot = makeSnapshot()
        let panel = self.panel ?? makePanel()
        button.highlight(true)

        let size = host?.fittingSize ?? CGSize(width: 324, height: 600)
        let final = frame(for: size, below: buttonWindow.frame)
        panel.alphaValue = 0
        panel.setFrame(final.offsetBy(dx: 0, dy: 4), display: false)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(final, display: true)
        }
        installMonitors()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func close(animated: Bool) {
        guard isOpen, let panel else { return }
        isOpen = false
        timer?.invalidate(); timer = nil
        removeMonitors()
        item.button?.highlight(false)
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            guard let self, !self.isOpen else { return }
            panel?.orderOut(nil)
        })
    }

    private func makePanel() -> MenuBarWindow {
        let panel = MenuBarWindow()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 324, height: 600))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let blur = NSVisualEffectView(frame: container.bounds)
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)

        let host = MenuBarHost(rootView: MenuBarPanelRoot(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.onResize = { [weak self] in self?.fitToContent() }
        container.addSubview(host)

        panel.contentView = container
        self.host = host
        self.panel = panel
        return panel
    }

    /// Keeps the top edge under the menu bar while the content grows or shrinks (the dim slider, cards…).
    private func fitToContent() {
        guard let panel, let host, let buttonWindow = item.button?.window else { return }
        let size = host.fittingSize
        guard abs(size.height - panel.frame.height) > 0.5 || abs(size.width - panel.frame.width) > 0.5 else { return }
        var frame = self.frame(for: size, below: buttonWindow.frame)
        if !isOpen { frame.origin = panel.frame.origin }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// Centred under the item, 4 pt below the menu bar, kept 8 pt inside the screen.
    private func frame(for size: CGSize, below itemFrame: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: itemFrame.midX, y: itemFrame.midY)) } ?? NSScreen.main
        let bounds = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let menuBarBottom = screen.map { $0.visibleFrame.maxY } ?? itemFrame.minY
        let top = min(itemFrame.minY, menuBarBottom) - 4
        let x = min(max(itemFrame.midX - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        return CGRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
    }

    // MARK: Events

    private func installMonitors() {
        removeMonitors()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            self?.close(animated: true)
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel && event.window !== self.item.button?.window { self.close(animated: true) }
            return event
        }) { monitors.append(local) }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.isOpen else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 { self.close(animated: true); return nil }
            if flags == .command, event.charactersIgnoringModifiers == "," { self.model.actions.openSettings(); return nil }
            if flags == .command, event.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return nil }
            return event
        }) { monitors.append(keys) }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.close(animated: false) })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.close(animated: false) })
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}

/// A borderless panel that takes key events (Esc, ⌘,) without activating Mosaïque, so the app in front stays in front.
final class MenuBarWindow: NSPanel {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 324, height: 600), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class MenuBarHost: NSHostingView<MenuBarPanelRoot> {
    var onResize: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onResize?() }
    }
}

/// The panel content on its glass: the window's blur shows through a tint of `--glass`.
struct MenuBarPanelRoot: View {
    @ObservedObject var model: MenuBarModel
    /// Draws the glass colour fully opaque (for renders, where there is nothing behind to blur).
    var opaque = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = MenuBarTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        MenuBarPanelView(model: model)
            .background(shape.fill(t.glass.opacity(opaque ? 1 : (t.dark ? 0.72 : 0.78))))
            .clipShape(shape)
            .overlay(shape.strokeBorder(t.edge, lineWidth: 0.5))
    }
}
