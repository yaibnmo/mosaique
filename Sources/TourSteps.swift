import SwiftUI
import AppKit

// MARK: Tokens and controls (reference section 6)

struct TourPalette {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var text: Color { dark ? Color(tourHex: 0xF5F5F7) : Color(tourHex: 0x1D1D1F) }
    var text2: Color { dark ? Color(tourHex: 0xEBEBF5, 0.62) : Color(tourHex: 0x3C3C43, 0.78) }
    var text3: Color { dark ? Color(tourHex: 0xEBEBF5, 0.34) : Color(tourHex: 0x3C3C43, 0.5) }
    var fill: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    var fill2: Color { dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10) }
    var edge: Color { dark ? Color.white.opacity(0.12) : Color.black.opacity(0.14) }
    var glass: Color { dark ? Color(tourHex: 0x26262C) : Color(tourHex: 0xF6F6F8) }
    var solid: Color { dark ? Color(tourHex: 0x2E2E34) : .white }
    var background: Color { dark ? Color(tourHex: 0x232327) : Color(tourHex: 0xECECEE) }
    static let green = Color(tourHex: 0x1F9D57)
    static let warning = Color(tourHex: 0xC77700)
}

struct TourButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary
    func makeBody(configuration: Configuration) -> some View { TourButtonBody(configuration: configuration, kind: kind) }
}

private struct TourButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: TourButtonStyle.Kind
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = TourPalette(scheme)
        configuration.label
            .font(.system(size: 13, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(kind == .primary ? (enabled ? Color.white : p.text3) : p.text)
            .padding(.horizontal, kind == .primary ? 18 : 14)
            .frame(minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(kind == .primary ? (enabled ? Color.tourAccent : p.fill2) : p.fill2.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .animation(.easeOut(duration: 0.15), value: enabled)
    }
}

/// 38×22 switch with a springy knob.
struct TourSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Capsule().fill(isOn ? Color.tourAccent : TourPalette(scheme).fill2)
            .frame(width: 38, height: 22)
            .overlay(Circle().fill(.white).frame(width: 18, height: 18).shadow(color: .black.opacity(0.3), radius: 1.5, y: 1).offset(x: isOn ? 8 : -8))
            .onTapGesture { withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { isOn.toggle() } }
            .accessibilityElement().accessibilityAddTraits(.isButton).accessibilityValue(isOn ? "activé" : "désactivé")
            .accessibilityAction { isOn.toggle() }
    }
}

/// Segmented control: fill track, the selected segment on a solid pill.
struct TourSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String, String?)]
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = TourPalette(scheme)
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.0 == selection
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = option.0 } } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.2 { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                        Text(option.1).font(.system(size: 12, weight: on ? .semibold : .regular))
                    }
                    .foregroundStyle(on ? p.text : p.text2)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.dark ? Color(tourHex: 0x5A5A60) : .white)
                                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.edge, lineWidth: 0.5))
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.fill))
    }
}

/// Choice tile: fill background; selected gets an accent tint and a 1.5 pt accent ring.
struct TourChoice<Thumb: View>: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @ViewBuilder let thumb: () -> Thumb
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = TourPalette(scheme)
        Button(action: action) {
            VStack(spacing: 6) {
                thumb()
                Text(title).font(.system(size: 11.5, weight: on ? .semibold : .regular)).foregroundStyle(on ? Color.tourAccent : p.text)
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.top, 10).padding(.horizontal, 6).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Color.tourAccent.opacity(0.14) : p.fill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(on ? Color.tourAccent : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct TourHeading: View {
    let title: String
    let subtitle: String
    var center = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = TourPalette(scheme)
        VStack(alignment: center ? .center : .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(p.text)
            Text(subtitle).font(.system(size: 13.5)).foregroundStyle(p.text2).multilineTextAlignment(center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TourGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = TourPalette(scheme)
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.solid))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.edge, lineWidth: 0.5))
    }
}

/// A settings-style row: tinted icon, title and hint, trailing control.
struct TourRow<Trailing: View>: View {
    let symbol: String
    let tint: (UInt32, UInt32)
    let title: String
    let hint: String
    var divider = false
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = TourPalette(scheme)
        VStack(spacing: 0) {
            if divider { Rectangle().fill(p.fill).frame(height: 0.5).padding(.leading, 50) }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color(tourHex: tint.0), Color(tourHex: tint.1)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(p.text)
                    Text(hint).font(.system(size: 11.5)).foregroundStyle(p.text3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                trailing()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 54)
        }
    }
}

struct TourStatusBadge: View {
    let text: String
    let symbol: String
    let color: Color
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

/// Three dots pulsing while the tour waits for access.
struct TourWaitingDots: View {
    @State private var phase = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.tourAccent).frame(width: 5, height: 5)
                    .opacity(phase ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: phase)
            }
        }
        .onAppear { phase = true }
    }
}

// MARK: 1. Bienvenue

struct TourWelcomeStep: View {
    @ObservedObject var model: TourModel
    @State private var band: CGFloat?
    @State private var rings: Set<Int> = []
    @Environment(\.colorScheme) private var scheme

    static let pile: [TourWin] = [
        TourWin(id: 1, app: .notes, frame: CGRect(x: 52, y: 26, width: 150, height: 106), z: 1),
        TourWin(id: 2, app: .safari, frame: CGRect(x: 122, y: 40, width: 150, height: 104), z: 2),
        TourWin(id: 3, app: .terminal, frame: CGRect(x: 84, y: 64, width: 140, height: 98), z: 3)]

    private var state: TourDemoState {
        var s = TourDemoState()
        s.wins = Self.pile
        s.active = 3
        s.highlight = "none"
        s.grip = false
        if model.settled { s.layout([1, 2, 3]) }
        s.band = band
        s.rings = rings
        return s
    }

    var body: some View {
        let p = TourPalette(scheme)
        VStack(spacing: 24) {
            TourScene(state: state, corner: 12)
                .frame(width: 600)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                .padding(.top, 14)
            VStack(spacing: 8) {
                Text("Bienvenue dans Mosaïque").font(.system(size: 28, weight: .bold)).foregroundStyle(p.text)
                Text("Tes fenêtres se rangent côte à côte, toutes seules. La visite prend deux minutes,\net rien ne bouge sur ton écran avant la toute fin.")
                    .font(.system(size: 14)).foregroundStyle(p.text2).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: model.settled) { _, on in if on { sweep() } }
    }

    /// The tidy sweep in miniature: a light band crosses the screen and each window flashes a ring as it passes.
    private func sweep() {
        let width = TourGeo.size.width, bandWidth = width * 0.32
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { band = -bandWidth / 2 }
            withAnimation(.easeInOut(duration: 0.75).delay(0.08)) { band = width + bandWidth / 2 }
            for (i, f) in TourGeo.tiles(3).enumerated() {
                let delay = max(0, 0.08 + (f.midX / width) * 0.75 - 0.2)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { withAnimation(.easeInOut(duration: 0.2)) { _ = rings.insert(i + 1) } }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.2) { withAnimation(.easeInOut(duration: 0.2)) { _ = rings.remove(i + 1) } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { band = nil }
        }
    }
}

// MARK: 2. Autorisations

struct TourPermissionStep: View {
    @ObservedObject var model: TourModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TourPalette(scheme)
        VStack(alignment: .leading, spacing: 18) {
            TourHeading(title: "Autorise Mosaïque à ranger tes fenêtres",
                        subtitle: "macOS ne laisse une app déplacer les fenêtres des autres qu’avec ton accord. Mosaïque lit seulement leur position et leur taille, jamais ce qu’elles contiennent, et rien ne quitte ton Mac.")
            TourGroup {
                TourRow(symbol: "hand.raised.fill", tint: (0x3D9CFF, 0x0A6BE0), title: "Accès Accessibilité",
                        hint: model.trusted ? "Mosaïque peut déplacer et redimensionner tes fenêtres." : "Réglages Système › Confidentialité et sécurité › Accessibilité.") {
                    if model.trusted {
                        TourStatusBadge(text: "Autorisé", symbol: "checkmark.circle.fill", color: TourPalette.green)
                    } else {
                        Button(model.asked ? "Rouvrir Réglages Système" : "Ouvrir Réglages Système") { model.askAccess() }
                            .buttonStyle(TourButtonStyle(kind: model.asked ? .secondary : .primary))
                    }
                }
                if !model.trusted && model.asked {
                    Rectangle().fill(p.fill).frame(height: 0.5).padding(.leading, 50)
                    HStack(alignment: .top, spacing: 12) {
                        TourWaitingDots().frame(width: 26, height: 16)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("En attente… Active Mosaïque dans la liste.").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.text)
                            Text("Mosaïque le remarque tout de suite, rien à redémarrer. Absente de la liste ? Clique sur + et choisis Mosaïque dans Applications.")
                                .font(.system(size: 11.5)).foregroundStyle(p.text3).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .transition(.opacity)
                }
            }
            TourGroup {
                TourRow(symbol: "power", tint: (0x9E9E9E, 0x6B6B6B), title: "Ouvrir à la connexion",
                        hint: model.loginNote.isEmpty ? "Démarre Mosaïque quand tu ouvres ta session sur ce Mac." : model.loginNote) {
                    TourSwitch(isOn: Binding(get: { model.login }, set: { model.setLogin($0) }))
                }
                TourRow(symbol: "command", tint: (0x5C5C5C, 0x303030), title: "Raccourcis clavier", hint: shortcutHint, divider: true) {
                    if !model.shortcutsOn {
                        TourStatusBadge(text: "Désactivés", symbol: "pause.circle.fill", color: p.text3)
                    } else if model.taken.isEmpty {
                        TourStatusBadge(text: "Tous libres", symbol: "checkmark.circle.fill", color: TourPalette.green)
                    } else {
                        TourStatusBadge(text: model.takenLabels.count == 1 ? "1 déjà pris" : "\(model.takenLabels.count) déjà pris", symbol: "exclamationmark.triangle.fill", color: TourPalette.warning)
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pause.circle.fill").font(.system(size: 15)).foregroundStyle(Color.tourAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rien ne bouge pour l’instant").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.text)
                    Text("Autoriser l’accès ne range rien tout seul. Mosaïque attend que tu appuies sur « Ranger mon espace », à la fin de la visite.")
                        .font(.system(size: 12)).foregroundStyle(p.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.tourAccent.opacity(0.08)))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .onAppear { model.applyLoginDefault() }
    }

    private var shortcutHint: String {
        if !model.shortcutsOn { return "Coupés dans Réglages › Clavier. Tu peux les rallumer quand tu veux." }
        if model.taken.isEmpty { return "Tous les raccourcis ⌃⌥ de Mosaïque sont libres sur ce Mac." }
        return "Déjà utilisés par une autre app : \(model.takenLabels.joined(separator: ", ")). Les autres fonctionnent."
    }
}

// MARK: 5. À ta façon

struct TourCustomizeStep: View {
    @ObservedObject var model: TourModel
    @Environment(\.colorScheme) private var scheme

    static func preview(kind: LayoutKind, capacity: Int, highlight: String, whenFull: String) -> TourDemoState {
        let apps: [TourApp] = [.notes, .safari, .terminal, .mail]
        var s = TourDemoState()
        s.highlight = highlight
        let frames = TourGeo.tiles(capacity, kind: kind)
        s.wins = frames.enumerated().map { TourWin(id: $0.offset + 1, app: apps[$0.offset], frame: $0.element, z: Double($0.offset + 1)) }
        s.raise(1)
        // One more window than the screen holds, to show what "full" does.
        if whenFull == "stack" {
            s.wins.append(TourWin(id: 9, app: .music, frame: frames[0], z: 20))
            s.active = 9
            s.stackCount = 2; s.stackShown = 1
        } else {
            s.wins.append(TourWin(id: 9, app: .music, frame: TourGeo.floating.insetBy(dx: 18, dy: 12), z: 20, floating: true))
            s.grip = false
        }
        return s
    }

    var body: some View {
        let p = TourPalette(scheme)
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                TourHeading(title: "À ta façon", subtitle: "Tu pourras tout changer plus tard dans les réglages, ou pour un seul écran depuis la barre des menus.")
                TourScene(state: Self.preview(kind: model.kind, capacity: model.capacity, highlight: model.highlight, whenFull: model.whenFull), corner: 10)
                    .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                    .padding(.top, 6)
                Text(previewCaption).font(.system(size: 12)).foregroundStyle(p.text3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 360)
            VStack(alignment: .leading, spacing: 12) {
                section("Disposition", note: model.kind == .grid ? "Une grande fenêtre, les autres à côté." : "Toutes côte à côte, autant qu’il en tient : trois sur un MacBook, quatre sur un grand écran.") {
                    HStack(spacing: 8) {
                        ForEach(LayoutKind.allCases) { k in
                            TourChoice(title: k.label, on: model.kind == k, action: { set { model.kind = k } }) {
                                TourCountGlyph(count: 3, kind: k).fill(model.kind == k ? Color.tourAccent.opacity(0.75) : p.text3).frame(width: 64, height: 36)
                            }
                        }
                    }
                    .frame(width: 2 * 96 + 8)
                }
                section("Fenêtres par écran", note: nil) {
                    HStack(spacing: 8) {
                        ForEach(1...4, id: \.self) { n in
                            TourChoice(title: countTitle(n), on: model.capacity == n, action: { set { model.capacity = n } }) {
                                TourCountGlyph(count: n, kind: model.kind).fill(model.capacity == n ? Color.tourAccent.opacity(0.75) : p.text3).frame(width: 50, height: 28)
                            }
                        }
                    }
                }
                section("Mise en évidence", note: "Dessinée dans l’espace entre les fenêtres : elle ne cache jamais leur contenu.") {
                    HStack(spacing: 8) {
                        ForEach([("none", "Aucune"), ("active", "Bordure active"), ("all", "Toutes les bordures"), ("glow", "Lueur active")], id: \.0) { id, title in
                            TourChoice(title: title, on: model.highlight == id, action: { set { model.highlight = id } }) {
                                TourHighlightPictogram(mode: id).frame(width: 70, height: 42)
                            }
                        }
                    }
                }
                section("Quand un écran est plein", note: nil) {
                    VStack(spacing: 6) {
                        radio("stack", "Empiler dans la case active", "La nouvelle fenêtre rejoint la case où tu es, par-dessus. Passe de l’une à l’autre avec ⌃⌥` ou la poignée.")
                        radio("float", "Flotter au milieu", "La nouvelle fenêtre flotte au milieu jusqu’à ce qu’il y ait de la place.")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewCaption: String {
        model.whenFull == "stack"
            ? "Une fenêtre de plus arrive alors que l’écran est plein : elle s’empile dans la case active, la poignée devient orange."
            : "Une fenêtre de plus arrive alors que l’écran est plein : elle flotte au milieu jusqu’à ce qu’une place se libère."
    }

    private func set(_ change: () -> Void) { withAnimation(.tourWindow) { change() } }

    private func countTitle(_ n: Int) -> String {
        if model.kind == .columns { return n == 1 ? "Plein écran" : "\(n) colonnes" }
        return ["Plein écran", "Côte à côte", "Une grande, deux petites", "Grille de quatre"][n - 1]
    }

    @ViewBuilder private func section<C: View>(_ title: String, note: String?, @ViewBuilder content: () -> C) -> some View {
        let p = TourPalette(scheme)
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.text2)
            content().fixedSize(horizontal: false, vertical: true)
            if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(p.text3).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func radio(_ id: String, _ title: String, _ hint: String) -> some View {
        let p = TourPalette(scheme), on = model.whenFull == id
        return Button { set { model.whenFull = id } } label: {
            HStack(alignment: .top, spacing: 9) {
                Circle().strokeBorder(on ? Color.tourAccent : p.fill2, lineWidth: on ? 5 : 1.5).frame(width: 16, height: 16).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(p.text)
                    Text(hint).font(.system(size: 11.5)).foregroundStyle(p.text3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Color.tourAccent.opacity(0.08) : p.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Two little windows showing a highlight mode.
struct TourHighlightPictogram: View {
    let mode: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = TourPalette(scheme)
        let pane = p.dark ? Color.white.opacity(0.22) : Color.white
        HStack(spacing: 5) {
            ForEach(0..<2, id: \.self) { i in
                let active = i == 0
                let bordered = mode == "all" || (mode == "active" && active)
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(pane)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .overlay(RoundedRectangle(cornerRadius: 5.5, style: .continuous).stroke(Color.tourAccent, lineWidth: 2).padding(-1.5).opacity(bordered ? 1 : 0))
                    .overlay(alignment: .top) {
                        if mode == "glow" && active {
                            Capsule().fill(Color.tourAccent).frame(height: 2).padding(.horizontal, 5).offset(y: -4)
                                .shadow(color: Color.tourAccent.opacity(0.8), radius: 3)
                        }
                    }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(p.dark ? Color(tourHex: 0x3A2754) : Color(tourHex: 0xD6C2EE)))
    }
}

// MARK: 6. Prêt

struct TourReadyStep: View {
    @ObservedObject var model: TourModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TourPalette(scheme)
        VStack(spacing: 20) {
            TourScene(state: TourCustomizeStep.preview(kind: model.kind, capacity: model.capacity, highlight: model.highlight, whenFull: "stack").removingExtra(), corner: 10)
                .frame(width: 400)
                .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
                .padding(.top, 16)
            TourHeading(title: model.reopened ? "C’est tout pour la visite" : "Tout est prêt", subtitle: subtitle, center: true)
                .frame(maxWidth: 560)
            HStack(spacing: 6) {
                chip(model.kind.label, "rectangle.split.2x1")
                chip(model.capacity == 1 ? "1 fenêtre" : "Jusqu’à \(model.capacity) fenêtres", "square.grid.2x2")
                chip(highlightLabel, "square.dashed")
                chip(model.whenFull == "stack" ? "Empiler" : "Flotter au milieu", "square.stack")
            }
            if !model.canFinish {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.fill").font(.system(size: 15)).foregroundStyle(TourPalette.warning).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mosaïque a besoin de l’accès Accessibilité pour ranger tes fenêtres.").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text)
                        Text("Active-le dans Réglages Système. Le bouton « Ranger mon espace » s’allume dès que c’est fait.")
                            .font(.system(size: 12)).foregroundStyle(p.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("Ouvrir Réglages Système") { model.askAccess() }.buttonStyle(TourButtonStyle(kind: .secondary))
                }
                .padding(12)
                .frame(maxWidth: 600)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TourPalette.warning.opacity(0.12)))
                .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    TourLogo().fill(p.text2).frame(width: 15, height: 14)
                    Text("Ensuite, Mosaïque vit dans la barre des menus : clique sur son icône pour la disposition, Clean Space, No peek et les réglages.")
                        .font(.system(size: 12)).foregroundStyle(p.text3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        model.reopened
            ? "Mosaïque range déjà tes fenêtres. Tu peux revoir cette visite quand tu veux, dans Réglages › Général."
            : "Appuie sur « Ranger mon espace » : tes fenêtres se mettent en place, et la visite se range dans la barre des menus."
    }
    private var highlightLabel: String {
        switch model.highlight { case "active": return "Bordure active"; case "all": return "Toutes les bordures"; case "glow": return "Lueur active"; default: return "Sans mise en évidence" }
    }
    private func chip(_ text: String, _ symbol: String) -> some View {
        let p = TourPalette(scheme)
        return Label(text, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(p.text2)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(p.fill))
    }
}

private extension TourDemoState {
    /// The preview without its extra "screen is full" window.
    func removingExtra() -> TourDemoState {
        var s = self
        s.remove(9); s.stackCount = 1; s.raise(1); s.grip = true
        return s
    }
}
