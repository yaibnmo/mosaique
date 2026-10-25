import SwiftUI
import AppKit

// Pages General, Layout, Highlight, Mouse and Keyboard, laid out like the reference's screenshots.

let settingsGroupSpacing: CGFloat = 20

// MARK: General

struct SettingsGeneralPage: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var engine: WindowEngine

    private var tiling: Binding<Bool> {
        Binding(get: { engine.autoStart }, set: { engine.setAutomaticTiling($0) })
    }
    private var login: Binding<Bool> {
        Binding(get: { engine.loginEnabled }, set: { engine.setLogin($0) })
    }
    private let backgrounds: [(id: String, name: String, hex: UInt32)] = [("graphite", "Graphite", 0x2A2A2D), ("stone", "Pierre", 0x6E6C68), ("mist", "Brume", 0xD9D8D4)]

    var body: some View {
        VStack(alignment: .leading, spacing: settingsGroupSpacing) {
            SettingsGroup {
                SettingsRow(label: "Rangement automatique", hint: "Range les fenêtres quand elles s’ouvrent et se ferment.", anchor: "general.tiling") {
                    SettingsSwitch(isOn: tiling)
                }
                SettingsRow(label: "Ouvrir à la connexion", hint: engine.loginMessage.isEmpty ? "Lance Mosaïque à l’ouverture de ta session." : engine.loginMessage, anchor: "general.login") {
                    HStack(spacing: 10) {
                        Button("Éléments de connexion…") { engine.openLoginItems() }.buttonStyle(SettingsButtonStyle())
                        SettingsSwitch(isOn: login)
                    }
                }
            }

            SettingsGroup(title: "Apparence") {
                SettingsBlock(anchor: "general.icon") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Icône de l’app").font(.system(size: 13)).foregroundStyle(p.text)
                            Text("Affichée dans les fenêtres de Mosaïque.").font(.system(size: 11.5)).foregroundStyle(p.text3)
                        }
                        HStack(spacing: 6) {
                            ForEach(IconStyles.all, id: \.id) { style in
                                SettingsIconButton(style: style, on: engine.iconStyle == style.id) {
                                    engine.iconStyle = style.id
                                    IconStyles.apply(style.id)
                                                                    }
                            }
                        }
                    }
                }
                SettingsRow(label: "Clean Space", hint: "Le fond uni derrière la fenêtre que tu partages. ⌃⌥P", anchor: "general.clean") {
                    HStack(spacing: 3) {
                        ForEach(backgrounds, id: \.id) { bg in
                            SettingsSwatch(fill: Color.settingsHex(bg.hex), on: engine.cleanBackground == bg.id, name: bg.name) { engine.cleanBackground = bg.id }
                        }
                    }
                }
            }

            SettingsGroup(title: "Autorisation") {
                SettingsRow(label: "Accès Accessibilité", hint: "Permet à Mosaïque de déplacer et redimensionner les fenêtres. Il ne lit jamais ce qu’elles contiennent.", anchor: "general.access") {
                    if engine.trusted {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                            Text("Autorisé").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(p.green)
                    } else {
                        Button("Autoriser l’accès…") {
                            engine.requestAccess()
                            if !engine.trusted { engine.openAccessibility() }
                        }
                        .buttonStyle(SettingsButtonStyle(prominent: true))
                    }
                }
            }

            SettingsGroup(title: "Aide") {
                SettingsRow(label: "Visite de bienvenue", hint: "Deux minutes pour découvrir l’essentiel.", anchor: "general.tour") {
                    Button("Ouvrir la visite") { TourController.shared.show(engine: engine) }.buttonStyle(SettingsButtonStyle())
                }
            }
        }
    }
}

/// One of the seven app icons: a 40 pt icon over its name; the chosen one sits in an accent-outlined tile.
struct SettingsIconButton: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let style: (id: String, name: String, summary: String)
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.15)) { action() } }) {
            VStack(spacing: 3) {
                // The PNGs keep Apple's margin around the icon: draw them larger so the icon itself is 40 pt.
                Image(nsImage: IconStyles.image(for: style.id, size: 100))
                    .resizable().interpolation(.high)
                    .frame(width: 50, height: 50)
                    .frame(width: 40, height: 40)
                Text(style.name).font(.system(size: 11)).foregroundStyle(p.text2).lineLimit(1).fixedSize()
            }
            .padding(.top, 4).padding(.bottom, 4).padding(.horizontal, 4)
            .frame(minWidth: 48)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.accent.opacity(on ? 0.1 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.accent, lineWidth: 1.5).opacity(on ? 1 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(style.name) : \(style.summary)")
    }
}

// MARK: Layout

struct SettingsLayoutPage: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var engine: WindowEngine

    private func countTitle(_ n: Int) -> String {
        if engine.defaultKind == .columns { return n == 1 ? "Plein écran" : "\(n) colonnes" }
        return ["Plein écran", "Côte à côte", "Une grande, deux petites", "Grille de quatre"][n - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: settingsGroupSpacing) {
            SettingsGroup(title: "Disposition", note: "Les colonnes placent toutes les fenêtres côte à côte, autant qu’il en tient : trois sur un MacBook, quatre sur un écran plus grand. Les écrans verticaux empilent toujours les fenêtres en rangées.", anchor: "layout.kind") {
                SettingsBlock(padding: 10) {
                    HStack(spacing: 8) {
                        ForEach(LayoutKind.allCases) { kind in
                            SettingsChoice(title: kind.label, on: engine.defaultKind == kind, action: { engine.defaultKind = kind }) {
                                SettingsLayoutThumb(kind: kind, count: 3, on: engine.defaultKind == kind, width: 82, height: 44)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsGroup(title: "Fenêtres par écran", note: "Chaque écran commence avec ce nombre. Change-le pour un écran dans le panneau de la barre des menus ou avec ⌃⌥⌘1–4.", anchor: "layout.count") {
                SettingsBlock(padding: 10) {
                    HStack(spacing: 8) {
                        ForEach(1...4, id: \.self) { n in
                            SettingsChoice(title: countTitle(n), on: engine.defaultCapacity == n, minWidth: 0, action: { engine.defaultCapacity = n }) {
                                SettingsLayoutThumb(kind: engine.defaultKind, count: n, on: engine.defaultCapacity == n, width: 61, height: 34)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsGroup(title: "Quand un écran est plein", anchor: "layout.full") {
                SettingsRadioRow(label: "Empiler dans la case active", hint: "Une nouvelle fenêtre rejoint la case où tu es, par-dessus. Passe de l’une à l’autre avec ⌃⌥` ou la poignée.", on: engine.whenFull == "stack") { engine.whenFull = "stack" }
                SettingsRadioRow(label: "Flotter au milieu", hint: "Une nouvelle fenêtre flotte au milieu jusqu’à ce qu’il y ait de la place.", on: engine.whenFull == "float") { engine.whenFull = "float" }
            }

            SettingsGroup(title: "Déplacer vers un écran plein", anchor: "layout.move") {
                SettingsRadioRow(label: "Échanger les places", hint: "⌃⌥ + flèche ou Écran suivant échange la fenêtre avec celle où elle arrive.", on: engine.moveIntoFull == "swap") { engine.moveIntoFull = "swap" }
                SettingsRadioRow(label: "Empiler par-dessus", hint: "La fenêtre rejoint la pile de la case où elle arrive.", on: engine.moveIntoFull == "stack") { engine.moveIntoFull = "stack" }
            }

            SettingsGroup {
                SettingsRow(label: "Espace entre les fenêtres", hint: "Aussi utilisé autour des bords de l’écran.", anchor: "layout.gap") {
                    SettingsSlider(value: $engine.gap, range: 0...24, step: 2) { "\(Int($0)) pt" }
                }
            }
        }
    }
}

// MARK: Highlight

struct SettingsHighlightPage: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var engine: WindowEngine

    private let modes: [(id: String, title: String)] = [("none", "Aucune"), ("active", "Bordure active"), ("all", "Toutes les bordures"), ("glow", "Lueur active")]
    static let tints: [(id: String, name: String, hex: UInt32?)] = [("accent", "Accent", nil), ("purple", "Violet", 0xA550F5), ("pink", "Rose", 0xF7418F),
                                                                   ("orange", "Orange", 0xFF9500), ("green", "Vert", 0x34C759), ("graphite", "Graphite", 0x8E8E93)]
    private var bordered: Bool { engine.highlight == "active" || engine.highlight == "all" }
    private var noPeek: Binding<Bool> {
        Binding(get: { engine.noPeek }, set: { if $0 != engine.noPeek { engine.toggleNoPeek() } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: settingsGroupSpacing) {
            SettingsGroup(title: "Surbrillance", note: "Les surbrillances sont dessinées dans l’espace entre les fenêtres : elles ne couvrent jamais ce qu’il y a dedans.", anchor: "highlight.mode") {
                SettingsBlock(padding: 10) {
                    HStack(spacing: 8) {
                        ForEach(modes, id: \.id) { mode in
                            SettingsChoice(title: mode.title, on: engine.highlight == mode.id, minWidth: 0, action: { engine.highlight = mode.id }) {
                                SettingsHighlightThumb(mode: mode.id, on: engine.highlight == mode.id)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                SettingsRow(label: "Épaisseur de bordure", hint: bordered ? "L’espace entre les fenêtres s’élargit pour l’accueillir." : "Dessinée dans l’espace entre les fenêtres.", anchor: "highlight.width") {
                    SettingsSlider(value: $engine.borderWidth, range: 2...6, step: 1) { "\(Int($0)) pt" }
                }
                .disabled(!bordered)
                .opacity(bordered ? 1 : 0.45)
                SettingsRow(label: "Couleur", hint: engine.highlight == "none" ? "Choisis d’abord une surbrillance ci-dessus." : "Accent suit la couleur de ton Mac.", anchor: "highlight.color") {
                    HStack(spacing: 2) {
                        ForEach(Self.tints, id: \.id) { tint in
                            SettingsSwatch(fill: tint.hex.map { Color.settingsHex($0) } ?? p.accent, on: engine.tintName == tint.id, name: tint.name) { engine.tintName = tint.id }
                        }
                        SettingsSwatch(fill: engine.tintName == "custom" ? AnyShapeStyle(Color(nsColor: engine.customColor))
                                                                        : AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)),
                                       on: engine.tintName == "custom", name: "N’importe quelle couleur") { SettingsColorBridge.shared.open(engine: engine) }
                    }
                }
                .disabled(engine.highlight == "none")
                .opacity(engine.highlight == "none" ? 0.45 : 1)
            }

            SettingsGroup(title: "Mode No peek", note: "Rien n’est recouvert ni modifié : les fenêtres sous le voile fonctionnent comme d’habitude. La barre des menus et le Dock restent lumineux.") {
                SettingsRow(label: "Mode No peek", hint: "Toutes les fenêtres sauf celle où tu travailles s’estompent, pour que personne ne puisse lire. ⌃⌥D", anchor: "highlight.nopeek") {
                    SettingsSwitch(isOn: noPeek)
                }
                SettingsRow(label: "Intensité", hint: "Plus léger garde les autres fenêtres lisibles.", anchor: "highlight.dim") {
                    SettingsSlider(value: $engine.dimAmount, range: 0.1...0.9, step: 0.05) { "\(Int(($0 * 100).rounded())) %" }
                }
                .disabled(!engine.noPeek)
                .opacity(engine.noPeek ? 1 : 0.45)
                SettingsRow(label: "Flouter les autres fenêtres", hint: "Rend leur contenu illisible, pas seulement plus sombre.", anchor: "highlight.blur") {
                    SettingsSwitch(isOn: $engine.blurOthers)
                }
                .disabled(!engine.noPeek)
                .opacity(engine.noPeek ? 1 : 0.45)
            }
        }
    }
}

/// Opens the system colour panel for "any colour" and feeds the engine's custom tint.
final class SettingsColorBridge: NSObject {
    static let shared = SettingsColorBridge()
    private weak var engine: WindowEngine?
    func open(engine: WindowEngine) {
        self.engine = engine
        engine.tintName = "custom"
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = engine.customColor
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.orderFront(nil)
    }
    @objc private func changed(_ panel: NSColorPanel) {
        guard let engine else { return }
        engine.customColor = panel.color
        if engine.tintName != "custom" { engine.tintName = "custom" }
    }
}

// MARK: Mouse

struct SettingsMousePage: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var engine: WindowEngine

    private let always: [(label: String, hint: String)] = [
        ("Échanger deux fenêtres", "Maintiens ⌘ et fais glisser une fenêtre sur une autre."),
        ("Ajouter à une pile", "Maintiens ⌥⌘ et fais glisser une fenêtre sur une case."),
        ("Redimensionner", "Fais glisser le bord entre deux fenêtres."),
        ("Déplacer vers un autre écran", "Fais glisser une fenêtre sur l’autre écran."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: settingsGroupSpacing) {
            SettingsGroup {
                SettingsRow(label: "Actions rapides au-dessus des fenêtres", hint: "Repose le pointeur sur la poignée au-dessus d’une fenêtre pour ses actions.", anchor: "mouse.quick") {
                    SettingsSwitch(isOn: $engine.quickActions)
                }
                SettingsRow(label: "Activer les fenêtres au survol", hint: "Pointe une fenêtre pour la rendre active, sans cliquer.", anchor: "mouse.hover") {
                    SettingsSwitch(isOn: $engine.hoverFocus)
                }
            }
            SettingsGroup(title: "Toujours disponible", anchor: "mouse.always") {
                ForEach(always, id: \.label) { item in
                    SettingsRow(label: item.label, hint: item.hint)
                }
            }
        }
    }
}

// MARK: Keyboard

struct SettingsKeyboardPage: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var engine: WindowEngine
    private let categories = ["Déplacer", "Activer", "Taille", "Plus"]

    private var unavailable: [ShortcutInfo] {
        WindowEngine.shortcutCatalog.filter { engine.unavailableShortcuts.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: settingsGroupSpacing) {
            SettingsGroup(note: engine.shortcutsEnabled ? nil : "Les raccourcis sont désactivés. Ils restent listés ici pour que tu puisses les apprendre.") {
                SettingsRow(label: "Raccourcis clavier", hint: "Range les fenêtres avec ⌃ Contrôle et ⌥ Option.", anchor: "keyboard.master") {
                    SettingsSwitch(isOn: $engine.shortcutsEnabled)
                }
            }

            if engine.shortcutsEnabled && !unavailable.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundStyle(p.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(unavailable.count == 1 ? "Un raccourci est déjà utilisé par une autre app" : "\(unavailable.count) raccourcis sont déjà utilisés par une autre app")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text)
                        Text(unavailable.map { $0.keys.joined() }.joined(separator: ", ") + ". Mosaïque ne peut pas s’en servir ; ils sont grisés ci-dessous.")
                            .font(.system(size: 11.5)).foregroundStyle(p.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.orange.opacity(0.13)))
            }

            ForEach(categories, id: \.self) { category in
                SettingsGroup(title: category, anchor: category == "Déplacer" ? "keyboard.list" : nil) {
                    ForEach(WindowEngine.shortcutCatalog.filter { $0.category == category }) { shortcut in
                        let blocked = engine.shortcutsEnabled && engine.unavailableShortcuts.contains(shortcut.id)
                        HStack(spacing: 12) {
                            Text(shortcut.action).font(.system(size: 13)).foregroundStyle(p.text)
                            Spacer(minLength: 0)
                            SettingsKeycaps(keys: shortcut.keys)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 12).frame(minHeight: 42)
                        .opacity(blocked ? 0.4 : 1)
                    }
                }
                .opacity(engine.shortcutsEnabled ? 1 : 0.55)
            }
        }
    }
}
