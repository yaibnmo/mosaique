import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Pages Apps, Activity and About.

private let groupSpacing = settingsGroupSpacing

/// Names and icons of apps by bundle identifier, looked up once.
enum SettingsAppInfo {
    private static var cache: [String: (name: String, icon: NSImage?)] = [:]
    static func lookup(_ bundle: String) -> (name: String, icon: NSImage?) {
        if let hit = cache[bundle] { return hit }
        var name = WindowEngine.defaultExclusions.first { $0.bundle == bundle }?.name
        var icon: NSImage?
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            name = name ?? running.localizedName; icon = running.icon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            if name == nil { name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
            if icon == nil { icon = NSWorkspace.shared.icon(forFile: url.path) }
        }
        let result = (name ?? bundle, icon)
        cache[bundle] = result
        return result
    }
}

struct SettingsAppLabel: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let bundle: String
    var detail: String? = nil
    var body: some View {
        let info = SettingsAppInfo.lookup(bundle)
        HStack(spacing: 8) {
            Group {
                if let icon = info.icon { Image(nsImage: icon).resizable().interpolation(.high) }
                else { RoundedRectangle(cornerRadius: 5, style: .continuous).fill(p.fill2) }
            }
            .frame(width: 20, height: 20)
            Text(info.name).font(.system(size: 13)).foregroundStyle(p.text).lineLimit(1)
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(p.text2).lineLimit(1) }
        }
    }
}


/// Lays chips out in rows, wrapping like text.
struct SettingsFlow: SwiftUI.Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }
    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }
    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + lineSpacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// A bordered chip with an app icon, like the reference's "Add an open app" buttons.
struct SettingsChip: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let title: String
    var icon: NSImage? = nil
    var symbol: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16) }
                if let symbol { Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(p.text2) }
                Text(title).font(.system(size: 13)).foregroundStyle(p.text).lineLimit(1)
            }
            .padding(.horizontal, 9).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.solid).shadow(color: .black.opacity(0.1), radius: 0.5, x: 0, y: 0.5))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.edge, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Apps

struct SettingsAppsPage: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var engine: WindowEngine
    @State private var showDefaults = false

    private var excluded: [(bundle: String, isDefault: Bool)] {
        let defaults = WindowEngine.defaultExclusions.map(\.bundle).filter { !engine.removedDefaults.contains($0) }
        let mine = engine.exclusions.filter { bundle in !defaults.contains(bundle) }
        let rows = defaults.map { ($0, true) } + mine.map { ($0, false) }
        return rows.sorted { SettingsAppInfo.lookup($0.0).name.localizedCaseInsensitiveCompare(SettingsAppInfo.lookup($1.0).name) == .orderedAscending }
            .map { (bundle: $0.0, isDefault: $0.1) }
    }
    private var openApps: [NSRunningApplication] {
        engine.apps().filter { app in app.bundleIdentifier.map { engine.isTiled(bundle: $0) } ?? false }
    }
    private func size(_ value: Double) -> String { value > 0 ? "\(Int(value.rounded()))" : "Tout" }

    var body: some View {
        VStack(alignment: .leading, spacing: groupSpacing) {
            SettingsGroup(title: "Ne pas ranger ces apps", note: "Leurs fenêtres restent là où tu les mets.", anchor: "apps.exclusions") {
                if excluded.filter({ !$0.isDefault }).isEmpty { plainRow("Mosaïque range toutes les apps.") }
                ForEach(excluded.filter { !$0.isDefault || showDefaults }, id: \.bundle) { row in
                    HStack(spacing: 8) {
                        SettingsAppLabel(bundle: row.bundle)
                        if row.isDefault { SettingsTag(text: "Par défaut") }
                        Spacer(minLength: 0)
                        Button("Retirer") { engine.setTiled(bundle: row.bundle, true) }.buttonStyle(SettingsButtonStyle())
                    }
                    .padding(.vertical, 6).padding(.horizontal, 12).frame(minHeight: 42)
                }
                let defaults = excluded.filter(\.isDefault).count
                if defaults > 0 {
                    SettingsRow(label: "Petits outils laissés de côté par défaut", hint: "\(defaults) apps, comme Calculette ou Réglages Système. Retire-en une pour la ranger quand même.") {
                        Button(showDefaults ? "Masquer" : "Afficher") { withAnimation(.easeOut(duration: 0.2)) { showDefaults.toggle() } }
                            .buttonStyle(SettingsButtonStyle())
                    }
                }
                SettingsFlow {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 12))
                        Text("Ajouter une app ouverte").font(.system(size: 13))
                    }
                    .foregroundStyle(p.text2).frame(height: 24).padding(.trailing, 8)
                    ForEach(openApps, id: \.processIdentifier) { app in
                        SettingsChip(title: app.localizedName ?? app.bundleIdentifier ?? "App", icon: app.icon) {
                            if let id = app.bundleIdentifier { engine.setTiled(bundle: id, false) }
                        }
                    }
                    SettingsChip(title: "Choisir dans Applications…", symbol: "folder") { chooseApps() }
                    if !engine.removedDefaults.isEmpty {
                        SettingsChip(title: "Rétablir les apps par défaut", symbol: "arrow.uturn.backward") { engine.removedDefaults = [] }
                    }
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
            }

            SettingsGroup(title: "Toujours faire flotter ces fenêtres", note: "Les fenêtres de l’app dont le titre commence par ces mots. Ajoute-en une avec ⌃⌥⇧F sur la fenêtre.", anchor: "apps.float") {
                if engine.floatRules.isEmpty { plainRow("Aucune pour l’instant.") }
                ForEach(engine.floatRules) { rule in
                    HStack(spacing: 8) {
                        SettingsAppLabel(bundle: rule.bundle, detail: "« \(rule.prefix) »")
                        Spacer(minLength: 0)
                        Button("Retirer") { engine.floatRules.removeAll { $0.id == rule.id } }.buttonStyle(SettingsButtonStyle())
                    }
                    .padding(.vertical, 6).padding(.horizontal, 12).frame(minHeight: 42)
                }
            }

            SettingsGroup(title: "Apps qui ne rétrécissent pas", note: "Mosaïque retient leur plus petite taille et en tient compte.", anchor: "apps.minimums") {
                if engine.minimumRows.isEmpty { plainRow("Aucune pour l’instant.") }
                ForEach(engine.minimumRows) { row in
                    HStack(spacing: 8) {
                        SettingsAppLabel(bundle: row.id, detail: "\(size(row.width)) × \(size(row.height))")
                        Spacer(minLength: 0)
                        Button("Oublier") { engine.forget(minimum: row.id) }.buttonStyle(SettingsButtonStyle())
                    }
                    .padding(.vertical, 6).padding(.horizontal, 12).frame(minHeight: 42)
                }
                if engine.minimumRows.count > 1 {
                    HStack {
                        Spacer()
                        Button("Tout oublier") { engine.forgetMinimums() }.buttonStyle(SettingsButtonStyle())
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                }
            }

            if !engine.roomCardMuted.isEmpty {
                SettingsGroup(title: "Carte « Besoin de plus de place » masquée", note: "Ces apps ne montrent plus la carte quand leur fenêtre doit flotter faute de place.") {
                    ForEach(engine.roomCardMuted.sorted(), id: \.self) { bundle in
                        HStack(spacing: 8) {
                            SettingsAppLabel(bundle: bundle)
                            Spacer(minLength: 0)
                            Button("Afficher à nouveau") { engine.roomCardMuted.remove(bundle) }.buttonStyle(SettingsButtonStyle())
                        }
                        .padding(.vertical, 6).padding(.horizontal, 12).frame(minHeight: 42)
                    }
                }
            }
        }
    }

    private func plainRow(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(p.text)
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Ne pas ranger"
        panel.message = "Choisis les apps que Mosaïque doit laisser où tu les mets."
        let done: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            for url in panel.urls { if let id = Bundle(url: url)?.bundleIdentifier { engine.setTiled(bundle: id, false) } }
        }
        if let window = SettingsWindowController.shared.window, window.isVisible { panel.beginSheetModal(for: window, completionHandler: done) }
        else { panel.begin(completionHandler: done) }
    }
}

// MARK: Activity

struct SettingsActivityPage: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var engine: WindowEngine
    @State private var confirmReset = false

    static let features: [String: (label: String, keys: [String], tip: String)] = [
        "tabView": ("Tab View", ["⌥", "⇥"], "Voir toutes les fenêtres par écran et en choisir une."),
        "primary": ("Fenêtre principale", ["⌃", "⌥", "↩"], "Mettre la fenêtre active à la place principale."),
        "focus": ("Mode Focus", ["⌃", "⌥", "Z"], "Remplir l’écran avec la fenêtre active, puis la remettre."),
        "noPeek": ("Mode No peek", ["⌃", "⌥", "D"], "Estomper toutes les fenêtres sauf la tienne."),
        "stack": ("Parcourir une pile", ["⌃", "⌥", "`"], "Afficher la fenêtre suivante de la case."),
        "resize": ("Redimensionner", ["⌃", "⌥", "="], "Agrandir la fenêtre active sans souris."),
        "float": ("Faire flotter", ["⌃", "⌥", "F"], "Sortir une fenêtre de la disposition un moment."),
        "cleanSpace": ("Clean Space", ["⌃", "⌥", "P"], "Rendre l’écran uni pour partager ou présenter."),
        "count": ("Nombre de fenêtres", ["⌃", "⌥", "⌘", "1–4"], "Choisir combien de fenêtres partagent cet écran."),
        "move": ("Échanger les fenêtres", ["⌃", "⌥", "←"], "Échanger la fenêtre avec sa voisine."),
        "cycle": ("Fenêtre suivante", ["⌃", "⌥", "]"], "Activer la fenêtre suivante."),
        "reset": ("Rétablir les tailles", ["⌃", "⌥", "0"], "Revenir aux tailles de départ sur cet écran."),
        "swap": ("Échanger à la souris", [], "Maintenir ⌘ et glisser une fenêtre sur une autre."),
        "moveScreen": ("Changer d’écran", [], "Glisser une fenêtre sur l’autre écran."),
        "chip": ("Barre de survol", [], "Passer d’une fenêtre à l’autre d’une pile."),
        "retile": ("Ranger à nouveau", [], "Tout remettre en place depuis la barre des menus."),
    ]
    private static let tryOrder = ["tabView", "primary", "focus", "noPeek", "stack", "resize", "float", "cleanSpace", "count", "reset"]

    private var stats: ActivityStats {
        engine.activity.weekStart == ActivityStats.currentWeek() ? engine.activity : ActivityStats()
    }
    static func saved(_ seconds: Double) -> String {
        if seconds < 60 { return "Moins d’1 min" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    var body: some View {
        let s = stats
        let total = s.keyboard + s.mouse
        let keyboardShare = total > 0 ? s.keyboard / total : 0
        let shortcuts = s.features.filter { !(Self.features[$0.key]?.keys.isEmpty ?? true) && $0.value > 0 }.sorted { $0.value > $1.value }
        let used = shortcuts.reduce(0) { $0 + $1.value }
        let next = Self.tryOrder.first { (s.features[$0] ?? 0) == 0 }
        VStack(alignment: .leading, spacing: groupSpacing) {
            // Hero: windows tiled this week.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(s.placed)").font(.system(size: 46, weight: .bold).monospacedDigit()).foregroundStyle(p.text)
                Text(s.placed == 1 ? "fenêtre rangée cette semaine" : "fenêtres rangées cette semaine").font(.system(size: 15)).foregroundStyle(p.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).frame(height: 92)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LinearGradient(
                colors: p.dark ? [.settingsHex(0x1F3A45), .settingsHex(0x2E3236)] : [.settingsHex(0xDDF2F9), .settingsHex(0xF6FAFC)],
                startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.edge, lineWidth: 0.5))
            .settingsAnchor("activity.stats")

            HStack(alignment: .top, spacing: 12) {
                statCard(title: "Temps gagné", value: Self.saved(s.secondsSaved), detail: "Par rapport au déplacement des fenêtres à la main.")
                statCard(title: "Raccourcis utilisés", value: "\(used)",
                         detail: shortcuts.first.flatMap { Self.features[$0.key] }.map { "Le plus utilisé : \($0.label)." } ?? "Aucun pour l’instant.")
            }
            .fixedSize(horizontal: false, vertical: true)

            SettingsGroup(title: "Tes raccourcis") {
                if shortcuts.isEmpty {
                    Text("Aucun pour l’instant.").font(.system(size: 13)).foregroundStyle(p.text)
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                }
                ForEach(shortcuts, id: \.key) { item in
                    HStack {
                        Text(Self.features[item.key]?.label ?? item.key).font(.system(size: 13)).foregroundStyle(p.text)
                        Spacer()
                        Text("\(item.value)×").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(p.text2)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 42)
                }
                if let next, let info = Self.features[next] {
                    SettingsRow(label: "À essayer ensuite : \(info.label)", hint: info.tip) { SettingsKeycaps(keys: info.keys) }
                }
            }

            SettingsGroup(note: "Des chiffres seulement, gardés sur ce Mac. Jamais de titres de fenêtres ni de noms d’apps.") {
                SettingsRow(label: "Clavier ou souris", hint: total > 0 ? "Clavier \(Int((keyboardShare * 100).rounded())) % · Souris \(100 - Int((keyboardShare * 100).rounded())) %" : "Rien encore cette semaine.") {
                    HStack(spacing: 2) {
                        Capsule().fill(p.accent).frame(width: total > 0 ? max(4, 148 * keyboardShare) : 0)
                        Capsule().fill(total > 0 ? Color.settingsHex(0xFF9F0A) : p.fill2)
                    }
                    .frame(width: 150, height: 6)
                }
                SettingsRow(label: "Compter l’activité", hint: "Désactive pour arrêter de compter ; tes chiffres restent tels quels.", anchor: "activity.count") {
                    SettingsSwitch(isOn: $engine.countActivity)
                }
                SettingsRow(label: "Réinitialiser l’activité", hint: "Remet tous les compteurs à zéro.", anchor: "activity.reset") {
                    Button("Réinitialiser…") { confirmReset = true }.buttonStyle(SettingsButtonStyle())
                }
            }
        }
        .alert("Remettre l’activité à zéro ?", isPresented: $confirmReset) {
            Button("Réinitialiser", role: .destructive) { engine.resetActivity() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous les compteurs de la semaine repartent de zéro.")
        }
    }

    private func statCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.text2)
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(p.text)
            Text(detail).font(.system(size: 11.5)).foregroundStyle(p.text3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.solid))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.edge, lineWidth: 0.5))
    }
}

// MARK: About

struct SettingsAboutPage: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var engine: WindowEngine

    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Version de développement" }
        return "Version \(short)"
    }
    private let promises: [(label: String, hint: String)] = [
        ("Fonctionne sur ce Mac", "Pas de compte, pas de cloud."),
        ("Ne lit jamais les fenêtres", "Ni leurs titres, ni ce qu’elles contiennent."),
        ("N’envoie rien", "Aucune donnée ne quitte ton Mac."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: groupSpacing) {
            VStack(spacing: 6) {
                Image(nsImage: IconStyles.image(for: engine.iconStyle, size: 180)).resizable().interpolation(.high).frame(width: 90, height: 90).frame(width: 72, height: 72)
                    .padding(.bottom, 4)
                Text("Mosaïque").font(.system(size: 20, weight: .bold)).foregroundStyle(p.text)
                Text(version).font(.system(size: 12)).foregroundStyle(p.text3)
            }
            .frame(maxWidth: .infinity)
            .settingsAnchor("about.version")

            SettingsGroup(title: "Conçu pour rester privé", note: "Mosaïque range les fenêtres sans regarder dedans.", anchor: "about.privacy") {
                ForEach(promises, id: \.label) { item in
                    SettingsRow(label: item.label, hint: item.hint)
                }
            }
        }
    }
}
