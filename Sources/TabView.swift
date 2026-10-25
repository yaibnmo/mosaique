import AppKit
import SwiftUI
import Combine

/// Tab View, ⌥⇥: every window shown where it sits, screen by screen.
/// The first pick is the window used before the active one, so a quick ⌥⇥ switches back without showing the panel.
final class TabViewController {
    private enum Phase { case closed, pending, shown }

    private let engine: WindowEngine
    private let model = TabViewModel()
    private var panel: TabViewWindow?
    private var host: NSHostingView<TabViewRoot>?
    private var phase = Phase.closed
    /// Opened without ⌥ held: stays open until Return, a click or Esc.
    private var sticky = false
    private var showWork: DispatchWorkItem?
    private var poll: Timer?
    private var monitors: [Any] = []
    private var startMouse = CGPoint.zero
    private var activeID: Int?
    /// The app in front before Tab View took the keys; it comes back when Tab View closes without switching.
    private var previousApp: NSRunningApplication?
    private var resignObserver: NSObjectProtocol?
    /// Most recently used windows first.
    private var recent: [Int] = []
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []

    init(engine: WindowEngine) {
        self.engine = engine
        model.choose = { [weak self] id in self?.commit(id) }
        // Window activation order, for the first pick. The engine republishes its rows after every scan,
        // which includes focus changes inside an app; app switches are caught straight away.
        engine.$windowRows.sink { [weak self] _ in DispatchQueue.main.async { self?.noteActive() } }.store(in: &cancellables)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.noteActive() }
        })
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        poll?.invalidate()
        monitors.forEach(NSEvent.removeMonitor)
    }

    /// Opens Tab View, or moves the selection by `step` if it is already open.
    func open(step: Int) {
        if phase != .closed { move(by: step); return }
        guard !engine.cleanSpace else { return }
        noteActive()
        let snapshot = makeSnapshot()
        guard !snapshot.order.isEmpty else { return }
        activeID = engine.activeWindow?.id
        model.snapshot = snapshot
        model.current = activeID
        model.selected = firstPick(step: step, order: snapshot.order)
        model.hoverEnabled = false
        model.visible = false
        sticky = !NSEvent.modifierFlags.contains(.option)
        phase = .pending
        startPolling()
        if sticky { show() }
        else {
            // 120 ms: a quick ⌥⇥ tap switches without flashing the panel.
            let work = DispatchWorkItem { [weak self] in self?.show() }
            showWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }

    // MARK: Data

    private func noteActive() {
        guard phase == .closed, let id = engine.activeWindow?.id else { return }
        remember(id)
    }

    private func remember(_ id: Int) {
        guard recent.first != id else { return }
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        if recent.count > 64 { recent.removeLast(recent.count - 64) }
    }

    /// The window used before the active one; ⌥⇧⇥ starts one step back from the active window.
    private func firstPick(step: Int, order: [Int]) -> Int? {
        let current = activeID.flatMap { order.firstIndex(of: $0) }
        if step < 0 { return order[((current ?? 0) - 1 + order.count) % order.count] }
        if let previous = recent.first(where: { $0 != activeID && order.contains($0) }) { return previous }
        if let current { return order[(current + 1) % order.count] }
        return order.first
    }

    private func makeSnapshot() -> TabViewSnapshot {
        let rows = engine.windowRows
        let displays = engine.displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        var screens: [TabViewScreen] = []
        var order: [Int] = []
        for display in displays {
            let own = rows.filter { $0.screenID == display.id || ($0.screenID.isEmpty && display.id == displays.first?.id) }
            let byID = Dictionary(own.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let layout = engine.tabViewOrder(for: display.id).filter { byID[$0] != nil }
            let tiled = layout.filter { byID[$0]!.minimized == false && byID[$0]!.waiting == false }
            let free = own.filter { !$0.minimized && !$0.waiting && !tiled.contains($0.id) }.map(\.id)
            let waiting = layout.filter { byID[$0]!.waiting && !byID[$0]!.minimized } + own.filter { $0.waiting && !$0.minimized && !layout.contains($0.id) }.map(\.id)
            let minimized = layout.filter { byID[$0]!.minimized } + own.filter { $0.minimized && !layout.contains($0.id) }.map(\.id)
            func item(_ id: Int, _ state: TabViewItem.State) -> TabViewItem {
                let row = byID[id]!
                return TabViewItem(id: id, app: row.app, title: row.title, icon: row.icon, frame: row.frame, state: state, screenName: display.name)
            }
            screens.append(TabViewScreen(id: display.id, name: display.name, builtIn: Self.isBuiltIn(display),
                                         frame: display.frame,
                                         mapItems: tiled.map { item($0, .tiled) } + free.map { item($0, .free) },
                                         chips: waiting.map { item($0, .waiting) } + minimized.map { item($0, .minimized) }))
            order += tiled + free + waiting + minimized
        }
        let visible = activeScreen()?.visibleFrame.width ?? 1440
        return TabViewSnapshot(screens: screens, order: order, scale: TabViewSnapshot.scale(for: screens.map(\.frame), maxWidth: visible * 0.92 - 40))
    }

    private static func isBuiltIn(_ display: DisplayOption) -> Bool {
        let cocoa = ScreenSpace.cocoa(display.frame)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(cocoa) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
        return CGDisplayIsBuiltin(number) != 0
    }

    /// The screen of the active window, else the one under the pointer.
    private func activeScreen() -> NSScreen? {
        if let window = engine.activeWindow {
            let center = ScreenSpace.cocoa(window.frame)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: center.midX, y: center.midY)) }) { return screen }
        }
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    // MARK: Showing

    private func show() {
        guard phase == .pending else { return }
        showWork = nil
        phase = .shown
        let panel = self.panel ?? makePanel()
        guard let host else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let screen = activeScreen()?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Centred, slightly above the middle (translate −50 % −55 %).
        let origin = CGPoint(x: (screen.midX - size.width / 2).rounded(), y: (screen.midY - size.height / 2 + size.height * 0.05).rounded())
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        startMouse = NSEvent.mouseLocation
        panel.alphaValue = 0
        // Mosaïque comes forward while Tab View is open so the arrows, Return and Esc always reach it.
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()

        // Opacity and scale 0.97 → 1 over 0.14 s, ease-out.
        if let layer = panel.contentView?.layer {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var start = CATransform3DMakeTranslation(center.x, center.y, 0)
            start = CATransform3DScale(start, 0.97, 0.97, 1)
            start = CATransform3DTranslate(start, -center.x, -center.y, 0)
            let animation = CABasicAnimation(keyPath: "sublayerTransform")
            animation.fromValue = NSValue(caTransform3D: start)
            animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            animation.duration = 0.14
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.sublayerTransform = CATransform3DIdentity
            layer.add(animation, forKey: "open")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        model.visible = true
    }

    private func makePanel() -> TabViewWindow {
        let panel = TabViewWindow()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        container.wantsLayer = true

        let clip = NSView(frame: container.bounds)
        clip.wantsLayer = true
        clip.layer?.cornerRadius = 18
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.autoresizingMask = [.width, .height]
        let blur = NSVisualEffectView(frame: clip.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.autoresizingMask = [.width, .height]
        clip.addSubview(blur)
        container.addSubview(clip)

        let host = NSHostingView(rootView: TabViewRoot(model: model))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        panel.contentView = container
        self.host = host
        self.panel = panel
        return panel
    }

    private func close(restore: Bool = true) {
        let wasShown = phase == .shown
        showWork?.cancel(); showWork = nil
        poll?.invalidate(); poll = nil
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        phase = .closed
        model.visible = false
        panel?.orderOut(nil)
        if wasShown && restore { previousApp?.activate() }
        if wasShown { previousApp = nil }
    }

    // MARK: Choosing

    private func commit(_ id: Int? = nil) {
        guard phase != .closed else { return }
        let chosen = id ?? model.selected
        let wasActive = activeID
        let item = chosen.flatMap { model.snapshot.item($0) }
        // Choosing a minimized window restores it; engine.select handles both and brings its app forward.
        let switching = chosen != nil && (chosen != wasActive || item?.state == .minimized)
        close(restore: !switching)
        guard let chosen else { return }
        if switching { engine.select(chosen) }
        remember(chosen)
    }

    private func cancel() { close() }

    private func move(by step: Int) {
        let order = model.snapshot.order
        guard !order.isEmpty else { return }
        let index = model.selected.flatMap { order.firstIndex(of: $0) } ?? (step > 0 ? -1 : 0)
        model.selected = order[((index + step) % order.count + order.count) % order.count]
    }

    private enum Direction { case left, right, up, down }

    /// The nearest tile or chip that way, across screens: overlapping ones first, then the closest, then the best aligned.
    private func move(_ direction: Direction) {
        guard let id = model.selected, let from = model.rects[id] else { return }
        let tolerance: CGFloat = 4
        var best: (overlap: Bool, gap: CGFloat, cross: CGFloat, id: Int)?
        for (other, rect) in model.rects where other != id && model.snapshot.order.contains(other) {
            let ahead: Bool, gap: CGFloat, overlap: Bool, cross: CGFloat
            switch direction {
            case .left:  ahead = rect.maxX <= from.minX + tolerance && rect.midX < from.midX; gap = from.minX - rect.maxX
            case .right: ahead = rect.minX >= from.maxX - tolerance && rect.midX > from.midX; gap = rect.minX - from.maxX
            case .up:    ahead = rect.maxY <= from.minY + tolerance && rect.midY < from.midY; gap = from.minY - rect.maxY
            case .down:  ahead = rect.minY >= from.maxY - tolerance && rect.midY > from.midY; gap = rect.minY - from.maxY
            }
            guard ahead else { continue }
            if direction == .left || direction == .right {
                overlap = min(rect.maxY, from.maxY) - max(rect.minY, from.minY) > 0; cross = abs(rect.midY - from.midY)
            } else {
                overlap = min(rect.maxX, from.maxX) - max(rect.minX, from.minX) > 0; cross = abs(rect.midX - from.midX)
            }
            let candidate = (overlap: overlap, gap: max(0, gap), cross: cross, id: other)
            if let current = best {
                let better = (candidate.overlap && !current.overlap)
                    || (candidate.overlap == current.overlap && (candidate.gap < current.gap - 0.5
                        || (abs(candidate.gap - current.gap) <= 0.5 && candidate.cross < current.cross)))
                if better { best = candidate }
            } else { best = candidate }
        }
        if let best { model.selected = best.id }
    }

    // MARK: Events

    private func startPolling() {
        poll?.invalidate()
        // ⌥ is read from the hardware state, so its release is seen even before the panel shows or takes key events.
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            guard let self, self.phase != .closed else { return }
            if !self.sticky && !NSEvent.modifierFlags.contains(.option) { self.commit(); return }
            if self.phase == .shown && !self.model.hoverEnabled {
                let p = NSEvent.mouseLocation
                if hypot(p.x - self.startMouse.x, p.y - self.startMouse.y) > 2 { self.model.hoverEnabled = true }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func installMonitors() {
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.phase == .shown else { return event }
            switch Int(event.keyCode) {
            case 53: self.cancel()
            case 36, 76: self.commit()
            case 48: self.move(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            case 123: self.move(.left)
            case 124: self.move(.right)
            case 125: self.move(.down)
            case 126: self.move(.up)
            default: break
            }
            return nil
        }) { monitors.append(keys) }
        if let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            if let self, !self.sticky, !event.modifierFlags.contains(.option) { self.commit() }
            return event
        }) { monitors.append(flags) }
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.cancel() }) {
            monitors.append(clicks)
        }
        resignObserver.map(NotificationCenter.default.removeObserver)
        // ⌘⇥ or a click in another app while Tab View is open: it closes, leaving the new app in front.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.phase == .shown else { return }
            self.close(restore: false)
        }
    }
}

/// Borderless and non-activating: it takes the keys (arrows, Return, Esc) while the app in front keeps its place.
final class TabViewWindow: NSPanel {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
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
