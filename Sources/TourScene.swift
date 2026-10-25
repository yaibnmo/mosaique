import SwiftUI
import AppKit

// Miniature desktop used by every demo of the welcome tour. Everything is drawn here in SwiftUI:
// no artwork. The desktop is a 320×200 unit canvas scaled to the view, so a scene reads the same
// on a small card and in the large demo.

extension Color {
    init(tourHex hex: UInt32, _ alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
    static let tourOrange = Color(tourHex: 0xFF9500)
    static var tourAccent: Color { Color(nsColor: .controlAccentColor) }
}

extension Animation {
    /// The reference window spring: bounce 0.16, 0.62 s.
    static let tourWindow = Animation.spring(response: 0.45, dampingFraction: 0.84)
    static let tourCursor = Animation.easeInOut(duration: 0.55)
    static let tourQuick = Animation.easeOut(duration: 0.14)
    static let tourFade = Animation.easeInOut(duration: 0.3)
    /// Clean Space panels: 0.38 s, cubic-bezier(0.4, 0, 0.2, 1).
    static let tourClean = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)
    /// Glow line and layout preview panes: 0.5 s, cubic-bezier(0.32, 0.72, 0, 1).
    static let tourGlide = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.5)
}

// MARK: Apps shown in the demos

enum TourApp: CaseIterable {
    case notes, safari, terminal, mail, music, messages
    var color: Color {
        switch self {
        case .notes: return Color(tourHex: 0xFFC400)
        case .safari: return Color(tourHex: 0x0A84FF)
        case .terminal: return Color(tourHex: 0x32D74B)
        case .mail: return Color(tourHex: 0x2F80ED)
        case .music: return Color(tourHex: 0xFA2D48)
        case .messages: return Color(tourHex: 0x34C759)
        }
    }
    var name: String {
        switch self {
        case .notes: return "Notes"; case .safari: return "Safari"; case .terminal: return "Terminal"
        case .mail: return "Mail"; case .music: return "Musique"; case .messages: return "Messages"
        }
    }
    var symbol: String {
        switch self {
        case .notes: return "note.text"; case .safari: return "safari.fill"; case .terminal: return "apple.terminal.fill"
        case .mail: return "envelope.fill"; case .music: return "music.note"; case .messages: return "message.fill"
        }
    }
}

// MARK: Geometry (units of the 320×200 canvas)

enum TourGeo {
    static let size = CGSize(width: 320, height: 200)
    static let menuHeight: CGFloat = 9
    static let gap: CGFloat = 4
    /// Usable area: below the menu bar, above the Dock.
    static let area = CGRect(x: 0, y: 9, width: 320, height: 170)
    static var inner: CGRect { area.insetBy(dx: gap, dy: gap) }

    /// Grid ("fold") and Columns frames, as in the engine: 4 windows go clockwise from top-left.
    static func tiles(_ count: Int, kind: LayoutKind = .grid, ratio: CGFloat = 0.5) -> [CGRect] {
        let i = inner, g = gap, n = max(1, count)
        guard n > 1 else { return [i] }
        if kind == .columns {
            let w = (i.width - g * CGFloat(n - 1)) / CGFloat(n)
            return (0..<n).map { CGRect(x: i.minX + CGFloat($0) * (w + g), y: i.minY, width: w, height: i.height) }
        }
        let lw = ((i.width - g) * ratio).rounded()
        let left = CGRect(x: i.minX, y: i.minY, width: lw, height: i.height)
        let right = CGRect(x: i.minX + lw + g, y: i.minY, width: i.width - lw - g, height: i.height)
        if n == 2 { return [left, right] }
        let th = ((i.height - g) * 0.5).rounded()
        let tr = CGRect(x: right.minX, y: right.minY, width: right.width, height: th)
        let br = CGRect(x: right.minX, y: right.minY + th + g, width: right.width, height: right.height - th - g)
        if n == 3 { return [left, tr, br] }
        let tl = CGRect(x: left.minX, y: left.minY, width: left.width, height: th)
        let bl = CGRect(x: left.minX, y: left.minY + th + g, width: left.width, height: left.height - th - g)
        return [tl, tr, br, bl]
    }
    static var full: CGRect { inner }
    /// Floating window: centred, 60 % × 75 % of the inset area.
    static var floating: CGRect {
        let w = (inner.width * 0.6).rounded(), h = (inner.height * 0.75).rounded()
        return CGRect(x: inner.midX - w / 2, y: inner.midY - h / 2, width: w, height: h)
    }
    static func grip(_ f: CGRect, floating: Bool = false) -> CGPoint { CGPoint(x: f.midX, y: floating ? f.minY - 1.4 : f.minY - gap / 2) }

    // Hover bar (slightly larger than the real 440×54 ratio so its labels stay readable).
    static let barSize = CGSize(width: 132, height: 17)
    static let stackRow: CGFloat = 11
    static func bar(_ f: CGRect, stack: Bool, floating: Bool) -> CGRect {
        let p = grip(f, floating: floating), h = barSize.height + (stack ? stackRow : 0)
        let x = min(max(p.x - barSize.width / 2, area.minX + 1.5), area.maxX - barSize.width - 1.5)
        let y = min(max(p.y - h / 2, area.minY + 1.5), area.maxY - h - 1.5)
        return CGRect(x: x, y: y, width: barSize.width, height: h)
    }
    static func barButton(_ index: Int, frame f: CGRect, stack: Bool = false, floating: Bool = false) -> CGPoint {
        let r = bar(f, stack: stack, floating: floating)
        let w = (r.width - 2) / 3
        return CGPoint(x: r.minX + 1 + (CGFloat(index) + 0.5) * w, y: r.maxY - barSize.height / 2)
    }
    static let chipWidth: CGFloat = 30
    static func barChip(_ index: Int, frame f: CGRect, floating: Bool = false) -> CGPoint {
        let r = bar(f, stack: true, floating: floating)
        return CGPoint(x: r.minX + 8 + CGFloat(index) * (chipWidth + 1) + chipWidth / 2, y: r.minY + stackRow / 2 + 0.5)
    }
    /// Orange marks of a stacked tile, centred on the grip point.
    static func marks(count: Int, shown: Int, at p: CGPoint) -> [CGRect] {
        let on: CGFloat = 6, off: CGFloat = 2.6, h: CGFloat = 1.5, sp: CGFloat = 1.2
        let total = on + CGFloat(count - 1) * (off + sp)
        var x = p.x - total / 2
        return (0..<count).map { i in
            let w = i == shown ? on : off
            defer { x += w + sp }
            return CGRect(x: x, y: p.y - h / 2, width: w, height: h)
        }
    }

    // Menu bar panel.
    static let menuIcon = CGPoint(x: 287, y: 4.5)
    static let panel = CGRect(x: 232, y: 10.5, width: 84, height: 64)
    static func panelCount(_ n: Int) -> CGPoint { CGPoint(x: panel.minX + 6 + 8 + CGFloat(n - 1) * 18.5, y: panel.minY + 22) }
    static let panelCleanRow = CGPoint(x: panel.maxX - 9, y: panel.minY + 36)
    static let panelNoPeekRow = CGPoint(x: panel.maxX - 9, y: panel.minY + 45)

    // Tab View.
    static let tabPanel = CGRect(x: 82, y: 32, width: 156, height: 108)
    static var tabMap: CGRect { CGRect(x: tabPanel.minX + 8, y: tabPanel.minY + 16, width: 140, height: (140 * area.height / area.width).rounded()) }
    static func tabTile(_ f: CGRect) -> CGRect {
        let m = tabMap, sx = m.width / area.width, sy = m.height / area.height
        return CGRect(x: m.minX + (f.minX - area.minX) * sx, y: m.minY + (f.minY - area.minY) * sy, width: f.width * sx, height: f.height * sy).insetBy(dx: 0.9, dy: 0.9)
    }
}

// MARK: Scene state

struct TourWin: Identifiable {
    let id: Int
    var app: TourApp
    var frame: CGRect
    var z: Double = 1
    var floating = false
}

struct TourDemoState {
    var wins: [TourWin] = []
    var active: Int?
    var highlight = "active"
    var grip = true
    var stackCount = 1
    var stackShown = 0
    var stackApps: [TourApp] = []
    var bar = false
    var barStack = false
    var barHot: Int?
    var chipHot: Int?
    var focused = false
    var cursor: CGPoint?
    var pressing = false
    var badge: String?
    var dragging = false
    var keys: [String] = []
    var keysDown = false
    var caption: String?
    var veil = 0.0
    var cleanMeet: CGFloat?
    var cleanOn = false
    var tab = false
    var tabPick: Int?
    var drop: Int?
    var dropLabel: String?
    var toast: String?
    var focusTag = false
    var panel = false
    var panelHot: String?
    var panelOn: Set<String> = []
    var panelCount = 3
    var divider: CGPoint?
    var band: CGFloat?
    var rings: Set<Int> = []
    var activity: Int?
    var activityMouse = false

    func frame(_ id: Int) -> CGRect { wins.first { $0.id == id }?.frame ?? .zero }
    var activeFrame: CGRect? { active.map(frame) }
    var activeWin: TourWin? { wins.first { $0.id == active } }
    mutating func set(_ id: Int, _ f: CGRect) { if let i = wins.firstIndex(where: { $0.id == id }) { wins[i].frame = f } }
    mutating func raise(_ id: Int) {
        let top = (wins.map(\.z).max() ?? 0) + 1
        if let i = wins.firstIndex(where: { $0.id == id }) { wins[i].z = top }
        active = id
    }
    /// Lays out the given windows in order, like the engine's tile order.
    mutating func layout(_ ids: [Int], kind: LayoutKind = .grid, ratio: CGFloat = 0.5) {
        let frames = TourGeo.tiles(ids.count, kind: kind, ratio: ratio)
        for (id, f) in zip(ids, frames) { set(id, f) }
    }
    mutating func swap(_ a: Int, _ b: Int) { let fa = frame(a); set(a, frame(b)); set(b, fa) }
    mutating func add(_ id: Int, _ app: TourApp, _ f: CGRect) {
        wins.append(TourWin(id: id, app: app, frame: f, z: (wins.map(\.z).max() ?? 0) + 1)); active = id
    }
    mutating func remove(_ id: Int) { wins.removeAll { $0.id == id }; if active == id { active = wins.max { $0.z < $1.z }?.id } }
    mutating func setFloating(_ id: Int, _ on: Bool) { if let i = wins.firstIndex(where: { $0.id == id }) { wins[i].floating = on } }

    /// Three windows: Notes on the left, Safari top right, Terminal bottom right.
    static func base(active: Int = 1) -> TourDemoState {
        let t = TourGeo.tiles(3)
        var s = TourDemoState()
        s.wins = [TourWin(id: 1, app: .notes, frame: t[0], z: 1), TourWin(id: 2, app: .safari, frame: t[1], z: 2), TourWin(id: 3, app: .terminal, frame: t[2], z: 3)]
        s.raise(active)
        return s
    }
}

// MARK: Scene view

struct TourScene: View {
    let state: TourDemoState
    var corner: CGFloat = 10
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / TourGeo.size.width
            content(s: s).frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .aspectRatio(TourGeo.size.width / TourGeo.size.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Color.black.opacity(scheme == .dark ? 0.5 : 0.12), lineWidth: 0.5))
    }

    private var dark: Bool { scheme == .dark }

    @ViewBuilder private func content(s: CGFloat) -> some View {
        let detailed = s >= 1.45
        let activeZ = state.activeWin?.z ?? 0
        ZStack(alignment: .topLeading) {
            wallpaper
            ForEach(state.wins) { w in
                let isActive = w.id == state.active
                TourMiniWindow(app: w.app, s: s, border: border(for: w), ring: state.rings.contains(w.id), detailed: detailed)
                    .blur(radius: !isActive && state.veil > 0 ? 1.2 * s : 0)
                    .overlay(dropHighlight(w, s: s))
                    .frame(width: w.frame.width * s, height: w.frame.height * s)
                    .position(x: w.frame.midX * s, y: w.frame.midY * s)
                    .zIndex(w.z)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9)).animation(.easeOut(duration: 0.28)),
                                            removal: .opacity.combined(with: .scale(scale: 0.9)).animation(.easeInOut(duration: 0.2))))
            }
            Color.black.opacity(state.veil).allowsHitTesting(false).zIndex(activeZ - 0.5)
            cleanPanels(s: s).zIndex(activeZ - 0.4)
            overlays(s: s, detailed: detailed).zIndex(600)
            menuBar(s: s).zIndex(900)
            dock(s: s).zIndex(900)
            if let band = state.band { sweepBand(band, s: s).zIndex(950) }
            if state.panel { TourMiniPanel(state: state, s: s, detailed: detailed).transition(.opacity.combined(with: .offset(y: -3 * s))).zIndex(960) }
            if state.tab { TourMiniTabView(state: state, s: s, detailed: detailed).transition(.opacity.combined(with: .scale(scale: 0.97))).zIndex(970) }
            if let n = state.activity { TourMiniActivity(count: n, mouse: state.activityMouse, s: s).zIndex(975) }
            if let toast = state.toast { toastView(toast, s: s).transition(.opacity.combined(with: .offset(y: 4 * s))).zIndex(980) }
            if !state.keys.isEmpty { keyHUD(s: s, detailed: detailed).transition(.opacity.combined(with: .offset(y: 4 * s))).zIndex(990) }
            if let c = state.cursor { cursor(at: c, s: s).zIndex(1000) }
        }
    }

    private func border(for w: TourWin) -> Bool {
        guard !w.floating, !state.cleanOn else { return false }
        switch state.highlight {
        case "all": return true
        case "active": return w.id == state.active
        default: return false
        }
    }

    private var wallpaper: some View {
        LinearGradient(colors: dark ? [Color(tourHex: 0x1E2246), Color(tourHex: 0x3A2754), Color(tourHex: 0x5B2E45)]
                                    : [Color(tourHex: 0xB7C6F4), Color(tourHex: 0xD6C2EE), Color(tourHex: 0xF4CDB6)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder private func menuBar(s: CGFloat) -> some View {
        let h = TourGeo.menuHeight * s
        ZStack(alignment: .topLeading) {
            Rectangle().fill(dark ? Color.black.opacity(0.28) : Color.white.opacity(0.42)).frame(height: h)
            let ink = dark ? Color.white.opacity(0.75) : Color.black.opacity(0.62)
            HStack(spacing: 4 * s) {
                Circle().fill(ink).frame(width: 3.2 * s, height: 3.2 * s)
                RoundedRectangle(cornerRadius: 0.6 * s).fill(ink).frame(width: 12 * s, height: 2 * s)
                ForEach(0..<4, id: \.self) { i in RoundedRectangle(cornerRadius: 0.6 * s).fill(ink.opacity(0.6)).frame(width: CGFloat([8, 7, 9, 6][i]) * s, height: 1.8 * s) }
            }
            .frame(height: h).padding(.leading, 6 * s)
            HStack(spacing: 5 * s) {
                ZStack {
                    if state.panel { RoundedRectangle(cornerRadius: 1.2 * s).fill(ink.opacity(0.2)).frame(width: 9 * s, height: 6.6 * s) }
                    TourLogo(filled: true).fill(ink).frame(width: 5.4 * s, height: 5 * s)
                }
                .frame(width: 9 * s)
                RoundedRectangle(cornerRadius: 0.6 * s).fill(ink.opacity(0.6)).frame(width: 7 * s, height: 1.8 * s)
                RoundedRectangle(cornerRadius: 0.6 * s).fill(ink).frame(width: 14 * s, height: 2 * s)
            }
            .frame(width: TourGeo.size.width * s - 6 * s, height: h, alignment: .trailing)
        }
        .frame(width: TourGeo.size.width * s, height: h, alignment: .topLeading)
    }

    @ViewBuilder private func dock(s: CGFloat) -> some View {
        let apps: [TourApp] = [.safari, .mail, .notes, .music, .messages, .terminal]
        HStack(spacing: 2 * s) {
            ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                RoundedRectangle(cornerRadius: 2.2 * s, style: .continuous).fill(app.color.gradient).frame(width: 10 * s, height: 10 * s)
                    .overlay(Image(systemName: app.symbol).font(.system(size: 5.2 * s, weight: .semibold)).foregroundStyle(.white))
            }
        }
        .padding(2 * s)
        .background(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).fill(dark ? Color.white.opacity(0.14) : Color.white.opacity(0.38)))
        .position(x: TourGeo.size.width / 2 * s, y: (TourGeo.size.height - 9.5) * s)
    }

    @ViewBuilder private func cleanPanels(s: CGFloat) -> some View {
        let color = Color(tourHex: 0x2A2A2D)
        let meet = state.cleanMeet ?? 0
        let lw = state.cleanMeet == nil ? 0 : meet + 1
        let rw = state.cleanMeet == nil ? 0 : TourGeo.size.width - meet
        ZStack(alignment: .topLeading) {
            color.frame(width: lw * s, height: TourGeo.size.height * s).position(x: lw * s / 2, y: TourGeo.size.height * s / 2)
            color.frame(width: rw * s, height: TourGeo.size.height * s).position(x: (TourGeo.size.width - rw / 2) * s, y: TourGeo.size.height * s / 2)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func dropHighlight(_ w: TourWin, s: CGFloat) -> some View {
        if state.drop == w.id {
            let r = max(2.5, 3.4 * s)
            ZStack {
                RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color.tourAccent.opacity(0.24))
                RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color.tourAccent, lineWidth: max(1.5, 0.8 * s))
                if let label = state.dropLabel {
                    Text(label).font(.system(size: max(7, 3.4 * s), weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, max(5, 3 * s)).padding(.vertical, max(2.5, 1.5 * s))
                        .background(RoundedRectangle(cornerRadius: max(4, 2 * s)).fill(Color.tourAccent)).shadow(color: .black.opacity(0.25), radius: 3 * s, y: 1.5 * s)
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private func overlays(s: CGFloat, detailed: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let w = state.activeWin, state.highlight == "glow", !w.floating, !state.cleanOn, !state.tab {
                let f = w.frame
                Capsule().fill(Color.tourAccent)
                    .frame(width: f.width * 0.8 * s, height: max(2, 0.8 * s))
                    .shadow(color: Color.tourAccent.opacity(0.7), radius: max(2, 2.2 * s))
                    .position(x: f.midX * s, y: (f.minY - TourGeo.gap / 2) * s)
            }
            if let w = state.activeWin, state.grip, !state.cleanOn, !state.tab, !state.dragging {
                gripView(w, s: s)
            }
            if let w = state.activeWin, state.bar, !state.cleanOn {
                TourMiniBar(state: state, frame: w.frame, floating: w.floating, s: s, detailed: detailed)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(.easeOut(duration: 0.14)),
                                            removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).animation(.easeOut(duration: 0.12))))
            }
            if let w = state.activeWin, state.focusTag {
                Text("Focus · ⌃⌥Z pour la remettre").font(.system(size: max(6.5, 3 * s), weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, max(5, 2.6 * s)).padding(.vertical, max(2, 1.1 * s))
                    .background(Capsule().fill(Color(tourHex: 0x18181C, 0.78)))
                    .fixedSize()
                    .position(x: w.frame.midX * s, y: (w.frame.maxY - (state.keys.isEmpty ? 6 : 26)) * s)
                    .transition(.opacity)
            }
            if let d = state.divider {
                Capsule().fill(Color.white.opacity(0.95)).frame(width: max(3, 1.3 * s), height: max(14, 11 * s))
                    .shadow(color: .black.opacity(0.3), radius: 2 * s)
                    .position(x: d.x * s, y: d.y * s)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func gripView(_ w: TourWin, s: CGFloat) -> some View {
        let p = TourGeo.grip(w.frame, floating: w.floating)
        if state.stackCount > 1 {
            ForEach(Array(TourGeo.marks(count: state.stackCount, shown: state.stackShown, at: p).enumerated()), id: \.offset) { i, m in
                RoundedRectangle(cornerRadius: max(1, 0.6 * s)).fill(i == state.stackShown ? Color.tourOrange : Color.tourOrange.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: max(1, 0.6 * s)).strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
                    .frame(width: max(m.width * s, i == state.stackShown ? 9 : 4), height: max(2.5, m.height * s))
                    .shadow(color: .black.opacity(0.3), radius: 1.2)
                    .position(x: m.midX * s, y: m.midY * s)
            }
        } else {
            let near = state.bar || (state.cursor.map { hypot($0.x - p.x, $0.y - p.y) < 8 } ?? false)
            Capsule().fill(Color.white.opacity(0.96))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
                .frame(width: max(near ? 15 : 11, (near ? 9.8 : 7.1) * s), height: max(2.5, 1.2 * s))
                .opacity(near ? 1 : 0.55)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                .position(x: p.x * s, y: p.y * s)
                .animation(.easeOut(duration: 0.15), value: near)
        }
    }

    private func sweepBand(_ x: CGFloat, s: CGFloat) -> some View {
        let w = TourGeo.size.width * 0.32
        return LinearGradient(colors: [.white.opacity(0), .white.opacity(0.28), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
            .frame(width: w * s, height: TourGeo.size.height * s)
            .position(x: x * s, y: TourGeo.size.height / 2 * s)
            .allowsHitTesting(false)
    }

    private func toastView(_ text: String, s: CGFloat) -> some View {
        Text(text).font(.system(size: max(7.5, 3.6 * s), weight: .medium)).foregroundStyle(Color(tourHex: 0xF5F5F7))
            .multilineTextAlignment(.center).lineLimit(2)
            .padding(.horizontal, max(7, 4 * s)).padding(.vertical, max(4, 2.2 * s))
            .background(RoundedRectangle(cornerRadius: max(6, 3.5 * s), style: .continuous).fill(Color(tourHex: 0x26262A, 0.94)))
            .shadow(color: .black.opacity(0.3), radius: 4 * s, y: 2 * s)
            .frame(maxWidth: TourGeo.size.width * 0.8 * s)
            .position(x: TourGeo.size.width / 2 * s, y: (TourGeo.area.maxY - 16) * s)
    }

    @ViewBuilder private func keyHUD(s: CGFloat, detailed: Bool) -> some View {
        let cap = max(15, 9 * s)
        HStack(spacing: max(6, 3 * s)) {
            HStack(spacing: max(2.5, 1.2 * s)) {
                ForEach(Array(state.keys.enumerated()), id: \.offset) { _, key in
                    Text(key).font(.system(size: cap * 0.5, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        .frame(minWidth: cap, minHeight: cap).padding(.horizontal, key.count > 1 ? cap * 0.2 : 0)
                        .background(RoundedRectangle(cornerRadius: cap * 0.24, style: .continuous).fill(state.keysDown ? Color.tourAccent : Color.white.opacity(0.16)))
                        .scaleEffect(state.keysDown ? 0.92 : 1)
                }
            }
            if detailed, let caption = state.caption {
                Text(caption).font(.system(size: max(9, 4 * s), weight: .medium)).foregroundStyle(Color(tourHex: 0xEBEBF5, 0.85)).fixedSize()
            }
        }
        .padding(max(4, 2.2 * s))
        .padding(.horizontal, max(1, 0.6 * s))
        .background(RoundedRectangle(cornerRadius: max(7, 4 * s), style: .continuous).fill(Color(tourHex: 0x222226, 0.9)))
        .shadow(color: .black.opacity(0.3), radius: 4 * s, y: 2 * s)
        .fixedSize()
        .position(x: TourGeo.size.width / 2 * s, y: (TourGeo.area.maxY - 15) * s)
    }

    @ViewBuilder private func cursor(at p: CGPoint, s: CGFloat) -> some View {
        let size = max(11, 7 * s)
        ZStack(alignment: .topLeading) {
            TourCursorShape().fill(Color.black).frame(width: size * 0.72, height: size)
                .overlay(TourCursorShape().stroke(Color.white, lineWidth: max(1, size * 0.08)))
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .scaleEffect(state.pressing ? 0.86 : 1, anchor: .topLeading)
            if let badge = state.badge {
                Text(badge).font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, size * 0.22).padding(.vertical, size * 0.06)
                    .background(Capsule().fill(Color.tourAccent))
                    .offset(x: size * 0.75, y: size * 0.75)
                    .fixedSize()
            }
        }
        .frame(width: size * 2, height: size * 2, alignment: .topLeading)
        .position(x: p.x * s + size, y: p.y * s + size)
    }
}

// MARK: Pieces

/// The Mosaïque mark: four panes (our own drawing).
struct TourLogo: Shape {
    var filled = true
    func path(in r: CGRect) -> Path {
        let g = r.width * 0.1, w1 = (r.width - g) * 0.6, w2 = r.width - g - w1, h = (r.height - g) / 2, c = min(r.width, r.height) * 0.14
        var p = Path()
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY, width: w1, height: h), cornerSize: CGSize(width: c, height: c))
        p.addRoundedRect(in: CGRect(x: r.minX + w1 + g, y: r.minY, width: w2, height: h), cornerSize: CGSize(width: c, height: c))
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY + h + g, width: w2, height: h), cornerSize: CGSize(width: c, height: c))
        p.addRoundedRect(in: CGRect(x: r.minX + w2 + g, y: r.minY + h + g, width: w1, height: h), cornerSize: CGSize(width: c, height: c))
        return p
    }
}

struct TourCursorShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.8))
        p.addLine(to: CGPoint(x: r.minX + w * 0.27, y: r.minY + h * 0.6))
        p.addLine(to: CGPoint(x: r.minX + w * 0.45, y: r.minY + h * 0.98))
        p.addLine(to: CGPoint(x: r.minX + w * 0.62, y: r.minY + h * 0.9))
        p.addLine(to: CGPoint(x: r.minX + w * 0.45, y: r.minY + h * 0.54))
        p.addLine(to: CGPoint(x: r.minX + w, y: r.minY + h * 0.54))
        p.closeSubpath()
        return p
    }
}

struct TourAppIcon: View {
    let app: TourApp
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(app.color.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: app.symbol).font(.system(size: size * 0.55, weight: .semibold)).foregroundStyle(.white))
    }
}

/// A miniature app window: rounded corners, a title bar with traffic lights, and app-coloured content.
struct TourMiniWindow: View {
    let app: TourApp
    let s: CGFloat
    var border = false
    var ring = false
    var detailed = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let r = max(2.5, 3.4 * s)
        let titleH = max(4, 6.2 * s)
        let bg = app == .terminal ? Color(tourHex: 0x1C1C1F) : (dark ? Color(tourHex: 0x2B2B30) : Color.white)
        let bw = max(1.5, 0.9 * s)
        VStack(spacing: 0) {
            HStack(spacing: max(1.2, 1.1 * s)) {
                ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { c in Circle().fill(Color(tourHex: UInt32(c))).frame(width: max(1.8, 1.7 * s), height: max(1.8, 1.7 * s)) }
                Spacer(minLength: 0)
                if detailed { Text(app.name).font(.system(size: 2.9 * s, weight: .semibold)).foregroundStyle(titleInk(dark)).lineLimit(1) }
                Spacer(minLength: 0)
                Color.clear.frame(width: 6 * s, height: 1)
            }
            .padding(.horizontal, max(2, 2.4 * s))
            .frame(height: titleH)
            .background(app == .terminal ? Color(tourHex: 0x2A2A2E) : (dark ? Color(tourHex: 0x323237) : Color(tourHex: 0xF3F3F5)))
            Canvas { ctx, size in TourMiniWindow.drawBody(app, ctx: ctx, size: size, u: s, dark: dark) }
        }
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color.black.opacity(dark ? 0.55 : 0.16), lineWidth: 0.5))
        .overlay(RoundedRectangle(cornerRadius: r + bw / 2, style: .continuous).stroke(Color.tourAccent, lineWidth: bw).padding(-bw / 2).opacity(border ? 1 : 0))
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(Color.tourAccent, lineWidth: max(1.5, 0.6 * s))
                    .shadow(color: Color.tourAccent.opacity(0.6), radius: 4 * s).opacity(ring ? 1 : 0))
        .shadow(color: Color(tourHex: 0x111827, dark ? 0.45 : 0.2), radius: 4.5 * s, y: 2.2 * s)
    }

    private func titleInk(_ dark: Bool) -> Color { app == .terminal || dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6) }

    static func drawBody(_ app: TourApp, ctx: GraphicsContext, size: CGSize, u: CGFloat, dark: Bool) {
        let w = size.width, h = size.height
        let ink = dark ? Color.white.opacity(0.2) : Color.black.opacity(0.11)
        let strong = dark ? Color.white.opacity(0.42) : Color.black.opacity(0.3)
        func bar(_ x: CGFloat, _ y: CGFloat, _ bw: CGFloat, _ c: Color, _ bh: CGFloat = 1.3) {
            guard y + bh * u < h, bw > 0 else { return }
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: bw, height: bh * u), cornerRadius: bh * u / 2), with: .color(c))
        }
        func lines(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, count: Int, c: Color = ink) {
            let widths: [CGFloat] = [0.92, 0.78, 0.86, 0.6, 0.82, 0.7, 0.9, 0.5]
            for i in 0..<count { bar(x, y + CGFloat(i) * 3.6 * u, width * widths[i % widths.count], c) }
        }
        let p = 3 * u
        switch app {
        case .notes:
            let sw = w * 0.32
            ctx.fill(Path(CGRect(x: 0, y: 0, width: sw, height: h)), with: .color(app.color.opacity(dark ? 0.1 : 0.12)))
            ctx.fill(Path(roundedRect: CGRect(x: 2 * u, y: 2.4 * u, width: sw - 4 * u, height: 6 * u), cornerRadius: 1.2 * u), with: .color(app.color.opacity(0.75)))
            for i in 0..<5 { bar(3 * u, 11.5 * u + CGFloat(i) * 5 * u, (sw - 6 * u) * (i % 2 == 0 ? 0.8 : 0.6), ink) }
            bar(sw + p, 3 * u, (w - sw - 2 * p) * 0.5, strong, 2)
            lines(sw + p, 8.5 * u, w - sw - 2 * p, count: 60)
        case .safari:
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.25, y: 1.6 * u, width: w * 0.5, height: 3.4 * u), cornerRadius: 1.7 * u), with: .color(ink))
            let hero = CGRect(x: p, y: 7 * u, width: w - 2 * p, height: max(0, min(h * 0.38, h - 9 * u)))
            ctx.fill(Path(roundedRect: hero, cornerRadius: 1.6 * u), with: .linearGradient(Gradient(colors: [app.color, Color(tourHex: 0x5E5CE6)]), startPoint: hero.origin, endPoint: CGPoint(x: hero.maxX, y: hero.maxY)))
            bar(hero.minX + 3 * u, hero.midY - 2 * u, hero.width * 0.45, .white.opacity(0.85), 2.2)
            bar(hero.minX + 3 * u, hero.midY + 1.6 * u, hero.width * 0.3, .white.opacity(0.6), 1.3)
            let cy = hero.maxY + 3 * u, cw = (w - 2 * p - 4 * u) / 3
            for i in 0..<3 where cy + 9 * u < h {
                ctx.fill(Path(roundedRect: CGRect(x: p + CGFloat(i) * (cw + 2 * u), y: cy, width: cw, height: 9 * u), cornerRadius: 1.2 * u), with: .color(ink))
            }
            lines(p, cy + 12 * u, w - 2 * p, count: 20)
        case .terminal:
            let green = Color(tourHex: 0x32D74B), text = Color.white.opacity(0.55)
            let widths: [CGFloat] = [0.35, 0.7, 0.55, 0.2, 0.8, 0.45, 0.62, 0.3, 0.74, 0.5]
            var y = 2.6 * u, i = 0
            while y + 1.3 * u < h {
                if i % 4 == 0 { bar(p, y, 5 * u, green); bar(p + 6 * u, y, (w - 2 * p) * widths[i % widths.count] * 0.6, text) }
                else { bar(p, y, (w - 2 * p) * widths[i % widths.count], i % 4 == 3 ? Color.white.opacity(0.3) : text) }
                y += 3.6 * u; i += 1
            }
        case .mail:
            let lw = w * 0.38
            ctx.fill(Path(CGRect(x: lw, y: 0, width: 0.5, height: h)), with: .color(ink))
            for i in 0..<12 {
                let y = 2.5 * u + CGFloat(i) * 8 * u
                guard y + 6 * u < h else { break }
                if i == 0 { ctx.fill(Path(roundedRect: CGRect(x: 1 * u, y: y - 1 * u, width: lw - 2 * u, height: 7.4 * u), cornerRadius: 1.2 * u), with: .color(app.color.opacity(0.85))) }
                if i < 3 { ctx.fill(Path(ellipseIn: CGRect(x: 2 * u, y: y + 0.4 * u, width: 1.6 * u, height: 1.6 * u)), with: .color(i == 0 ? .white : app.color)) }
                bar(4.6 * u, y, (lw - 7 * u) * 0.7, i == 0 ? .white.opacity(0.9) : strong)
                bar(4.6 * u, y + 3 * u, (lw - 7 * u) * 0.9, i == 0 ? .white.opacity(0.6) : ink)
            }
            bar(lw + p, 3 * u, (w - lw - 2 * p) * 0.6, strong, 2)
            lines(lw + p, 8.5 * u, w - lw - 2 * p, count: 60)
        case .music:
            let sw = w * 0.22
            ctx.fill(Path(CGRect(x: 0, y: 0, width: sw, height: h)), with: .color(ink.opacity(0.5)))
            for i in 0..<6 { bar(2 * u, 3 * u + CGFloat(i) * 4.4 * u, (sw - 4 * u) * 0.8, i == 1 ? app.color : ink) }
            let colors: [[Color]] = [[app.color, Color(tourHex: 0xFF9F0A)], [Color(tourHex: 0xBF5AF2), Color(tourHex: 0x5E5CE6)], [Color(tourHex: 0xFF375F), Color(tourHex: 0xBF5AF2)], [Color(tourHex: 0x64D2FF), Color(tourHex: 0x0A84FF)]]
            let gx = sw + p, side = max(4, min((w - gx - p - 3 * u) / 4, 18 * u))
            var y = 3 * u, k = 0
            while y + side < h {
                for c in 0..<4 {
                    let rect = CGRect(x: gx + CGFloat(c) * (side + u), y: y, width: side, height: side)
                    guard rect.maxX <= w - u else { continue }
                    let g = colors[(k + c) % colors.count]
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.2 * u), with: .linearGradient(Gradient(colors: g), startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                }
                y += side + 4 * u; k += 1
            }
        case .messages:
            let lw = w * 0.3
            for i in 0..<10 {
                let y = 2.5 * u + CGFloat(i) * 7 * u
                guard y + 5 * u < h else { break }
                ctx.fill(Path(ellipseIn: CGRect(x: 2 * u, y: y, width: 4.6 * u, height: 4.6 * u)), with: .color(i == 0 ? app.color : ink))
                bar(8 * u, y + 0.6 * u, (lw - 10 * u) * 0.8, strong)
                bar(8 * u, y + 3 * u, (lw - 10 * u) * 0.6, ink)
            }
            ctx.fill(Path(CGRect(x: lw, y: 0, width: 0.5, height: h)), with: .color(ink))
            var y = 3 * u, i = 0
            let cw = w - lw - 2 * p
            while y + 5 * u < h {
                let mine = i % 3 == 1, bw = cw * (mine ? 0.55 : 0.62)
                let rect = CGRect(x: mine ? w - p - bw : lw + p, y: y, width: bw, height: 5 * u)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2.5 * u), with: .color(mine ? Color(tourHex: 0x0A84FF) : ink.opacity(1.6)))
                y += 7.5 * u; i += 1
            }
        }
    }
}

/// The hover bar: three buttons with their shortcuts, plus a row of chips for a stacked tile.
struct TourMiniBar: View {
    let state: TourDemoState
    let frame: CGRect
    let floating: Bool
    let s: CGFloat
    let detailed: Bool

    var body: some View {
        let r = TourGeo.bar(frame, stack: state.barStack, floating: floating)
        let buttons: [(String, String, [String])] = [
            ("rectangle.lefthalf.filled", "Principale", ["⌃", "⌥", "↩"]),
            (state.focused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", state.focused ? "Quitter" : "Focus", ["⌃", "⌥", "Z"]),
            (floating ? "rectangle.split.2x1" : "square.on.square", floating ? "Ranger" : "Flotter", ["⌃", "⌥", "F"])]
        VStack(spacing: 0) {
            if state.barStack {
                HStack(spacing: 1 * s) {
                    Image(systemName: "chevron.left").font(.system(size: 3.2 * s, weight: .bold)).frame(width: 6 * s)
                    ForEach(Array(state.stackApps.enumerated()), id: \.offset) { i, app in
                        HStack(spacing: 1.2 * s) {
                            TourAppIcon(app: app, size: 4.6 * s)
                            if detailed { Text(app.name).font(.system(size: 3.1 * s, weight: .medium)).lineLimit(1) }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 1 * s)
                        .frame(width: TourGeo.chipWidth * s, height: 7 * s)
                        .background(RoundedRectangle(cornerRadius: 1.7 * s).fill(i == state.stackShown ? Color.tourOrange.opacity(0.28) : (state.chipHot == i ? Color.white.opacity(0.1) : .clear)))
                        .overlay(RoundedRectangle(cornerRadius: 1.7 * s).strokeBorder(Color.tourOrange.opacity(i == state.stackShown ? 0.7 : 0), lineWidth: 0.6))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 3.2 * s, weight: .bold)).frame(width: 6 * s)
                }
                .frame(height: TourGeo.stackRow * s - 0.5)
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5).padding(.horizontal, 1.6 * s)
            }
            HStack(spacing: 0.5 * s) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 0.6 * s) {
                        HStack(spacing: 1.2 * s) {
                            Image(systemName: buttons[i].0).font(.system(size: 3.6 * s, weight: .medium))
                            if detailed { Text(buttons[i].1).font(.system(size: 3.4 * s, weight: .semibold)) }
                        }
                        if detailed {
                            HStack(spacing: 0.5 * s) {
                                ForEach(buttons[i].2, id: \.self) { k in
                                    Text(k).font(.system(size: 2.5 * s, weight: .medium)).foregroundStyle(Color(tourHex: 0xEBEBF5, 0.65))
                                        .frame(minWidth: 3.8 * s, minHeight: 3.6 * s).background(RoundedRectangle(cornerRadius: 0.9 * s).fill(Color.white.opacity(0.12)))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 2 * s).fill(Color.white.opacity(state.barHot == i ? (state.pressing ? 0.2 : 0.12) : 0)))
                }
            }
            .padding(1 * s)
            .frame(height: TourGeo.barSize.height * s)
        }
        .foregroundStyle(Color(tourHex: 0xF5F5F7))
        .frame(width: r.width * s, height: r.height * s)
        .background(RoundedRectangle(cornerRadius: 3 * s, style: .continuous).fill(Color(tourHex: 0x222226, 0.97)))
        .overlay(RoundedRectangle(cornerRadius: 3 * s, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 6 * s, y: 3 * s)
        .position(x: r.midX * s, y: r.midY * s)
    }
}

/// The menu bar panel, reduced to what the demos use: the count buttons, Clean Space and No peek.
struct TourMiniPanel: View {
    let state: TourDemoState
    let s: CGFloat
    let detailed: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let r = TourGeo.panel
        let text = dark ? Color(tourHex: 0xF5F5F7) : Color(tourHex: 0x1D1D1F)
        let fill = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2 * s) {
                TourLogo().fill(text).frame(width: 5.5 * s, height: 5 * s)
                label("Mosaïque", size: 3.6, weight: .semibold, color: text, width: 20)
                Spacer(minLength: 0)
                Circle().fill(Color(tourHex: 0x34C759)).frame(width: 1.8 * s, height: 1.8 * s)
            }
            .frame(height: 12 * s)
            HStack(spacing: 2.5 * s) {
                ForEach(1...4, id: \.self) { n in
                    let on = state.panelCount == n
                    RoundedRectangle(cornerRadius: 1.4 * s).fill(on ? Color.tourAccent.opacity(0.14) : fill)
                        .overlay(RoundedRectangle(cornerRadius: 1.4 * s).strokeBorder(on ? Color.tourAccent : .clear, lineWidth: max(0.8, 0.4 * s)))
                        .overlay(TourCountGlyph(count: n, kind: .grid).fill(on ? Color.tourAccent : text.opacity(0.45)).padding(1.6 * s))
                        .frame(width: 16 * s, height: 9 * s)
                        .background(RoundedRectangle(cornerRadius: 1.4 * s).fill(state.panelHot == "count\(n)" ? fill : .clear).padding(-0.8 * s))
                }
            }
            .frame(height: 12 * s)
            Rectangle().fill(fill).frame(height: 0.5).padding(.vertical, 1.4 * s)
            row("Clean Space", key: "clean", text: text, fill: fill)
            row("No peek", key: "nopeek", text: text, fill: fill)
            Rectangle().fill(fill).frame(height: 0.5).padding(.vertical, 1.4 * s)
            label("Réglages…", size: 3.2, weight: .regular, color: text, width: 18).frame(height: 6 * s)
        }
        .padding(.horizontal, 3.5 * s)
        .frame(width: r.width * s, height: r.height * s, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 3.5 * s, style: .continuous).fill(dark ? Color(tourHex: 0x26262C) : Color(tourHex: 0xF6F6F8)))
        .overlay(RoundedRectangle(cornerRadius: 3.5 * s, style: .continuous).strokeBorder(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 6 * s, y: 3 * s)
        .position(x: r.midX * s, y: r.midY * s)
    }

    @ViewBuilder private func label(_ t: String, size: CGFloat, weight: Font.Weight, color: Color, width: CGFloat) -> some View {
        if detailed { Text(t).font(.system(size: size * s, weight: weight)).foregroundStyle(color).lineLimit(1) }
        else { RoundedRectangle(cornerRadius: 0.6 * s).fill(color.opacity(0.5)).frame(width: width * s, height: 1.8 * s) }
    }

    private func row(_ title: String, key: String, text: Color, fill: Color) -> some View {
        let on = state.panelOn.contains(key)
        return HStack {
            label(title, size: 3.3, weight: .regular, color: text, width: 22)
            Spacer(minLength: 0)
            Capsule().fill(on ? Color.tourAccent : fill.opacity(2.2)).frame(width: 7.5 * s, height: 4.4 * s)
                .overlay(Circle().fill(.white).frame(width: 3.6 * s).shadow(color: .black.opacity(0.25), radius: 0.4 * s).offset(x: on ? 1.55 * s : -1.55 * s))
        }
        .padding(.horizontal, 1.2 * s)
        .frame(height: 8.6 * s)
        .background(RoundedRectangle(cornerRadius: 1.4 * s).fill(state.panelHot == key ? fill : .clear))
    }
}

/// Small layout thumbnail used by the count buttons and choice tiles.
struct TourCountGlyph: Shape {
    var count: Int
    var kind: LayoutKind
    func path(in r: CGRect) -> Path {
        let frames = TourGeo.tiles(count, kind: kind)
        let a = TourGeo.inner
        var p = Path()
        let sx = r.width / a.width, sy = r.height / a.height
        for f in frames {
            let rect = CGRect(x: r.minX + (f.minX - a.minX) * sx, y: r.minY + (f.minY - a.minY) * sy, width: f.width * sx, height: f.height * sy)
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: min(rect.width, rect.height) * 0.16, height: min(rect.width, rect.height) * 0.16))
        }
        return p
    }
}

/// Tab View: a dark panel with a map of the screen; the picked window is outlined in accent.
struct TourMiniTabView: View {
    let state: TourDemoState
    let s: CGFloat
    let detailed: Bool
    var body: some View {
        let r = TourGeo.tabPanel, m = TourGeo.tabMap
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5 * s, style: .continuous).fill(Color(tourHex: 0x202024, 0.97))
                .overlay(RoundedRectangle(cornerRadius: 5 * s, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
                .frame(width: r.width * s, height: r.height * s)
                .position(x: r.midX * s, y: r.midY * s)
                .shadow(color: .black.opacity(0.45), radius: 10 * s, y: 6 * s)
            HStack(spacing: 1.5 * s) {
                Image(systemName: "laptopcomputer").font(.system(size: 3.6 * s))
                if detailed { Text("Écran intégré").font(.system(size: 3.4 * s, weight: .semibold)); Text("\(state.wins.count) fenêtres").font(.system(size: 3 * s)).opacity(0.6) }
            }
            .foregroundStyle(Color(tourHex: 0xF5F5F7))
            .position(x: (m.minX + (detailed ? 26 : 4)) * s, y: (r.minY + 8) * s)
            RoundedRectangle(cornerRadius: 2.6 * s).fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 2.6 * s).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                .frame(width: m.width * s, height: m.height * s).position(x: m.midX * s, y: m.midY * s)
            ForEach(state.wins.filter { !$0.floating }) { w in
                let t = TourGeo.tabTile(w.frame), on = state.tabPick == w.id
                RoundedRectangle(cornerRadius: 2.2 * s).fill(on ? Color.tourAccent.opacity(0.3) : Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 2.2 * s).strokeBorder(on ? Color.tourAccent : (w.id == state.active ? Color.white.opacity(0.3) : .clear), lineWidth: on ? max(1.2, 0.6 * s) : 0.5))
                    .overlay(TourAppIcon(app: w.app, size: min(t.height * 0.42, 11) * s))
                    .frame(width: t.width * s, height: t.height * s).position(x: t.midX * s, y: t.midY * s)
            }
            if detailed, let pick = state.wins.first(where: { $0.id == state.tabPick }) {
                Text(pick.app.name).font(.system(size: 3.4 * s, weight: .semibold)).foregroundStyle(Color(tourHex: 0xF5F5F7))
                    .position(x: m.midX * s, y: (m.maxY + 7) * s)
                Text("⇥ suivante · lâche ⌥ pour y aller · Échap").font(.system(size: 2.7 * s)).foregroundStyle(Color(tourHex: 0xEBEBF5, 0.55))
                    .fixedSize().position(x: m.midX * s, y: (m.maxY + 12.5) * s)
            }
        }
    }
}

/// Settings › Activité in miniature, with numbers counting up.
struct TourMiniActivity: View {
    let count: Int
    let mouse: Bool
    let s: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        let text = dark ? Color(tourHex: 0xF5F5F7) : Color(tourHex: 0x1D1D1F)
        let text2 = dark ? Color(tourHex: 0xEBEBF5, 0.6) : Color(tourHex: 0x3C3C43, 0.75)
        let keys = Int(Double(count) * 0.42), clicks = Int(Double(count) * 0.3)
        let minutes = (count * 4 + (keys + clicks) * 2) / 60
        let big = max(16, 13 * s), small = max(7, 3.6 * s)
        VStack(alignment: .leading, spacing: max(4, 2.4 * s)) {
            HStack(spacing: max(3, 1.6 * s)) {
                RoundedRectangle(cornerRadius: max(3, 1.4 * s)).fill(LinearGradient(colors: [Color(tourHex: 0x3DCCE6), Color(tourHex: 0x0D8CB5)], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(10, 6 * s), height: max(10, 6 * s))
                    .overlay(Image(systemName: "chart.bar.fill").font(.system(size: max(6, 3.4 * s))).foregroundStyle(.white))
                Text("Activité").font(.system(size: max(9, 4.4 * s), weight: .bold)).foregroundStyle(text)
            }
            HStack(alignment: .firstTextBaseline, spacing: max(3, 1.6 * s)) {
                Text("\(count)").font(.system(size: big, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(text).contentTransition(.numericText(value: Double(count)))
                Text("fenêtres rangées\ncette semaine").font(.system(size: small)).foregroundStyle(text2).lineLimit(2)
            }
            if s >= 1.2 {
                HStack(spacing: max(6, 3 * s)) {
                    stat("Temps gagné", "≈ \(minutes) min", text: text, text2: text2, on: false)
                    stat("Raccourcis", "\(keys)", text: text, text2: text2, on: !mouse)
                    stat("Souris", "\(clicks)", text: text, text2: text2, on: mouse)
                }
            } else {
                Text("≈ \(minutes) min gagnées").font(.system(size: small, weight: .semibold)).foregroundStyle(Color.tourAccent).lineLimit(1)
            }
        }
        .padding(max(7, 5 * s))
        .frame(width: s >= 1.2 ? 150 * s : nil, alignment: .leading)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: max(7, 4 * s), style: .continuous).fill(dark ? Color(tourHex: 0x2C2C31) : .white))
        .overlay(RoundedRectangle(cornerRadius: max(7, 4 * s), style: .continuous).strokeBorder(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 8 * s, y: 4 * s)
        .position(x: TourGeo.size.width / 2 * s, y: (TourGeo.area.midY - 4) * s)
    }
    private func stat(_ title: String, _ value: String, text: Color, text2: Color, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: max(6, 3 * s))).foregroundStyle(on ? Color.tourAccent : text2).lineLimit(1)
            Text(value).font(.system(size: max(8, 4.4 * s), weight: .semibold)).monospacedDigit().foregroundStyle(on ? Color.tourAccent : text).contentTransition(.numericText())
        }
        .padding(.horizontal, max(3, 1.6 * s)).padding(.vertical, max(2, 1 * s))
        .background(RoundedRectangle(cornerRadius: max(3, 1.6 * s)).fill(on ? Color.tourAccent.opacity(0.12) : .clear))
    }
}

// MARK: Scripts and player

struct TourStep {
    let wait: Double
    let animation: Animation?
    let change: (inout TourDemoState) -> Void
}

struct TourScript {
    let id: String
    let initial: TourDemoState
    let steps: [TourStep]
    let poster: Int
    var posterState: TourDemoState {
        var s = initial
        for step in steps.prefix(poster) { step.change(&s) }
        return s
    }
}

/// Small DSL to write a demo as a timeline. `wait` is the pause before the change is applied.
final class TourScriptBuilder {
    private(set) var steps: [TourStep] = []
    var posterIndex: Int?
    func then(_ wait: Double, _ animation: Animation? = .tourWindow, _ change: @escaping (inout TourDemoState) -> Void) {
        steps.append(TourStep(wait: wait, animation: animation, change: change))
    }
    /// Marks the current point as the still frame shown when the demo isn't playing.
    func poster() { posterIndex = steps.count }
    /// Shows the keys, presses them, applies the effect with the window spring, then lifts them.
    func press(_ keys: [String], _ caption: String, after wait: Double = 0.7, hold: Bool = false, _ effect: @escaping (inout TourDemoState) -> Void) {
        then(wait, .tourQuick) { $0.keys = keys; $0.caption = caption; $0.keysDown = false }
        then(0.45, .tourQuick) { $0.keysDown = true }
        then(0.1, .tourWindow, effect)
        if !hold { then(0.35, .tourQuick) { $0.keysDown = false } }
    }
    func hideKeys(after wait: Double = 0.8) { then(wait, .tourFade) { $0.keys = []; $0.caption = nil; $0.keysDown = false } }
    func move(_ p: CGPoint, after wait: Double = 0.25, _ animation: Animation = .tourCursor) { then(wait, animation) { $0.cursor = p } }
    /// Presses and releases the pointer, then applies the effect.
    func click(after wait: Double = 0.6, _ effect: @escaping (inout TourDemoState) -> Void) {
        then(wait, .tourQuick) { $0.pressing = true }
        then(0.12, .tourQuick) { $0.pressing = false }
        then(0.02, .tourWindow, effect)
    }
    func build(_ id: String, _ initial: TourDemoState) -> TourScript {
        TourScript(id: id, initial: initial, steps: steps, poster: posterIndex ?? min(2, steps.count))
    }
}

/// Plays a script in a loop while `playing`; shows its still frame otherwise.
struct TourDemoPlayer: View {
    let script: TourScript
    let playing: Bool
    var corner: CGFloat = 10
    @State private var state: TourDemoState
    @State private var fade = 1.0

    init(script: TourScript, playing: Bool, corner: CGFloat = 10) {
        self.script = script; self.playing = playing; self.corner = corner
        _state = State(initialValue: script.posterState)
    }

    private struct Key: Equatable { let id: String; let playing: Bool }
    /// Off-screen renders show the still frame only.
    static var stillFrames = false

    var body: some View {
        TourScene(state: state, corner: corner)
            .opacity(fade)
            .task(id: Key(id: script.id, playing: playing)) {
                guard playing, !Self.stillFrames else {
                    withAnimation(.tourFade) { state = script.posterState; fade = 1 }
                    return
                }
                while !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.18)) { fade = 0 }
                    try? await Task.sleep(for: .milliseconds(180))
                    if Task.isCancelled { return }
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { state = script.initial }
                    withAnimation(.easeIn(duration: 0.2)) { fade = 1 }
                    for step in script.steps {
                        try? await Task.sleep(for: .seconds(step.wait))
                        if Task.isCancelled { return }
                        withAnimation(step.animation) { step.change(&state) }
                    }
                    try? await Task.sleep(for: .seconds(1.4))
                }
            }
    }
}
