import AppKit

/// A small card that offers a choice without taking the keyboard: "Toujours flotter ?", "Besoin de plus de place".
/// It closes by itself after `timeout` seconds, and waits while the pointer is over it.
final class ActionCard {
    static let shared = ActionCard()
    private var panel: CardPanel?
    private var closeWork: DispatchWorkItem?

    /// `near` is the rectangle to sit under (Cocoa coordinates), usually the top of a window.
    func show(title: String, message: String, buttons: [(String, Bool, () -> Void)], near: CGRect, timeout: TimeInterval) {
        dismiss(animated: false)
        let width: CGFloat = 300, padding: CGFloat = 14
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(hex: 0x26262A, alpha: 0.97).cgColor
        content.layer?.cornerRadius = 14
        content.layer?.borderWidth = 0.5; content.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        let titleField = NSTextField(wrappingLabelWithString: title)
        titleField.font = .systemFont(ofSize: 13, weight: .semibold); titleField.textColor = NSColor(hex: 0xF5F5F7)
        let messageField = NSTextField(wrappingLabelWithString: message)
        messageField.font = .systemFont(ofSize: 12); messageField.textColor = NSColor(hex: 0xEBEBF5, alpha: 0.72)
        let textWidth = width - padding * 2
        let titleHeight = titleField.sizeThatFits(CGSize(width: textWidth, height: 200)).height
        let messageHeight = message.isEmpty ? 0 : messageField.sizeThatFits(CGSize(width: textWidth, height: 200)).height
        let buttonHeight: CGFloat = 26
        let height = padding + titleHeight + (messageHeight > 0 ? 4 + messageHeight : 0) + 12 + CGFloat(buttons.count) * (buttonHeight + 6) - 6 + padding
        content.frame = CGRect(x: 0, y: 0, width: width, height: height)
        titleField.frame = CGRect(x: padding, y: height - padding - titleHeight, width: textWidth, height: titleHeight)
        messageField.frame = CGRect(x: padding, y: titleField.frame.minY - 4 - messageHeight, width: textWidth, height: messageHeight)
        content.addSubview(titleField); content.addSubview(messageField)
        var y = messageField.frame.minY - 12 - buttonHeight
        if messageHeight == 0 { y = titleField.frame.minY - 12 - buttonHeight }
        for (label, primary, action) in buttons {
            let button = CardButton(title: label, primary: primary) { [weak self] in action(); self?.dismiss(animated: true) }
            button.frame = CGRect(x: padding, y: y, width: textWidth, height: buttonHeight)
            content.addSubview(button)
            y -= buttonHeight + 6
        }
        let panel = CardPanel()
        panel.contentView = content
        panel.onHover = { [weak self] inside in
            guard let self else { return }
            if inside { self.closeWork?.cancel() } else { self.scheduleClose(after: timeout / 2) }
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(near) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = CGPoint(x: near.midX - width / 2, y: near.minY - height - 8)
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - width - 8)
        origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - height - 8)
        let target = CGRect(origin: origin, size: CGSize(width: width, height: height))
        panel.setFrame(target.offsetBy(dx: 0, dy: 6), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1; panel.animator().setFrame(target, display: true)
        }
        self.panel = panel
        scheduleClose(after: timeout)
    }
    private func scheduleClose(after delay: TimeInterval) {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    func dismiss(animated: Bool) {
        closeWork?.cancel()
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }, completionHandler: { panel.orderOut(nil) })
    }
}

private final class CardPanel: OverlayPanel {
    var onHover: ((Bool) -> Void)?
    init() {
        super.init(level: 4, mouse: true)
        hasShadow = true
    }
    override var contentView: NSView? {
        didSet { contentView?.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)) }
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

private final class CardButton: NSView {
    private let title: String
    private let primary: Bool
    private let action: () -> Void
    private var hover = false
    init(title: String, primary: Bool, action: @escaping () -> Void) {
        self.title = title; self.primary = primary; self.action = action
        super.init(frame: .zero)
        setAccessibilityRole(.button); setAccessibilityLabel(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        (primary ? NSColor.controlAccentColor.withAlphaComponent(hover ? 1 : 0.9) : NSColor.white.withAlphaComponent(hover ? 0.16 : 0.1)).setFill()
        path.fill()
        let font = NSFont.systemFont(ofSize: 12.5, weight: primary ? .semibold : .medium)
        let size = (title as NSString).size(withAttributes: [.font: font])
        (title as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: [.font: font, .foregroundColor: NSColor.white])
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { action(); return true }
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { action() } }
}
