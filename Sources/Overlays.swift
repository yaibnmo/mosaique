import AppKit
import QuartzCore

// Overlays drawn above other apps: the grip and hover bar of stacks, highlights, No peek, Clean Space,
// drop targets, notices and the tidy sweep. Sizes, colours and timings follow the reference demo.

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
    static let stackOrange = NSColor(hex: 0xFF9500)
    static let stackOrangeHover = NSColor(hex: 0xFFB340)
}

/// Converts between Accessibility coordinates (top-left origin) and Cocoa screen coordinates.
enum ScreenSpace {
    static var top: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
    static func cocoa(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) }
    static func ax(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) }
    static func axPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: top - p.y) }
}

class OverlayPanel: NSPanel {
    init(level: Int = 0, mouse: Bool = false) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + level)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; isReleasedWhenClosed = false; ignoresMouseEvents = !mouse
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private func shadowed(_ layer: CALayer, outline: CGFloat, outlineAlpha: CGFloat, blur: CGFloat, y: CGFloat, alpha: CGFloat) {
    layer.borderWidth = outline; layer.borderColor = NSColor.black.withAlphaComponent(outlineAlpha).cgColor
    layer.shadowColor = NSColor.black.cgColor; layer.shadowOpacity = Float(alpha); layer.shadowRadius = blur / 2; layer.shadowOffset = CGSize(width: 0, height: -y)
}

// MARK: - Grip

struct StackTab {
    let id: Int
    let title: String
    let icon: NSImage?
    let selected: Bool
    let action: () -> Void
}

/// The handle centred in the gap above the active window: a white pill, or one orange mark per window of a stack.
/// Inactive stacked tiles show smaller marks ("dots").
final class StackGrip: OverlayPanel {
    enum Kind { case active, dots }
    static let hitHeight: CGFloat = 18
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private let view = GripView()
    private(set) var kind: Kind = .active
    init() {
        super.init(level: 1, mouse: true)
        setAccessibilityLabel("Poignée Mosaïque")
        contentView = view
        view.onEnter = { [weak self] in self?.onEnter?() }
        view.onExit = { [weak self] in self?.onExit?() }
    }
    var tabs: [StackTab] { view.tabs }
    var near: Bool { get { view.near } set { view.near = newValue } }

    /// `center` is in Cocoa coordinates.
    func update(center: CGPoint, tabs: [StackTab], kind: Kind) {
        self.kind = kind
        let width = GripView.hitWidth(count: tabs.count, kind: kind)
        let height = kind == .dots ? 14 : Self.hitHeight
        let frame = CGRect(x: (center.x - width / 2).rounded(), y: (center.y - height / 2).rounded(), width: width, height: height)
        view.configure(tabs: tabs, kind: kind)
        if self.frame != frame { setFrame(frame, display: false); view.frame = CGRect(origin: .zero, size: frame.size); view.layout() }
        alphaValue = kind == .dots ? (view.near ? 1 : 0.85) : 1
        if !isVisible { orderFrontRegardless() }
    }
    func segment(at point: CGPoint) -> Int? { view.segment(at: point) }
}

final class GripView: NSView {
    private(set) var tabs: [StackTab] = []
    private var kind: StackGrip.Kind = .active
    private let pill = CALayer()
    private var marks: [CALayer] = []
    private var hovered: Int?
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var near = false { didSet { if near != oldValue { layout() } } }

    static let pillRest = CGSize(width: 32, height: 5), pillNear = CGSize(width: 44, height: 5)
    static func markSizes(_ kind: StackGrip.Kind) -> (showing: CGFloat, other: CGFloat) { kind == .dots ? (16, 7) : (26, 10) }
    static let markHeight: CGFloat = 6, spacing: CGFloat = 4
    static func marksWidth(count: Int, kind: StackGrip.Kind) -> CGFloat {
        let s = markSizes(kind)
        return s.showing + CGFloat(max(0, count - 1)) * (s.other + spacing)
    }
    static func hitWidth(count: Int, kind: StackGrip.Kind) -> CGFloat {
        kind == .dots ? marksWidth(count: count, kind: kind) + 8 : (count > 1 ? max(48, marksWidth(count: count, kind: kind) + 16) : 48)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pill.backgroundColor = NSColor(hex: 0xFFFFFF, alpha: 0.96).cgColor
        pill.cornerRadius = 3
        shadowed(pill, outline: 0.5, outlineAlpha: 0.35, blur: 4, y: 1, alpha: 0.3)
        layer?.addSublayer(pill)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    func configure(tabs: [StackTab], kind: StackGrip.Kind) {
        self.tabs = tabs; self.kind = kind
        while marks.count < tabs.count {
            let mark = CALayer(); mark.cornerRadius = 3
            shadowed(mark, outline: 0.5, outlineAlpha: 0.45, blur: 3, y: 1, alpha: 0.3)
            layer?.addSublayer(mark); marks.append(mark)
        }
        while marks.count > tabs.count { marks.removeLast().removeFromSuperlayer() }
        layout()
        updateTracking()
    }
    func markFrames() -> [CGRect] {
        let s = Self.markSizes(kind)
        var x = (bounds.width - Self.marksWidth(count: tabs.count, kind: kind)) / 2
        return tabs.map { tab in
            let w = tab.selected ? s.showing : s.other
            defer { x += w + Self.spacing }
            return CGRect(x: x, y: (bounds.height - Self.markHeight) / 2, width: w, height: Self.markHeight)
        }
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setAnimationDuration(0.15)
        let stacked = tabs.count > 1
        pill.isHidden = stacked || kind == .dots
        let size = near ? Self.pillNear : Self.pillRest
        pill.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        pill.opacity = near ? 1 : 0.5
        CATransaction.setAnimationDuration(0.2)
        for (index, frame) in markFrames().enumerated() where stacked || kind == .dots {
            marks[index].isHidden = false
            marks[index].frame = frame
            let color: NSColor = hovered == index ? .stackOrangeHover : (tabs[index].selected ? .stackOrange : NSColor.stackOrange.withAlphaComponent(0.5))
            marks[index].backgroundColor = color.cgColor
        }
        if !(stacked || kind == .dots) { marks.forEach { $0.isHidden = true } }
        CATransaction.commit()
    }
    func segment(at point: CGPoint) -> Int? {
        guard tabs.count > 1 || kind == .dots else { return nil }
        let rects = markFrames()
        return rects.indices.min { abs(rects[$0].midX - point.x) < abs(rects[$1].midX - point.x) }
            .flatMap { abs(rects[$0].midX - point.x) <= rects[$0].width / 2 + Self.spacing / 2 + 1 ? $0 : nil }
    }
    private func updateTracking() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { near = true; (window as? StackGrip).map { $0.alphaValue = 1 }; onEnter?() }
    override func mouseExited(with event: NSEvent) {
        hovered = nil; near = false
        if let grip = window as? StackGrip, grip.kind == .dots { grip.alphaValue = 0.85 }
        layout(); onExit?()
    }
    override func mouseMoved(with event: NSEvent) {
        let index = segment(at: convert(event.locationInWindow, from: nil))
        if index != hovered { hovered = index; layout() }
    }
    override func mouseDown(with event: NSEvent) {
        if let index = segment(at: convert(event.locationInWindow, from: nil)) { tabs[index].action() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Hover bar

struct BarAction {
    let title: String
    let symbol: String
    let keys: [String]
    var enabled = true
    let action: () -> Void
}

/// The bar that opens when the pointer rests on the grip. 440 × 54, or 90 with a stack row; centred on the grip.
final class StackHUD: OverlayPanel {
    static let size = CGSize(width: 440, height: 54), stackRow: CGFloat = 36
    private(set) var anchorKey: String?
    private var opened = Date.distantPast
    private var signature = ""
    private var closeWork: DispatchWorkItem?
    private let content = NSView()
    var onScroll: ((Int) -> Void)?
    var onChipDrag: ((Int, CGPoint, Bool) -> Void)?
    private(set) var chipButtons: [ChipButton] = []
    private(set) var actionButtons: [HUDActionButton] = []

    init() {
        super.init(level: 2, mouse: true)
        hasShadow = true
        setAccessibilityLabel("Barre d’actions Mosaïque")
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(hex: 0x222226).cgColor
        content.layer?.cornerRadius = 12
        content.layer?.borderWidth = 0.5; content.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        contentView = content
    }

    /// Buttons ignore clicks for the first 400 ms, so the click that opened it cannot trigger an action.
    var acceptsClicks: Bool { Date().timeIntervalSince(opened) >= 0.4 }

    func show(key: String, center: CGPoint, area: CGRect, tabs: [StackTab], actions: [BarAction]) {
        cancelClose()
        let wasOpen = isVisible && anchorKey == key
        anchorKey = key
        render(center: center, area: area, tabs: tabs, actions: actions, force: true)
        guard !wasOpen else { return }
        opened = Date()
        // Fade in from 96 % scale, anchored at the top centre, 0.14 s ease-out.
        content.layer?.anchorPoint = CGPoint(x: 0.5, y: 1)
        content.layer?.position = CGPoint(x: frame.width / 2, y: frame.height)
        alphaValue = 0
        orderFrontRegardless()
        content.layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = CATransform3DMakeScale(0.96, 0.96, 1); scale.toValue = CATransform3DIdentity
        scale.duration = 0.14; scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        content.layer?.add(scale, forKey: "open"); content.layer?.transform = CATransform3DIdentity
    }
    var onReorder: (([Int]) -> Void)?
    private var reorderIDs: [Int]?
    /// Moves the other chips aside, live, while one is dragged along the row.
    func previewReorder(_ moving: ChipButton, screenX: CGFloat) {
        guard let row = chipButtons.first?.superview, let window = row.window else { return }
        let local = row.convert(window.convertPoint(fromScreen: CGPoint(x: screenX, y: 0)), from: nil).x
        var others = chipButtons.filter { $0 !== moving }
        let index = others.firstIndex { $0.frame.midX > local } ?? others.count
        others.insert(moving, at: index)
        reorderIDs = others.map(\.tab.id)
        let total = others.reduce(0) { $0 + $1.preferredWidth } + CGFloat(max(0, others.count - 1)) * 2
        var x: CGFloat = 0; _ = total
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18; context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            context.allowsImplicitAnimation = true
            for chip in others {
                let frame = CGRect(x: x, y: chip.frame.minY, width: chip.preferredWidth, height: chip.frame.height)
                if chip !== moving { chip.animator().frame = frame } else { chip.frame = frame }
                x += chip.preferredWidth + 2
            }
        }
    }
    func commitReorder() {
        guard let ids = reorderIDs else { return }
        reorderIDs = nil
        onReorder?(ids)
    }
    func refresh(key: String, center: CGPoint, area: CGRect, tabs: [StackTab], actions: [BarAction]) {
        guard isVisible, anchorKey == key else { return }
        render(center: center, area: area, tabs: tabs, actions: actions, force: false)
    }
    func scheduleClose(after delay: TimeInterval = 0.35) {
        cancelClose()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Stay open while the pointer is over the bar or a chip is being dragged.
            if self.frame.contains(NSEvent.mouseLocation) || NSEvent.pressedMouseButtons != 0 { self.scheduleClose(); return }
            self.dismiss()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    func cancelClose() { closeWork?.cancel(); closeWork = nil }
    func dismiss(animated: Bool = true) {
        cancelClose()
        guard isVisible else { anchorKey = nil; return }
        anchorKey = nil; signature = ""
        guard animated else { orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in if self?.anchorKey == nil { self?.orderOut(nil) } })
        let scale = CABasicAnimation(keyPath: "transform")
        scale.toValue = CATransform3DMakeScale(0.97, 0.97, 1); scale.duration = 0.12; scale.fillMode = .forwards; scale.isRemovedOnCompletion = false
        content.layer?.add(scale, forKey: "close")
    }
    override func mouseEntered(with event: NSEvent) { cancelClose() }
    override func mouseExited(with event: NSEvent) { if NSEvent.pressedMouseButtons == 0 { scheduleClose() } }
    override func scrollWheel(with event: NSEvent) {
        guard !chipButtons.isEmpty else { return }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        guard abs(delta) > 3, event.momentumPhase == [] else { return }
        if event.phase == [] || event.phase == .began || abs(delta) > 12 { onScroll?(delta > 0 ? -1 : 1) }
    }

    private func render(center: CGPoint, area: CGRect, tabs: [StackTab], actions: [BarAction], force: Bool) {
        let next = tabs.map { "\($0.id):\($0.selected):\($0.title)" }.joined(separator: "|") + "#" + actions.map { "\($0.title)\($0.enabled)" }.joined(separator: "|")
        let stacked = tabs.count > 1
        let size = CGSize(width: Self.size.width, height: Self.size.height + (stacked ? Self.stackRow : 0))
        // Centred on the grip, kept 6 pt inside the screen.
        let origin = CGPoint(x: min(max(center.x - size.width / 2, area.minX + 6), area.maxX - size.width - 6),
                             y: min(max(center.y - size.height / 2, area.minY + 6), area.maxY - size.height - 6))
        let frame = CGRect(origin: origin, size: size).integral
        if self.frame != frame { setFrame(frame, display: false) }
        guard force || next != signature else { return }
        signature = next
        content.subviews.forEach { $0.removeFromSuperview() }
        content.frame = CGRect(origin: .zero, size: size)
        content.trackingAreas.forEach(content.removeTrackingArea)
        content.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        let padding: CGFloat = 4
        chipButtons = []
        if stacked {
            let rowY = size.height - padding - 30
            let previous = HUDArrow(symbol: "chevron.left", help: "Fenêtre précédente") { [weak self] in self?.onScroll?(-1) }
            previous.frame = CGRect(x: padding + 2, y: rowY + 3, width: 22, height: 24)
            let following = HUDArrow(symbol: "chevron.right", help: "Fenêtre suivante") { [weak self] in self?.onScroll?(1) }
            following.frame = CGRect(x: size.width - padding - 24, y: rowY + 3, width: 22, height: 24)
            let clip = NSScrollView(frame: CGRect(x: padding + 26, y: rowY, width: size.width - padding * 2 - 52, height: 30))
            clip.drawsBackground = false; clip.hasHorizontalScroller = false; clip.verticalScrollElasticity = .none; clip.horizontalScrollElasticity = .none
            let row = NSView()
            var x: CGFloat = 0
            for tab in tabs {
                let chip = ChipButton(tab: tab, guardian: { [weak self] in self?.acceptsClicks ?? false })
                chip.onDrag = { [weak self] point, ended in
                    guard let self else { return }
                    // Inside the bar it is a reorder, not a move to another tile.
                    if self.frame.insetBy(dx: 0, dy: -8).contains(point) { if ended { self.onChipDrag?(tab.id, CGPoint(x: -1e6, y: -1e6), true) } else { self.onChipDrag?(tab.id, CGPoint(x: -1e6, y: -1e6), false) } }
                    else { self.onChipDrag?(tab.id, point, ended) }
                }
                chip.rowContains = { [weak self] point in self?.frame.insetBy(dx: 0, dy: -8).contains(point) ?? false }
                chip.onReorderPreview = { [weak self, weak chip] x in if let chip { self?.previewReorder(chip, screenX: x) } }
                chip.onReorderCommit = { [weak self] in self?.commitReorder() }
                chip.frame = CGRect(x: x, y: 3, width: chip.preferredWidth, height: 24)
                row.addSubview(chip); chipButtons.append(chip); x += chip.preferredWidth + 2
            }
            let rowWidth = max(0, x - 2)
            row.frame = CGRect(x: 0, y: 0, width: max(rowWidth, clip.contentSize.width), height: 30)
            // Chips start at the left, right after ‹, as in the reference.
            clip.documentView = row
            if let selected = chipButtons.first(where: { $0.tab.selected }) { row.scrollToVisible(selected.frame.insetBy(dx: -30, dy: 0)) }
            [previous, following, clip].forEach(content.addSubview)
            let line = NSView(frame: CGRect(x: padding + 6, y: rowY - 3, width: size.width - padding * 2 - 12, height: 0.5))
            line.wantsLayer = true; line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
            content.addSubview(line)
        }
        let slot = (size.width - padding * 2 - CGFloat(max(0, actions.count - 1)) * 2) / CGFloat(max(1, actions.count))
        actionButtons = actions.enumerated().map { index, action in
            let button = HUDActionButton(action: action, guardian: { [weak self] in self?.acceptsClicks ?? false }) { [weak self] in self?.dismiss() }
            button.frame = CGRect(x: padding + CGFloat(index) * (slot + 2), y: padding, width: slot, height: Self.size.height - padding * 2)
            content.addSubview(button)
            return button
        }
    }
}

final class ChipButton: NSView {
    let tab: StackTab
    var onDrag: ((CGPoint, Bool) -> Void)?
    private let guardian: () -> Bool
    private var downPoint: CGPoint?
    private var dragging = false
    private var hover = false
    private let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
    init(tab: StackTab, guardian: @escaping () -> Bool) {
        self.tab = tab; self.guardian = guardian
        super.init(frame: .zero)
        setAccessibilityRole(.button); setAccessibilityLabel(tab.title)
        setAccessibilityValue(tab.selected ? "Affichée" : ""); toolTip = "Clique pour l’afficher, ou glisse-la sur une autre case"
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var preferredWidth: CGFloat { min(150, (tab.title as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 4 + 16 + 5 + 8) }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        if tab.selected {
            NSColor.stackOrange.withAlphaComponent(0.28).setFill(); path.fill()
            NSColor.stackOrange.withAlphaComponent(0.7).setStroke()
            let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5.5, yRadius: 5.5); inner.lineWidth = 1; inner.stroke()
        } else if hover { NSColor.white.withAlphaComponent(0.1).setFill(); path.fill() }
        if let icon = tab.icon {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: CGRect(x: 4, y: (bounds.height - 16) / 2, width: 16, height: 16), xRadius: 4, yRadius: 4).addClip()
            icon.draw(in: CGRect(x: 4, y: (bounds.height - 16) / 2, width: 16, height: 16))
            NSGraphicsContext.restoreGraphicsState()
        }
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        (tab.title as NSString).draw(in: CGRect(x: 25, y: (bounds.height - 15) / 2, width: bounds.width - 33, height: 15),
                                     withAttributes: [.font: font, .foregroundColor: NSColor(hex: 0xF5F5F7), .paragraphStyle: style])
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { tab.action(); return true }
    // The chip follows the pointer directly (no system drag image): inside the bar the other chips make room
    // live; dropped over another tile, its window moves there.
    var onReorderPreview: ((CGFloat) -> Void)?
    var onReorderCommit: (() -> Void)?
    var rowContains: ((CGPoint) -> Bool)?
    private var ghostPanel: OverlayPanel?
    private var grabOffset = CGPoint.zero
    override func mouseDown(with event: NSEvent) { downPoint = event.locationInWindow; dragging = false }
    override func mouseDragged(with event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation
        if !dragging {
            guard let downPoint, hypot(event.locationInWindow.x - downPoint.x, event.locationInWindow.y - downPoint.y) > 4 else { return }
            dragging = true
            let local = convert(downPoint, from: nil)
            grabOffset = CGPoint(x: local.x, y: local.y)
            let panel = OverlayPanel(level: 6)
            let size = CGSize(width: preferredWidth + 2, height: 26)
            let view = NSImageView(frame: CGRect(origin: .zero, size: size)); view.image = ghost()
            panel.contentView = view; panel.hasShadow = true
            panel.setFrame(CGRect(origin: CGPoint(x: screenPoint.x - grabOffset.x, y: screenPoint.y - grabOffset.y), size: size), display: true)
            panel.orderFrontRegardless()
            ghostPanel = panel
            alphaValue = 0.25
            NSCursor.closedHand.push()
        }
        ghostPanel?.setFrameOrigin(CGPoint(x: screenPoint.x - grabOffset.x, y: screenPoint.y - grabOffset.y))
        if rowContains?(screenPoint) == true {
            onReorderPreview?(screenPoint.x); onDrag?(screenPoint, false)
        } else { onDrag?(screenPoint, false) }
    }
    private func ghost() -> NSImage {
        let size = CGSize(width: preferredWidth + 2, height: 26)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(hex: 0x1E1E22, alpha: 0.9).setFill(); NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            self.tab.icon?.draw(in: CGRect(x: 5, y: 5, width: 16, height: 16))
            (self.tab.title as NSString).draw(at: CGPoint(x: 26, y: 6), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
            return true
        }
    }
    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard dragging else {
            if bounds.contains(convert(event.locationInWindow, from: nil)), guardian() { tab.action() }
            return
        }
        dragging = false
        NSCursor.pop()
        let point = NSEvent.mouseLocation
        ghostPanel?.orderOut(nil); ghostPanel = nil
        alphaValue = 1
        if rowContains?(point) == true { onDrag?(point, true); onReorderCommit?() }
        else { onDrag?(point, true) }
    }
}

final class HUDActionButton: NSView {
    let action: BarAction
    private let guardian: () -> Bool
    private let after: () -> Void
    private var hover = false, pressed = false
    init(action: BarAction, guardian: @escaping () -> Bool, after: @escaping () -> Void) {
        self.action = action; self.guardian = guardian; self.after = after
        super.init(frame: .zero)
        setAccessibilityRole(.button); setAccessibilityLabel(action.title); setAccessibilityEnabled(action.enabled)
        toolTip = action.title + " (" + action.keys.joined() + ")"
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        alphaValue = action.enabled ? 1 : 0.35
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        if (hover || pressed) && action.enabled {
            NSColor.white.withAlphaComponent(pressed ? 0.16 : 0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let title = action.title as NSString
        let titleWidth = title.size(withAttributes: [.font: titleFont]).width
        let titleRowWidth = 14 + 5 + titleWidth
        let titleY = bounds.midY + 1
        var x = (bounds.width - titleRowWidth) / 2
        if let image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold)) {
            let tinted = NSImage(size: CGSize(width: 14, height: 14), flipped: false) { rect in
                let fit = min(14 / image.size.width, 14 / image.size.height)
                let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
                image.draw(in: CGRect(x: (14 - size.width) / 2, y: (14 - size.height) / 2, width: size.width, height: size.height))
                NSColor(hex: 0xF5F5F7).set(); rect.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: CGRect(x: x, y: titleY, width: 14, height: 14))
        }
        x += 19
        title.draw(at: CGPoint(x: x, y: titleY - 1), withAttributes: [.font: titleFont, .foregroundColor: NSColor(hex: 0xF5F5F7)])
        // Keycaps: min 16 × 15, 10.5 pt, 2 pt apart.
        let keyFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let widths = action.keys.map { max(16, ($0 as NSString).size(withAttributes: [.font: keyFont]).width + 6) }
        var kx = (bounds.width - (widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * 2)) / 2
        let ky = titleY - 19
        for (key, width) in zip(action.keys, widths) {
            let cap = CGRect(x: kx, y: ky, width: width, height: 15)
            NSColor.white.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: cap, xRadius: 4, yRadius: 4).fill()
            let size = (key as NSString).size(withAttributes: [.font: keyFont])
            (key as NSString).draw(at: CGPoint(x: cap.midX - size.width / 2, y: cap.midY - size.height / 2), withAttributes: [.font: keyFont, .foregroundColor: NSColor(hex: 0xEBEBF5, alpha: 0.65)])
            kx += width + 2
        }
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { guard action.enabled else { return false }; action.action(); after(); return true }
    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false; needsDisplay = true
        guard action.enabled, guardian(), bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action.action(); after()
    }
}

final class HUDArrow: NSButton {
    private let onPress: () -> Void
    init(symbol: String, help: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?.withSymbolConfiguration(.init(pointSize: 11, weight: .heavy))
        isBordered = false; contentTintColor = NSColor(hex: 0xF5F5F7, alpha: 0.8)
        toolTip = help; setAccessibilityLabel(help)
        target = self; action = #selector(press)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func press() { onPress() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Highlight, No peek and Clean Space

/// One per screen: borders around windows and the No peek veil, with holes for the active window and its dialogs.
final class DecorationPanel: OverlayPanel {
    private let view = DecorationView()
    private var blurView: NSVisualEffectView?
    init() { super.init(); contentView = view; setAccessibilityElement(false) }
    func render(screen: CGRect, holes: [CGRect], dim: Double, outlines: [CGRect], color: NSColor, width: Double, blur: Bool) {
        guard dim > 0 || !outlines.isEmpty else {
            if isVisible { NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; animator().alphaValue = 0 }, completionHandler: { [weak self] in if self?.alphaValue == 0 { self?.orderOut(nil) } }) }
            return
        }
        if frame != screen { setFrame(screen, display: false) }
        let local = { (r: CGRect) in r.offsetBy(dx: -screen.minX, dy: -screen.minY) }
        let changed = view.holes != holes.map(local) || view.dim != dim || view.outlines != outlines.map(local) || view.color != color || view.lineWidth != width
        view.holes = holes.map(local); view.outlines = outlines.map(local)
        view.dim = dim; view.color = color; view.lineWidth = width
        view.frame = CGRect(origin: .zero, size: screen.size)
        if blur && dim > 0 {
            let backdrop = blurView ?? NSVisualEffectView()
            backdrop.material = .fullScreenUI; backdrop.blendingMode = .behindWindow; backdrop.state = .active
            backdrop.frame = view.bounds; backdrop.maskImage = view.mask()
            if blurView == nil { view.addSubview(backdrop, positioned: .below, relativeTo: nil); blurView = backdrop }
        } else { blurView?.removeFromSuperview(); blurView = nil }
        if changed { view.needsDisplay = true }
        if !isVisible || alphaValue < 1 {
            if !isVisible { alphaValue = 0; orderFrontRegardless() }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; animator().alphaValue = 1 }
        }
    }
}
private final class DecorationView: NSView {
    var holes: [CGRect] = [], outlines: [CGRect] = []
    var dim: Double = 0
    var color = NSColor.controlAccentColor
    var lineWidth: CGFloat = 3
    func mask() -> NSImage {
        NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            for hole in self.holes { NSBezierPath(roundedRect: hole, xRadius: 10, yRadius: 10).fill() }
            return true
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if dim > 0 {
            NSColor.black.withAlphaComponent(dim).setFill(); bounds.fill()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            for hole in holes { NSBezierPath(roundedRect: hole, xRadius: 10, yRadius: 10).fill() }
            NSGraphicsContext.restoreGraphicsState()
        }
        // Borders sit outside the window, following its rounded corners, inside the gap.
        color.setStroke()
        for rect in outlines {
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2), xRadius: 10 + lineWidth / 2, yRadius: 10 + lineWidth / 2)
            path.lineWidth = lineWidth; path.stroke()
        }
    }
}

/// Glow on active: a 3 pt line of colour, 80 % of the window's width, in the gap above it. It slides between windows.
final class GlowPanel: OverlayPanel {
    private let bar = CALayer()
    override init(level: Int = 0, mouse: Bool = false) {
        super.init(level: level, mouse: mouse)
        let view = NSView(); view.wantsLayer = true; contentView = view
        bar.cornerRadius = 1.5
        view.layer?.addSublayer(bar)
    }
    /// `window` is in Cocoa coordinates; `gap` is the effective gap.
    func show(above window: CGRect, gap: CGFloat, color: NSColor) {
        let line = CGRect(x: window.minX + window.width * 0.1, y: window.maxY + max(gap, 4) / 2 - 1.5, width: window.width * 0.8, height: 3)
        let frame = line.insetBy(dx: -14, dy: -14)
        bar.backgroundColor = color.cgColor
        bar.shadowColor = color.cgColor; bar.shadowOpacity = 0.7; bar.shadowRadius = 6; bar.shadowOffset = .zero
        if !isVisible {
            setFrame(frame, display: false); layoutBar(); alphaValue = 0; orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; animator().alphaValue = 1 }
            return
        }
        guard self.frame != frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            context.allowsImplicitAnimation = true
            animator().setFrame(frame, display: true)
        }
        layoutBar(size: frame.size)
    }
    private func layoutBar(size: CGSize? = nil) {
        let s = size ?? frame.size
        CATransaction.begin(); CATransaction.setAnimationDuration(0.5)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1))
        bar.frame = CGRect(x: 14, y: 14, width: s.width - 28, height: 3)
        CATransaction.commit()
    }
    func hide() { if isVisible { orderOut(nil) } }
}

/// Clean Space: two panels slide in from the screen edges and meet behind the active window (0.38 s).
final class CleanSpacePanel: OverlayPanel {
    private let left = CALayer(), right = CALayer()
    private var hole = CGRect.zero
    private let maskLayer = CAShapeLayer()
    override init(level: Int = 0, mouse: Bool = false) {
        super.init(level: level, mouse: mouse)
        let view = NSView(); view.wantsLayer = true; contentView = view
        let container = CALayer()
        container.addSublayer(left); container.addSublayer(right)
        container.mask = maskLayer; maskLayer.fillRule = .evenOdd
        view.layer?.addSublayer(container)
        container.frame = .zero
        container.name = "container"
    }
    private var container: CALayer? { contentView?.layer?.sublayers?.first { $0.name == "container" } }
    /// `screen` and `window` are in Cocoa coordinates.
    func close(screen: CGRect, around window: CGRect, color: NSColor) {
        setFrame(screen, display: false)
        let local = window.offsetBy(dx: -screen.minX, dy: -screen.minY)
        let meet = min(max(local.midX, 0), screen.width)
        container?.frame = CGRect(origin: .zero, size: screen.size)
        updateHole(local, size: screen.size)
        left.backgroundColor = color.cgColor; right.backgroundColor = color.cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        left.frame = CGRect(x: 0, y: 0, width: 0, height: screen.height)
        right.frame = CGRect(x: screen.width, y: 0, width: 0, height: screen.height)
        CATransaction.commit()
        orderFrontRegardless()
        CATransaction.begin(); CATransaction.setAnimationDuration(0.38)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1))
        left.frame = CGRect(x: 0, y: 0, width: meet + 1, height: screen.height)
        right.frame = CGRect(x: meet, y: 0, width: screen.width - meet, height: screen.height)
        CATransaction.commit()
    }
    func follow(window: CGRect) {
        guard isVisible else { return }
        let local = window.offsetBy(dx: -frame.minX, dy: -frame.minY)
        updateHole(local, size: frame.size)
    }
    func color(_ color: NSColor) { left.backgroundColor = color.cgColor; right.backgroundColor = color.cgColor }
    private func updateHole(_ rect: CGRect, size: CGSize) {
        hole = rect
        let path = CGMutablePath(); path.addRect(CGRect(origin: .zero, size: size))
        path.addRoundedRect(in: rect, cornerWidth: 10, cornerHeight: 10)
        maskLayer.path = path
    }
    func open() {
        guard isVisible else { return }
        let width = frame.width
        CATransaction.begin(); CATransaction.setAnimationDuration(0.38)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1))
        CATransaction.setCompletionBlock { [weak self] in self?.orderOut(nil) }
        left.frame = CGRect(x: 0, y: 0, width: 0, height: frame.height)
        right.frame = CGRect(x: width, y: 0, width: 0, height: frame.height)
        CATransaction.commit()
    }
}

// MARK: - Drag targets

/// Accent fill at 24 % with a 3 pt inner border; "Ajouter à la pile" / "Déplacer ici" label pill.
final class DropHighlight: OverlayPanel {
    private let label = NSTextField(labelWithString: "")
    private let pill = NSView()
    override init(level: Int = 0, mouse: Bool = false) {
        super.init(level: 3, mouse: false)
        let view = NSView(); view.wantsLayer = true
        view.layer?.cornerRadius = 12; view.layer?.borderWidth = 3
        contentView = view
        pill.wantsLayer = true; pill.layer?.cornerRadius = 8
        pill.shadow = NSShadow(); pill.layer?.shadowOpacity = 0.25; pill.layer?.shadowRadius = 8; pill.layer?.shadowOffset = CGSize(width: 0, height: -6)
        label.font = .systemFont(ofSize: 13, weight: .semibold); label.textColor = .white
        pill.addSubview(label); view.addSubview(pill)
    }
    /// `rect` is in Cocoa coordinates.
    func show(_ rect: CGRect, text: String?, color: NSColor) {
        contentView?.layer?.backgroundColor = color.withAlphaComponent(0.24).cgColor
        contentView?.layer?.borderColor = color.cgColor
        if frame != rect { setFrame(rect, display: true) }
        pill.isHidden = text == nil
        if let text {
            label.stringValue = text; label.sizeToFit()
            let size = CGSize(width: label.frame.width + 24, height: label.frame.height + 12)
            pill.frame = CGRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2, width: size.width, height: size.height)
            label.frame.origin = CGPoint(x: 12, y: 6)
            pill.layer?.backgroundColor = color.cgColor
        }
        if !isVisible { alphaValue = 0; orderFrontRegardless(); NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 } }
    }
    func hide() { if isVisible { orderOut(nil) } }
}

// MARK: - Notices

struct Notice {
    let title: String
    var message: String = ""
    var symbol: String = "rectangle.3.group"
    var sound: Bool = false
}

/// The volume-style HUD: 200 × 170, radius 22, 72 pt above the bottom of the usable area. Shown 2.6 s.
final class NoticeCenter {
    static let shared = NoticeCenter()
    private var panel: OverlayPanel?
    private var hideWork: DispatchWorkItem?
    private var counter = 0
    /// `area` is the usable area (visible frame) of the screen, in Cocoa coordinates.
    func show(_ notice: Notice, on area: CGRect) {
        counter += 1
        let token = counter
        hideWork?.cancel()
        panel?.orderOut(nil)
        let panel = OverlayPanel(level: 4)
        let width: CGFloat = 200
        let content = NSView(frame: CGRect(x: 0, y: 0, width: width, height: 170))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(hex: 0x26262A, alpha: 0.96).cgColor
        content.layer?.cornerRadius = 22
        content.layer?.borderWidth = 0.5; content.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        let icon = NSImageView(frame: CGRect(x: (width - 46) / 2, y: 170 - 18 - 54, width: 46, height: 46))
        icon.image = NSImage(systemSymbolName: notice.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 38, weight: .light))
        icon.contentTintColor = NSColor(hex: 0xF5F5F7)
        let title = NSTextField(wrappingLabelWithString: notice.title)
        title.font = .systemFont(ofSize: 15, weight: .semibold); title.textColor = NSColor(hex: 0xF5F5F7); title.alignment = .center
        let message = NSTextField(wrappingLabelWithString: notice.message)
        message.font = .systemFont(ofSize: 12); message.textColor = NSColor(hex: 0xEBEBF5, alpha: 0.72); message.alignment = .center
        let textWidth = width - 36
        title.preferredMaxLayoutWidth = textWidth; message.preferredMaxLayoutWidth = textWidth
        let titleHeight = title.sizeThatFits(CGSize(width: textWidth, height: 200)).height
        let messageHeight = notice.message.isEmpty ? 0 : message.sizeThatFits(CGSize(width: textWidth, height: 300)).height
        let height = max(170, 18 + 62 + 6 + titleHeight + (messageHeight > 0 ? 6 + messageHeight : 0) + 20)
        content.frame.size.height = height
        icon.frame.origin.y = height - 18 - 54
        title.frame = CGRect(x: 18, y: height - 18 - 62 - 6 - titleHeight, width: textWidth, height: titleHeight)
        message.frame = CGRect(x: 18, y: title.frame.minY - 6 - messageHeight, width: textWidth, height: messageHeight)
        [icon, title, message].forEach(content.addSubview)
        panel.contentView = content
        panel.hasShadow = true
        let target = CGRect(x: area.midX - width / 2, y: area.minY + 72, width: width, height: height)
        panel.setFrame(target.offsetBy(dx: 0, dy: -8), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1; panel.animator().setFrame(target, display: true)
        }
        if notice.sound { NSSound.beep() }
        self.panel = panel
        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel, self.counter == token else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }, completionHandler: { panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }
}

/// "Focus · ⌃⌥Z pour revenir": a pill at the bottom of the zoomed window, gone after 2.6 s.
final class FocusTag {
    static let shared = FocusTag()
    private var panel: OverlayPanel?
    func show(on window: CGRect, text: String = "Focus · ⌃⌥Z pour revenir") {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11.5, weight: .medium); label.textColor = .white
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 20, height: label.frame.height + 8)
        let panel = OverlayPanel(level: 4)
        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true; view.layer?.backgroundColor = NSColor(hex: 0x18181C, alpha: 0.78).cgColor; view.layer?.cornerRadius = size.height / 2
        label.frame.origin = CGPoint(x: 10, y: 4); view.addSubview(label)
        panel.contentView = view
        panel.setFrame(CGRect(x: window.midX - size.width / 2, y: window.minY + 14, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.8; panel?.animator().alphaValue = 0 }, completionHandler: { panel?.orderOut(nil) })
        }
    }
    func hide() { panel?.orderOut(nil) }
}

// MARK: - Tidy sweep and chime

/// The first tidy: a light band sweeps across the screen in 0.75 s and each tile flashes an accent ring as it passes.
final class TidySweep {
    static let shared = TidySweep()
    private var panels: [OverlayPanel] = []
    /// `screen` and `tiles` are in Cocoa coordinates.
    func play(screen: CGRect, tiles: [CGRect], color: NSColor) {
        let panel = OverlayPanel(level: 5)
        panel.setFrame(screen, display: false)
        let view = NSView(frame: CGRect(origin: .zero, size: screen.size)); view.wantsLayer = true
        panel.contentView = view
        let bandWidth = screen.width * 0.32
        let band = CAGradientLayer()
        band.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        band.startPoint = CGPoint(x: 0, y: 0.5); band.endPoint = CGPoint(x: 1, y: 0.5)
        band.frame = CGRect(x: -bandWidth, y: 0, width: bandWidth, height: screen.height)
        view.layer?.addSublayer(band)
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -bandWidth / 2; move.toValue = screen.width + bandWidth / 2
        move.duration = 0.75; move.beginTime = CACurrentMediaTime() + 0.08
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); move.fillMode = .both; move.isRemovedOnCompletion = false
        band.add(move, forKey: "sweep")
        for tile in tiles {
            let local = tile.offsetBy(dx: -screen.minX, dy: -screen.minY)
            let ring = CAShapeLayer()
            ring.path = CGPath(roundedRect: local, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ring.fillColor = nil; ring.strokeColor = color.cgColor; ring.lineWidth = 2
            ring.shadowColor = color.cgColor; ring.shadowOpacity = 0.6; ring.shadowRadius = 9; ring.shadowOffset = .zero
            ring.opacity = 0
            view.layer?.addSublayer(ring)
            let r = Double((local.midX + bandWidth / 2) / (screen.width + bandWidth))
            let flash = CAKeyframeAnimation(keyPath: "opacity")
            flash.values = [0, 1, 0]; flash.keyTimes = [0, 0.5, 1]; flash.duration = 0.4
            flash.beginTime = CACurrentMediaTime() + max(0, 0.08 + r * 0.75 - 0.2)
            flash.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); flash.fillMode = .both; flash.isRemovedOnCompletion = false
            ring.add(flash, forKey: "flash")
        }
        panel.orderFrontRegardless()
        panels.append(panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self, weak panel] in
            panel?.orderOut(nil); self?.panels.removeAll { $0 === panel }
        }
    }
}

/// A soft bell (F6 with inharmonic partials), synthesised once and kept in memory.
enum Chime {
    private static let sound: NSSound? = {
        let rate = 44_100.0, length = 1.7
        let partials: [(ratio: Double, level: Double, ring: Double)] = [(1, 1, 1.5), (2, 0.32, 0.9), (2.76, 0.22, 0.6), (5.4, 0.08, 0.3)]
        let count = Int(rate * length)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / rate - 0.08
            guard t >= 0 else { continue }
            let attack = min(1, t / 0.005)
            var value = 0.0
            for p in partials { value += p.level * exp(-t * 6.9 / p.ring) * sin(2 * .pi * 1396.9 * p.ratio * t) }
            samples[i] = Int16(max(-1, min(1, value * 0.16 * attack)) * Double(Int16.max))
        }
        var data = Data()
        func append<T>(_ value: T) { var v = value; data.append(Data(bytes: &v, count: MemoryLayout<T>.size)) }
        data.append("RIFF".data(using: .ascii)!); append(UInt32(36 + count * 2)); data.append("WAVEfmt ".data(using: .ascii)!)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append("data".data(using: .ascii)!); append(UInt32(count * 2))
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return NSSound(data: data)
    }()
    static func play() { sound?.stop(); sound?.play() }
}

enum Haptic {
    static func tap() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
}
