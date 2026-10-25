import SwiftUI
import AppKit

// The menu bar panel's content, drawn from a snapshot of the engine so it can also be rendered with sample data.
// Sizes, colours and texts follow the reference panel.

// MARK: - Mosaïque glyph

/// Mosaïque's own mark: four panes laid like mosaic tiles, a wide and a narrow pane on each row, swapped on the second row.
enum MenuBarGlyph {
    /// Panes in an 18 × 18 box.
    static let panes: [CGRect] = {
        let x0: CGFloat = 1.5, y0: CGFloat = 2.5, w: CGFloat = 15, h: CGFloat = 13, gap: CGFloat = 1.6
        let row = (h - gap) / 2, wide = ((w - gap) * 0.62).rounded(toPlaces: 1), narrow = w - gap - wide
        return [CGRect(x: x0, y: y0, width: wide, height: row),
                CGRect(x: x0 + wide + gap, y: y0, width: narrow, height: row),
                CGRect(x: x0, y: y0 + row + gap, width: narrow, height: row),
                CGRect(x: x0 + narrow + gap, y: y0 + row + gap, width: wide, height: row)]
    }()
    static let radius: CGFloat = 1.5
    static let stroke: CGFloat = 1.2
    static let markCenter = CGPoint(x: 15.7, y: 14.7), markRadius: CGFloat = 2.3, markClearance: CGFloat = 1.3

    /// Template image for the status item: filled while tiling, outlined otherwise, with a dot for Clean Space.
    static func image(filled: Bool, cleanMark: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: size / 18, y: size / 18)
            NSColor.black.setFill(); NSColor.black.setStroke()
            for pane in panes {
                if filled {
                    NSBezierPath(roundedRect: pane, xRadius: radius, yRadius: radius).fill()
                } else {
                    let inset = pane.insetBy(dx: stroke / 2, dy: stroke / 2)
                    let path = NSBezierPath(roundedRect: inset, xRadius: radius - stroke / 2, yRadius: radius - stroke / 2)
                    path.lineWidth = stroke; path.stroke()
                }
            }
            if cleanMark {
                let r = markRadius + markClearance
                context.setBlendMode(.clear)
                context.fillEllipse(in: CGRect(x: markCenter.x - r, y: markCenter.y - r, width: 2 * r, height: 2 * r))
                context.setBlendMode(.normal)
                context.fillEllipse(in: CGRect(x: markCenter.x - markRadius, y: markCenter.y - markRadius, width: 2 * markRadius, height: 2 * markRadius))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mosaïque"
        return image
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat { let f = pow(10, CGFloat(places)); return (self * f).rounded() / f }
}

/// The glyph as a SwiftUI view, for the panel header.
struct MenuBarGlyphView: View {
    var filled: Bool
    var size: CGFloat = 21
    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 18
            for pane in MenuBarGlyph.panes {
                let rect = CGRect(x: pane.minX * s, y: pane.minY * s, width: pane.width * s, height: pane.height * s)
                if filled {
                    context.fill(Path(roundedRect: rect, cornerRadius: MenuBarGlyph.radius * s), with: .foreground)
                } else {
                    let w = MenuBarGlyph.stroke * s
                    context.stroke(Path(roundedRect: rect.insetBy(dx: w / 2, dy: w / 2), cornerRadius: (MenuBarGlyph.radius - MenuBarGlyph.stroke / 2) * s), with: .foreground, lineWidth: w)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Snapshot

struct MenuBarSnapshot {
    var status: StatusKind = .active
    var statusLine = ""
    var autoTiling = true
    var trusted = true
    var setupDone = true
    var enabled = true
    var secureInput = false
    var shortcutsEnabled = true
    /// Non-empty when other apps hold some shortcuts or macOS refused them.
    var shortcutIssue = ""
    var screenSize = CGSize(width: 1440, height: 875)
    var panes: [PreviewPane] = []
    var focusActive = false
    var customSizes = false
    var kind: LayoutKind = .grid
    var capacity = 3
    var columnCapacity = 3
    var bordersOn = false
    var hoverFocus = false
    var cleanSpace = false
    var noPeek = false
    var dimAmount = 0.5
    var frontApp: String?
    var frontAppIcon: NSImage?
    var frontAppTiled = true

    var tall: Bool { screenSize.height > screenSize.width }
    var previewMessage: String? {
        if !setupDone { return "Termine la configuration pour commencer" }
        if !enabled || !trusted { return "Le rangement est désactivé" }
        if panes.isEmpty { return "Aucune fenêtre à ranger sur cet écran" }
        return nil
    }
    /// The highest count this screen can show with its layout.
    var maxCount: Int { tall ? 3 : (kind == .columns ? min(4, columnCapacity) : 4) }
}

struct MenuBarActions {
    var setAutomaticTiling: (Bool) -> Void = { _ in }
    var grantAccess: () -> Void = {}
    var tidy: () -> Void = {}
    var showKeyboard: () -> Void = {}
    var resetSizes: () -> Void = {}
    var setKind: (LayoutKind) -> Void = { _ in }
    var setCapacity: (Int) -> Void = { _ in }
    var retile: () -> Void = {}
    var toggleBorders: () -> Void = {}
    var toggleHoverFocus: () -> Void = {}
    var toggleCleanSpace: () -> Void = {}
    var toggleNoPeek: () -> Void = {}
    var setDim: (Double) -> Void = { _ in }
    var setFrontAppTiled: (Bool) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
}

final class MenuBarModel: ObservableObject {
    @Published var snapshot = MenuBarSnapshot()
    var actions = MenuBarActions()
}

// MARK: - Theme

private func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
}

/// Light and dark tokens of the reference (`--text`, `--fill`, `--glass`…).
struct MenuBarTheme {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var text: Color { dark ? rgb(0xF5F5F7) : rgb(0x1D1D1F) }
    var text2: Color { dark ? rgb(0xEBEBF5, 0.70) : rgb(0x3C3C43, 0.78) }
    var text3: Color { dark ? rgb(0xEBEBF5, 0.42) : rgb(0x3C3C43, 0.50) }
    var fill: Color { dark ? rgb(0xFFFFFF, 0.08) : rgb(0x000000, 0.06) }
    var fill2: Color { dark ? rgb(0xFFFFFF, 0.14) : rgb(0x000000, 0.10) }
    var edge: Color { dark ? rgb(0xFFFFFF, 0.14) : rgb(0x000000, 0.14) }
    var glass: Color { dark ? rgb(0x26262C) : rgb(0xF6F6F8) }
    var solid: Color { dark ? rgb(0x36363C) : .white }
    var accent: Color { Color(nsColor: .controlAccentColor) }
    var paneLine: Color { text.opacity(0.22) }
    /// Panes of the count thumbnails and the segmented glyphs.
    var thumb: Color { dark ? rgb(0xFFFFFF, 0.28) : rgb(0x000000, 0.20) }
    var glyph: Color { dark ? rgb(0xFFFFFF, 0.55) : rgb(0x000000, 0.52) }
}

/// cubic-bezier(.32,.72,0,1), 0.4 s: how the preview panes move.
private let paneCurve = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.4)

// MARK: - Shared controls

/// `.sw.small`: 32 × 19, knob 15, springy knob (cubic-bezier(.3,.7,.3,1.3) over 0.28 s).
struct MenuBarSwitch: View {
    var isOn: Bool
    var enabled = true
    var action: (Bool) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = MenuBarTheme(scheme)
        ZStack(alignment: .leading) {
            Capsule().fill(isOn ? t.accent : t.fill2)
                .animation(.easeInOut(duration: 0.2), value: isOn)
            Circle().fill(Color.white)
                .frame(width: 15, height: 15)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                .offset(x: isOn ? 15 : 2)
                .animation(.timingCurve(0.3, 0.7, 0.3, 1.3, duration: 0.28), value: isOn)
        }
        .frame(width: 32, height: 19)
        .contentShape(Capsule())
        .opacity(enabled ? 1 : 0.45)
        .onTapGesture { if enabled { action(!isOn) } }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "Activé" : "Désactivé")
    }
}

/// The reference's range input: a light grey track, the accent fill and an accent knob.
struct MenuBarSlider: View {
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var onChange: (Double) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = MenuBarTheme(scheme)
        GeometryReader { geo in
            let knob: CGFloat = 15
            let span = geo.size.width - knob
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(t.dark ? rgb(0xFFFFFF, 0.12) : rgb(0xFFFFFF))
                    .overlay(Capsule().strokeBorder(t.dark ? rgb(0xFFFFFF, 0.12) : rgb(0x000000, 0.22), lineWidth: 0.5))
                    .frame(height: 5)
                Capsule().fill(t.accent).frame(width: knob / 2 + span * fraction, height: 5)
                Circle().fill(t.accent)
                    .frame(width: knob, height: knob)
                    .offset(x: span * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(1, max(0, (drag.location.x - knob / 2) / max(1, span)))
                let raw = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                let snapped = (raw / step).rounded() * step
                if abs(snapped - value) > 0.0001 { onChange(min(range.upperBound, max(range.lowerBound, snapped))) }
            })
        }
        .frame(height: 16)
    }
}

/// A clickable row that highlights under the pointer.
private struct MenuBarRowButton<Content: View>: View {
    var height: CGFloat = 24
    var action: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = MenuBarTheme(scheme)
        HStack(spacing: 0) { content }
            .padding(.horizontal, 6)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? t.fill : .clear))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture(perform: action)
            .padding(.horizontal, -6)
    }
}

private struct Hairline: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(MenuBarTheme(scheme).fill2).frame(height: 0.5) }
}

/// The 22 pt column of icons at the start of the rows; labels line up 32 pt from the edge.
private struct RowIcon: View {
    var symbol: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(MenuBarTheme(scheme).text2)
            .frame(width: 22, alignment: .center)
            .padding(.trailing, 10)
    }
}

// MARK: - Layout thumbnails

/// Frames of a layout on the 1440 × 798 canvas the reference uses for thumbnails (gap 40).
private func thumbnailFrames(count: Int, kind: LayoutKind, tall: Bool) -> [CGRect] {
    let canvas = CGRect(x: 0, y: 0, width: 1440, height: 798), gap: CGFloat = 40
    if tall {
        let area = canvas.insetBy(dx: gap, dy: gap)
        let n = CGFloat(max(1, min(count, 3))), h = (area.height - gap * (n - 1)) / n
        return (0..<Int(n)).map { CGRect(x: area.minX, y: area.minY + CGFloat($0) * (h + gap), width: area.width, height: h) }
    }
    return TileLayout.frames(in: canvas, count: count, kind: kind, gap: gap)
}

private struct LayoutThumbnail: View {
    var count: Int
    var kind: LayoutKind
    var tall: Bool
    var color: Color
    var body: some View {
        Canvas { context, size in
            let s = size.width / 1440
            for f in thumbnailFrames(count: count, kind: kind, tall: tall) {
                let rect = CGRect(x: f.minX * s, y: f.minY * s, width: f.width * s, height: f.height * s)
                context.fill(Path(roundedRect: rect, cornerRadius: 60 * s), with: .color(color))
            }
        }
    }
}

/// 22 × 13 glyphs of the segmented control: one big pane and two small, or three columns.
private struct KindGlyph: View {
    var kind: LayoutKind
    var body: some View {
        Canvas { context, size in
            let g: CGFloat = 1.5, r: CGFloat = 1
            var rects: [CGRect] = []
            if kind == .grid {
                let half = (size.width - g) / 2, row = (size.height - g) / 2
                rects = [CGRect(x: 0, y: 0, width: half, height: size.height),
                         CGRect(x: half + g, y: 0, width: half, height: row),
                         CGRect(x: half + g, y: row + g, width: half, height: row)]
            } else {
                let w = (size.width - 2 * g) / 3
                rects = (0..<3).map { CGRect(x: CGFloat($0) * (w + g), y: 0, width: w, height: size.height) }
            }
            for rect in rects { context.fill(Path(roundedRect: rect, cornerRadius: r), with: .foreground) }
        }
        .frame(width: 22, height: 13)
    }
}

// MARK: - Panel

/// Every section sits in one column 12 pt apart, as in the reference.
struct MenuBarPanelView: View {
    @ObservedObject var model: MenuBarModel
    @Environment(\.colorScheme) private var scheme

    private var s: MenuBarSnapshot { model.snapshot }
    private var a: MenuBarActions { model.actions }

    var body: some View {
        let t = MenuBarTheme(scheme)
        VStack(alignment: .leading, spacing: 12) {
            header(t)
            cards
            MenuBarPreview(snapshot: s, reset: a.resetSizes)
                .frame(maxWidth: .infinity)
            windowsSection(t)
            quickToggles
            Hairline()
            switchRow(icon: "squareshape.dotted.squareshape", title: "Clean Space", keys: "⌃⌥P", isOn: s.cleanSpace, enabled: s.enabled, t) { _ in a.toggleCleanSpace() }
            switchRow(icon: "circle.lefthalf.filled", title: "Mode No peek", keys: "⌃⌥D", isOn: s.noPeek, enabled: s.enabled, t) { _ in a.toggleNoPeek() }
            if s.noPeek {
                HStack(spacing: 0) {
                    Text("Intensité").font(.system(size: 12)).foregroundStyle(t.text2)
                        .frame(width: 80, alignment: .leading)
                    MenuBarSlider(value: s.dimAmount, range: 0.1...0.9, step: 0.05, onChange: a.setDim)
                    Text("\(Int((s.dimAmount * 100).rounded()))\u{202F}%")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(t.text2)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.leading, 32)
                .frame(height: 18)
                .transition(.opacity)
            }
            if let app = s.frontApp {
                Hairline()
                HStack(spacing: 0) {
                    Group {
                        if let icon = s.frontAppIcon { Image(nsImage: icon).resizable().interpolation(.high) }
                        else { Image(systemName: "app.dashed").font(.system(size: 16)).foregroundStyle(t.text2) }
                    }
                    .frame(width: 22, height: 22).padding(.trailing, 10)
                    Text("Ranger \(app)").font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    MenuBarSwitch(isOn: s.frontAppTiled, action: a.setFrontAppTiled)
                }
            }
            Hairline()
            MenuBarRowButton(action: a.openSettings) {
                RowIcon(symbol: "sun.min")
                Text("Réglages").font(.system(size: 13))
                Spacer()
                Text("⌘,").font(.system(size: 12)).foregroundStyle(t.text3)
            }
            MenuBarRowButton(action: a.showKeyboard) {
                RowIcon(symbol: "command")
                Text("Raccourcis clavier").font(.system(size: 13))
                Spacer()
                if !s.shortcutsEnabled {
                    Text("Désactivés").font(.system(size: 11, weight: .medium)).foregroundStyle(t.text2)
                        .padding(.horizontal, 6).frame(height: 17)
                        .background(Capsule().fill(t.fill2))
                        .padding(.trailing, 6)
                } else if !s.shortcutIssue.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(rgb(0xFF9F0A))
                        .padding(.trailing, 6)
                        .help(s.shortcutIssue)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(t.text3)
            }
            Hairline()
            MenuBarRowButton(height: 22, action: a.quit) {
                Image(systemName: "power").font(.system(size: 11, weight: .medium)).padding(.trailing, 5)
                Text("Quitter Mosaïque").font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(t.text2)
        }
        .padding(14)
        .frame(width: 324, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(t.text)
    }

    // MARK: Header
    private func header(_ t: MenuBarTheme) -> some View {
        HStack(alignment: .center, spacing: 10) {
            MenuBarGlyphView(filled: s.status == .active, size: 22)
                .foregroundStyle(t.text)
            VStack(alignment: .leading, spacing: 5) {
                Text("Mosaïque").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(dotColor(t)).frame(width: 7, height: 7)
                    Text(s.statusLine).font(.system(size: 12)).foregroundStyle(t.text2)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 6)
            MenuBarSwitch(isOn: s.autoTiling, action: a.setAutomaticTiling)
                .help("Rangement automatique")
                .accessibilityLabel("Rangement automatique")
        }
        .frame(height: 42)
    }
    private func dotColor(_ t: MenuBarTheme) -> Color {
        switch s.status {
        case .active: return rgb(0x34C759)
        case .paused: return rgb(0xFF9F0A)
        case .off: return t.text3
        case .attention: return rgb(0xFF3B30)
        }
    }

    // MARK: Cards
    @ViewBuilder private var cards: some View {
        if !s.trusted {
            MenuBarCard(style: .attention, text: "Mosaïque a besoin de l’accès Accessibilité pour ranger les fenêtres.",
                        button: "Autoriser l’accès", action: a.grantAccess)
        } else if !s.setupDone {
            MenuBarCard(style: .warning, text: "Mosaïque attend pour ranger ce bureau.", button: "Ranger", action: a.tidy)
        }
        if s.secureInput {
            MenuBarCard(style: .neutral, text: "Une autre app utilise la saisie sécurisée (un champ de mot de passe, par exemple). Les raccourcis sont en pause jusqu’à la fin.",
                        button: nil, action: {})
        }
        if s.shortcutsEnabled && !s.shortcutIssue.isEmpty {
            MenuBarCard(style: .warning, text: s.shortcutIssue, button: "Voir", action: a.showKeyboard)
        }
    }

    // MARK: Windows on this screen
    private func windowsSection(_ t: MenuBarTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fenêtres sur cet écran").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.text2)
            HStack(spacing: 0) {
                ForEach(LayoutKind.allCases) { kind in
                    let on = s.kind == kind && !s.tall
                    HStack(spacing: 7) {
                        KindGlyph(kind: kind).foregroundStyle(t.glyph)
                        Text(kind.label).font(.system(size: 12.5))
                    }
                    .frame(maxWidth: .infinity).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? t.solid : .clear)
                        .shadow(color: .black.opacity(on ? 0.15 : 0), radius: 1, y: 1)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? t.edge : .clear, lineWidth: 0.5)))
                    .contentShape(Rectangle())
                    .onTapGesture { if !s.tall && s.kind != kind { a.setKind(kind) } }
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.fill))
            .opacity(s.tall ? 0.45 : 1)
            .animation(.easeOut(duration: 0.15), value: s.kind)

            HStack(spacing: 7) {
                ForEach(1...4, id: \.self) { n in
                    let disabled = n > s.maxCount
                    let on = min(s.capacity, s.maxCount) == n
                    VStack(spacing: 5) {
                        LayoutThumbnail(count: n, kind: s.kind, tall: s.tall, color: on ? t.accent : t.thumb)
                            .frame(width: 47, height: 26)
                        Text("\(n)").font(.system(size: 12.5).monospacedDigit())
                            .foregroundStyle(on ? t.accent : t.text)
                    }
                    .frame(maxWidth: .infinity).frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? t.accent.opacity(0.12) : t.fill))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(on ? t.accent : .clear, lineWidth: 1.5))
                    .opacity(disabled ? 0.35 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture { if !disabled && !on { a.setCapacity(n) } }
                    .accessibilityLabel(n == 1 ? "1 fenêtre" : "Jusqu’à \(n) fenêtres")
                }
            }
            .animation(.easeOut(duration: 0.15), value: s.capacity)
            if s.kind == .columns && !s.tall && s.columnCapacity < 4 {
                Text("Cet écran tient \(s.columnCapacity) colonne\(s.columnCapacity > 1 ? "s" : ""). Choisis Grille pour quatre.")
                    .font(.system(size: 11)).foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: Quick toggles
    private var quickToggles: some View {
        HStack(spacing: 6) {
            MenuBarToggleTile(title: "Réorganiser", symbol: "arrow.clockwise", on: false, enabled: s.enabled, momentary: true, action: a.retile)
            MenuBarToggleTile(title: "Bordures", symbol: "square.inset.filled", on: s.bordersOn, enabled: true, momentary: false, action: a.toggleBorders)
            MenuBarToggleTile(title: "Focus au survol", symbol: "cursorarrow.rays", on: s.hoverFocus, enabled: true, momentary: false, action: a.toggleHoverFocus)
        }
    }

    private func switchRow(icon: String, title: String, keys: String, isOn: Bool, enabled: Bool, _ t: MenuBarTheme, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 0) {
            Group {
                RowIcon(symbol: icon)
                Text(title).font(.system(size: 13)).lineLimit(1)
                Text(keys).font(.system(size: 11)).foregroundStyle(t.text3).padding(.leading, 10)
            }
            .opacity(enabled ? 1 : 0.5)
            Spacer(minLength: 8)
            MenuBarSwitch(isOn: isOn, enabled: enabled, action: action)
        }
        .frame(height: 19)
    }
}

// MARK: - Cards

struct MenuBarCard: View {
    enum Style { case warning, attention, neutral }
    var style: Style
    var text: String
    var button: String?
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = MenuBarTheme(scheme)
        let dark = t.dark
        let (fg, bg, tint): (Color, Color, Color) = {
            switch style {
            case .warning: return (dark ? rgb(0xFFB340) : rgb(0x9A5B00), rgb(0xFF9F0A, dark ? 0.16 : 0.13), rgb(0xFF9F0A))
            case .attention: return (dark ? rgb(0xFF6961) : rgb(0xB3261E), rgb(0xFF3B30, dark ? 0.16 : 0.11), rgb(0xFF3B30))
            case .neutral: return (t.text2, t.fill, t.text2)
            }
        }()
        HStack(alignment: .center, spacing: 10) {
            Text(text).font(.system(size: 12)).foregroundStyle(fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let button {
                Text(button).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: action)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg))
    }
}

// MARK: - Quick toggle tile

/// Radius 10, 11 pt label under a small icon; on = accent 17 % with accent text.
private struct MenuBarToggleTile: View {
    var title: String
    var symbol: String
    var on: Bool
    var enabled: Bool
    var momentary: Bool
    var action: () -> Void
    @State private var flash = false
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = MenuBarTheme(scheme)
        let lit = on || flash
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13, weight: .regular)).frame(height: 15)
            Text(title).font(.system(size: 11.5)).lineLimit(1).minimumScaleFactor(0.85)
        }
        .foregroundStyle(lit ? t.accent : t.text)
        .frame(maxWidth: .infinity).frame(height: 51)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? t.accent.opacity(0.17) : (hover ? t.fill2 : t.fill)))
        .animation(.easeOut(duration: 0.12), value: lit)
        .opacity(enabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { hover = $0 && enabled }
        .onTapGesture {
            guard enabled else { return }
            if momentary {
                flash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { flash = false }
            }
            action()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Layout preview

/// The screen under the pointer, 292 pt wide: bare panes on the glass, no frame around them.
struct MenuBarPreview: View {
    var snapshot: MenuBarSnapshot
    var reset: () -> Void
    @State private var ripple = 0
    @Environment(\.colorScheme) private var scheme

    private let width: CGFloat = 292
    private var signature: String {
        snapshot.panes.map { "\($0.id):\($0.unit.debugDescription):\($0.active):\($0.stackCount):\($0.focus)" }.joined(separator: "|")
    }

    var body: some View {
        let t = MenuBarTheme(scheme)
        let message = snapshot.previewMessage
        let aspect = max(0.2, snapshot.screenSize.height / max(1, snapshot.screenSize.width))
        let height = message == nil ? (width * aspect).rounded() : 56
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: width, height: height)
            if let message {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.fill)
                Text(message).font(.system(size: 12)).foregroundStyle(t.text2)
                    .multilineTextAlignment(.center)
                    .frame(width: width, height: height)
            } else {
                ForEach(snapshot.panes) { pane in
                    let rect = CGRect(x: pane.unit.minX * width, y: pane.unit.minY * height, width: pane.unit.width * width, height: pane.unit.height * height)
                        .insetBy(dx: 2, dy: 2)
                    MenuBarPaneView(pane: pane, size: rect.size, dimmed: snapshot.focusActive && !pane.focus, ripple: pane.active ? ripple : 0)
                        .frame(width: max(0, rect.width), height: max(0, rect.height))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .bottomTrailing) {
            if message == nil && snapshot.customSizes {
                Text("Réinitialiser les tailles")
                    .font(.system(size: 12)).foregroundStyle(t.text)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.solid).shadow(color: .black.opacity(0.18), radius: 2, y: 1))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.edge, lineWidth: 0.5))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: reset)
                    .padding(.trailing, 2)
                    .transition(.opacity)
            }
        }
        .animation(paneCurve, value: signature)
        .animation(paneCurve, value: height)
        .onChange(of: signature) { old, new in if !old.isEmpty && !new.isEmpty { ripple += 1 } }
    }
}

private struct MenuBarPaneView: View {
    var pane: PreviewPane
    var size: CGSize
    var dimmed: Bool
    var ripple: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = MenuBarTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        ZStack {
            shape.fill(t.dark ? rgb(0xFFFFFF, 0.05) : rgb(0xFFFFFF, 0.55))
            if pane.active { shape.fill(t.accent.opacity(0.1)) }
            if ripple > 0 { MenuBarRipple(color: t.accent).id(ripple) }
            VStack(spacing: 4) {
                if size.width >= 30 && size.height >= 26, let icon = pane.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                if size.width >= 56 && size.height >= 44 {
                    Text(pane.app).font(.system(size: 10)).foregroundStyle(t.text2).lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(pane.active ? t.accent : t.paneLine, lineWidth: pane.active ? 1.5 : 1))
        .overlay(alignment: .topTrailing) {
            if pane.stackCount > 1 {
                Text("\(pane.stackCount)").font(.system(size: 9.5, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14, maxHeight: 14)
                    .background(Capsule().fill(rgb(0xFF9500)))
                    .padding(4)
            }
        }
        .overlay(alignment: .topLeading) {
            if pane.focus {
                Text("Focus").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).frame(height: 14)
                    .background(Capsule().fill(t.accent))
                    .padding(4)
            }
        }
        .opacity(dimmed ? 0.35 : 1)
    }
}

/// "pv-wave": a 12 pt ring that grows from 0.4 to 14 times its size and fades out over 1.1 s.
private struct MenuBarRipple: View {
    var color: Color
    @State private var grown = false
    var body: some View {
        Circle().strokeBorder(color, lineWidth: 1.5)
            .frame(width: 12, height: 12)
            .scaleEffect(grown ? 14 : 0.4)
            .opacity(grown ? 0 : 0.9)
            .onAppear { withAnimation(.easeOut(duration: 1.1)) { grown = true } }
            .allowsHitTesting(false)
    }
}
