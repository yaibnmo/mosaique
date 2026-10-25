import AppKit

/// The seven app icon styles, drawn in code on Mosaïque's own four-pane geometry:
/// a tall pane on the left, a wide one top right and two small ones under it.
enum IconStyles {
    static let all: [(id: String, name: String, summary: String)] = [
        ("washi", "Washi", "Encre brillante sur papier"),
        ("lantern", "Lanterne", "La lumière à travers le papier de riz"),
        ("indigo", "Indigo", "Panneaux blancs sur bleu franc"),
        ("sunset", "Couchant", "Un seul dégradé sur quatre panneaux"),
        ("torii", "Torii", "Panneaux crème sur vermillon"),
        ("glass", "Verre", "Panneaux de verre dépoli"),
        ("focus", "Focus", "Le panneau actif s’allume"),
    ]

    /// A resolution-independent image of the style, `size` points square.
    static func image(for style: String, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.scaleBy(x: rect.width / 1024, y: rect.height / 1024)
            // Shadows ignore the transform, so their blur and offset are scaled by hand.
            shadowScale = hypot(ctx.ctm.a, ctx.ctm.b)
            draw(style, in: ctx)
            ctx.restoreGState()
            return true
        }
        image.accessibilityDescription = "Icône Mosaïque \(all.first { $0.id == style }?.name ?? style)"
        return image
    }

    /// Sets the icon of the running app only (About panel, alerts, the Dock while a window is open).
    static func apply(_ style: String) {
        NSApp.applicationIconImage = image(for: style, size: 512)
    }

    /// Sets the Finder icon of the app bundle. Not called anywhere: writing a custom icon into the bundle
    /// may invalidate the code signature that Accessibility trust relies on. To be tested before use.
    @discardableResult
    static func applyToBundle(_ style: String) -> Bool {
        NSWorkspace.shared.setIcon(image(for: style, size: 1024), forFile: Bundle.main.bundlePath, options: [])
    }

    // MARK: Geometry (1024 canvas, y up, Apple's 824 pt icon grid)

    private static var shadowScale: CGFloat = 1
    private static func setShadow(_ ctx: CGContext, y: CGFloat, blur: CGFloat, color: CGColor) {
        ctx.setShadow(offset: CGSize(width: 0, height: y * shadowScale), blur: blur * shadowScale, color: color)
    }
    private static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    private static let bodyRadius: CGFloat = 186
    private static let paneRadius: CGFloat = 40
    /// Left tall, top right, bottom right small left, bottom right small right. The first is the "active" one.
    private static let panes: [CGRect] = [
        CGRect(x: 232, y: 232, width: 240, height: 560),
        CGRect(x: 504, y: 552, width: 288, height: 240),
        CGRect(x: 504, y: 232, width: 128, height: 288),
        CGRect(x: 664, y: 232, width: 128, height: 288),
    ]

    private static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
    private static func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    }
    /// Fills `path` with a vertical gradient from `top` to `bottom` colours over `rect`.
    private static func fillVertical(_ ctx: CGContext, _ path: CGPath, _ rect: CGRect, _ colors: [CGColor], _ locations: [CGFloat]? = nil) {
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        ctx.drawLinearGradient(gradient(colors, locations), start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    /// The squircle base with Apple's soft drop shadow.
    private static func base(_ ctx: CGContext, _ colors: [CGColor], diagonal: Bool = false) {
        let path = rounded(body, bodyRadius)
        ctx.saveGState()
        setShadow(ctx, y: -10, blur: 24, color: rgb(0, 0.3))
        ctx.addPath(path); ctx.setFillColor(colors.last!); ctx.fillPath()
        ctx.restoreGState()
        if diagonal {
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            ctx.drawLinearGradient(gradient(colors), start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
            ctx.restoreGState()
        } else {
            fillVertical(ctx, path, body, colors)
        }
    }
    /// A soft light along the top half of a pane, for glossy surfaces.
    private static func gloss(_ ctx: CGContext, _ rect: CGRect, _ alpha: CGFloat) {
        ctx.saveGState(); ctx.addPath(rounded(rect, paneRadius)); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, alpha), rgb(0xFFFFFF, 0)]), start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.maxY - min(rect.height * 0.55, 220)), options: [])
        ctx.restoreGState()
    }
    private static func stroke(_ ctx: CGContext, _ rect: CGRect, _ color: CGColor, _ width: CGFloat) {
        ctx.saveGState(); ctx.addPath(rounded(rect.insetBy(dx: width / 2, dy: width / 2), paneRadius - width / 2))
        ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.strokePath(); ctx.restoreGState()
    }
    private static func shadowed(_ ctx: CGContext, _ color: CGColor, blur: CGFloat, y: CGFloat, _ draw: () -> Void) {
        ctx.saveGState(); setShadow(ctx, y: y, blur: blur, color: color); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        ctx.endTransparencyLayer(); ctx.restoreGState()
    }

    // MARK: Styles

    private static func draw(_ style: String, in ctx: CGContext) {
        switch style {
        case "lantern": lantern(ctx)
        case "indigo": solidPanes(ctx, base: [rgb(0x2F55F0), rgb(0x1B2FB0)], panes: [rgb(0xFFFFFF), rgb(0xE4EAFF)], shadow: rgb(0x0A1460, 0.45))
        case "sunset": sunset(ctx)
        case "torii": solidPanes(ctx, base: [rgb(0xF25433), rgb(0xC42E18)], panes: [rgb(0xFFF7E6), rgb(0xF5E2BD)], shadow: rgb(0x5A0E04, 0.45))
        case "glass": glass(ctx)
        case "focus": focus(ctx)
        default: washi(ctx)
        }
    }

    /// Glossy ink panes on warm paper with faint fibres.
    private static func washi(_ ctx: CGContext) {
        base(ctx, [rgb(0xFAF6EC), rgb(0xECE3D0)])
        // Paper fibres, from a fixed seed so every render matches.
        ctx.saveGState(); ctx.addPath(rounded(body, bodyRadius)); ctx.clip()
        var seed: UInt64 = 0x5EED
        func next() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1) }
        ctx.setLineCap(.round)
        for _ in 0..<70 {
            let x = body.minX + next() * body.width, y = body.minY + next() * body.height
            let angle = next() * .pi, length = 30 + next() * 90
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length), control: CGPoint(x: x + cos(angle + 0.4) * length / 2, y: y + sin(angle + 0.4) * length / 2))
            ctx.setStrokeColor(rgb(0x8A7550, 0.06 + next() * 0.06)); ctx.setLineWidth(1.5 + next() * 2); ctx.strokePath()
        }
        ctx.restoreGState()
        shadowed(ctx, rgb(0x3A2A10, 0.32), blur: 22, y: -10) {
            for pane in panes { fillVertical(ctx, rounded(pane, paneRadius), pane, [rgb(0x34404F), rgb(0x121820)]) }
        }
        for pane in panes { gloss(ctx, pane, 0.26); stroke(ctx, pane, rgb(0xFFFFFF, 0.12), 3) }
    }

    /// Warm light glowing through rice-paper panes, on a dark wooden frame.
    private static func lantern(_ ctx: CGContext) {
        base(ctx, [rgb(0x41291A), rgb(0x1C110A)])
        shadowed(ctx, rgb(0xFFA94D, 0.75), blur: 70, y: 0) {
            for pane in panes { ctx.addPath(rounded(pane, paneRadius)); ctx.setFillColor(rgb(0xF6C068)); ctx.fillPath() }
        }
        for pane in panes {
            ctx.saveGState(); ctx.addPath(rounded(pane, paneRadius)); ctx.clip()
            let center = CGPoint(x: pane.midX, y: pane.midY + pane.height * 0.08)
            ctx.drawRadialGradient(gradient([rgb(0xFFFBEA), rgb(0xFFE3A3), rgb(0xF2A848)], [0, 0.55, 1]), startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: max(pane.width, pane.height) * 0.75, options: [.drawsAfterEndLocation])
            // Paper ribs.
            ctx.setStrokeColor(rgb(0xB0702A, 0.16)); ctx.setLineWidth(4)
            var y = pane.minY + 48
            while y < pane.maxY - 20 { ctx.move(to: CGPoint(x: pane.minX, y: y)); ctx.addLine(to: CGPoint(x: pane.maxX, y: y)); y += 48 }
            ctx.strokePath()
            ctx.restoreGState()
            stroke(ctx, pane, rgb(0x8A5420, 0.35), 4)
        }
    }

    /// Plain panes on a bold colour (Indigo, Torii).
    private static func solidPanes(_ ctx: CGContext, base colors: [CGColor], panes fill: [CGColor], shadow: CGColor) {
        base(ctx, colors)
        shadowed(ctx, shadow, blur: 26, y: -12) {
            for pane in panes { fillVertical(ctx, rounded(pane, paneRadius), pane, fill) }
        }
        for pane in panes { gloss(ctx, pane, 0.35) }
    }

    /// One sunset gradient running across the four panes, on a night sky.
    private static func sunset(_ ctx: CGContext) {
        base(ctx, [rgb(0x251C46), rgb(0x0E0B21)])
        let union = CGMutablePath()
        for pane in panes { union.addPath(rounded(pane, paneRadius)) }
        shadowed(ctx, rgb(0xFF6A5A, 0.4), blur: 50, y: -6) {
            ctx.addPath(union); ctx.setFillColor(rgb(0xFF7A59)); ctx.fillPath()
        }
        ctx.saveGState(); ctx.addPath(union); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(0xFFD36E), rgb(0xFF8A5C), rgb(0xF2506E), rgb(0x8F3FD9)], [0, 0.35, 0.65, 1]),
                               start: CGPoint(x: 300, y: 792), end: CGPoint(x: 724, y: 232), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
        for pane in panes { gloss(ctx, pane, 0.22) }
    }

    /// Frosted glass panes over soft colour blobs.
    private static func glass(_ ctx: CGContext) {
        base(ctx, [rgb(0x4E6CF5), rgb(0x9A4FE8)], diagonal: true)
        ctx.saveGState(); ctx.addPath(rounded(body, bodyRadius)); ctx.clip()
        for (center, radius, color) in [(CGPoint(x: 290, y: 760), CGFloat(380), rgb(0x48E0E6)), (CGPoint(x: 800, y: 260), 360, rgb(0xFF6FB0)), (CGPoint(x: 760, y: 820), 260, rgb(0xFFD36E))] {
            ctx.drawRadialGradient(gradient([color, color.copy(alpha: 0)!]), startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
        ctx.restoreGState()
        shadowed(ctx, rgb(0x1A1060, 0.22), blur: 30, y: -10) {
            for pane in panes { ctx.addPath(rounded(pane, paneRadius)); ctx.setFillColor(rgb(0xFFFFFF, 0.26)); ctx.fillPath() }
        }
        for pane in panes {
            fillVertical(ctx, rounded(pane, paneRadius), pane, [rgb(0xFFFFFF, 0.30), rgb(0xFFFFFF, 0.06)])
            stroke(ctx, pane, rgb(0xFFFFFF, 0.7), 3)
        }
    }

    /// Dim panes on graphite; the active one (the tall pane) lights up.
    private static func focus(_ ctx: CGContext) {
        base(ctx, [rgb(0x2A2A31), rgb(0x131317)])
        for pane in panes.dropFirst() {
            fillVertical(ctx, rounded(pane, paneRadius), pane, [rgb(0x41414B), rgb(0x30303A)])
            stroke(ctx, pane, rgb(0xFFFFFF, 0.07), 3)
        }
        let active = panes[0]
        shadowed(ctx, rgb(0x42D9C2, 0.8), blur: 60, y: 0) {
            fillVertical(ctx, rounded(active, paneRadius), active, [rgb(0x7AF0DC), rgb(0x24B5A2)])
        }
        gloss(ctx, active, 0.35)
        stroke(ctx, active, rgb(0xFFFFFF, 0.35), 3)
    }
}
