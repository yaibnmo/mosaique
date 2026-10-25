import SwiftUI
import AppKit

// The settings window: 760×560, a 196 pt sidebar with search, and grouped pages (reference section 6).

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private(set) var window: NSWindow?
    private let nav = SettingsNav()
    private var closing = false

    /// `page` is one of: "general", "layout", "highlight", "mouse", "keyboard", "apps", "activity", "about".
    func show(engine: WindowEngine, page: String? = nil) {
        if let page, SettingsPage.all.contains(where: { $0.id == page }) { nav.page = page; nav.query = "" }
        engine.trusted = AXIsProcessTrusted()
        let w = window ?? makeWindow(engine: engine)
        NSApp.activate(ignoringOtherApps: true)
        guard !w.isVisible || closing else { w.makeKeyAndOrderFront(nil); return }
        closing = false
        // Opens like the reference: fades in while rising 8 pt, 0.3 s on cubic-bezier(.2,.8,.2,1).
        let final = w.frame
        w.alphaValue = 0
        w.setFrame(final.offsetBy(dx: 0, dy: -8), display: false)
        w.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            w.animator().alphaValue = 1
            w.animator().setFrame(final, display: true)
        }
    }

    private func makeWindow(engine: WindowEngine) -> NSWindow {
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Réglages Mosaïque"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.backgroundColor = SettingsPalette.windowBackground
        w.delegate = self
        w.contentView = NSHostingView(rootView: SettingsRoot(engine: engine).environmentObject(nav))
        w.setContentSize(CGSize(width: 760, height: 560))
        w.center()
        w.setFrameAutosaveName("MosaïqueSettings")
        window = w
        return w
    }

    /// Closes with a 0.15 s fade, as in the reference.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing else { return false }
        closing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            sender.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.closing else { return }
            sender.orderOut(nil); sender.alphaValue = 1; self.closing = false
        })
        return false
    }
    func windowDidBecomeKey(_ notification: Notification) {
        // Accessibility may have been granted in System Settings meanwhile.
        NotificationCenter.default.post(name: .settingsWindowDidBecomeKey, object: nil)
    }
}

extension Notification.Name {
    static let settingsWindowDidBecomeKey = Notification.Name("MosaïqueSettingsDidBecomeKey")
}

// MARK: Pages and search index

struct SettingsPage: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let colors: (UInt32, UInt32)

    static let all: [SettingsPage] = [
        SettingsPage(id: "general", title: "Général", symbol: "gearshape", colors: (0x9E9E9E, 0x6B6B6B)),
        SettingsPage(id: "layout", title: "Disposition", symbol: "rectangle.split.2x1", colors: (0x3D9CFF, 0x0A6BE0)),
        SettingsPage(id: "highlight", title: "Surbrillance", symbol: "sparkle", colors: (0xC77DFF, 0x8A40D1)),
        SettingsPage(id: "mouse", title: "Souris", symbol: "cursorarrow", colors: (0xFFAD33, 0xE07800)),
        SettingsPage(id: "keyboard", title: "Clavier", symbol: "command", colors: (0x5C5C5C, 0x303030)),
        SettingsPage(id: "apps", title: "Apps", symbol: "square.grid.2x2", colors: (0x45D66E, 0x1F9E42)),
        SettingsPage(id: "activity", title: "Activité", symbol: "chart.bar.xaxis", colors: (0x3DCCE6, 0x0D8CB5)),
        SettingsPage(id: "about", title: "À propos", symbol: "info.circle", colors: (0xB4B4B9, 0x7D7D83)),
    ]
    static func named(_ id: String) -> SettingsPage { all.first { $0.id == id } ?? all[0] }
}

struct SettingsSearchItem: Identifiable {
    let page: String
    let label: String
    let anchor: String
    var keywords = ""
    var id: String { anchor }

    static let all: [SettingsSearchItem] = [
        .init(page: "general", label: "Rangement automatique", anchor: "general.tiling", keywords: "activer pause arrêter tiling"),
        .init(page: "general", label: "Ouvrir à la connexion", anchor: "general.login", keywords: "démarrage session login éléments de connexion"),
        .init(page: "general", label: "Icône de l’app", anchor: "general.icon", keywords: "apparence washi lanterne indigo couchant torii verre focus"),
        .init(page: "general", label: "Fond de Clean Space", anchor: "general.clean", keywords: "apparence graphite pierre brume partage présentation"),
        .init(page: "general", label: "Accès Accessibilité", anchor: "general.access", keywords: "autorisation permission confidentialité"),
        .init(page: "general", label: "Visite de bienvenue", anchor: "general.tour", keywords: "aide tutoriel"),
        .init(page: "layout", label: "Disposition", anchor: "layout.kind", keywords: "grille colonnes rangées"),
        .init(page: "layout", label: "Fenêtres par écran", anchor: "layout.count", keywords: "nombre plein écran côte à côte grille de quatre"),
        .init(page: "layout", label: "Quand un écran est plein", anchor: "layout.full", keywords: "empiler pile flotter milieu"),
        .init(page: "layout", label: "Déplacer vers un écran plein", anchor: "layout.move", keywords: "échanger empiler écran suivant"),
        .init(page: "layout", label: "Espace entre les fenêtres", anchor: "layout.gap", keywords: "marge écart bords gap"),
        .init(page: "highlight", label: "Surbrillance", anchor: "highlight.mode", keywords: "bordure lueur active toutes"),
        .init(page: "highlight", label: "Épaisseur de bordure", anchor: "highlight.width", keywords: "bordure largeur"),
        .init(page: "highlight", label: "Couleur", anchor: "highlight.color", keywords: "accent violet rose orange vert graphite teinte"),
        .init(page: "highlight", label: "Mode No peek", anchor: "highlight.nopeek", keywords: "assombrir estomper voile confidentialité"),
        .init(page: "highlight", label: "Intensité", anchor: "highlight.dim", keywords: "no peek assombrir"),
        .init(page: "highlight", label: "Flouter les autres fenêtres", anchor: "highlight.blur", keywords: "flou no peek"),
        .init(page: "mouse", label: "Actions rapides au-dessus des fenêtres", anchor: "mouse.quick", keywords: "poignée barre survol"),
        .init(page: "mouse", label: "Activer les fenêtres au survol", anchor: "mouse.hover", keywords: "focus pointeur"),
        .init(page: "mouse", label: "Toujours disponible", anchor: "mouse.always", keywords: "glisser échanger redimensionner pile écran"),
        .init(page: "keyboard", label: "Raccourcis clavier", anchor: "keyboard.master", keywords: "touches contrôle option"),
        .init(page: "keyboard", label: "Liste des raccourcis", anchor: "keyboard.list", keywords: "déplacer activer taille"),
        .init(page: "apps", label: "Ne pas ranger ces apps", anchor: "apps.exclusions", keywords: "exclure exclusions ignorer"),
        .init(page: "apps", label: "Toujours faire flotter ces fenêtres", anchor: "apps.float", keywords: "dialogues règles flotter"),
        .init(page: "apps", label: "Apps qui ne rétrécissent pas", anchor: "apps.minimums", keywords: "taille minimale oublier"),
        .init(page: "activity", label: "Fenêtres rangées cette semaine", anchor: "activity.stats", keywords: "statistiques temps gagné"),
        .init(page: "activity", label: "Compter l’activité", anchor: "activity.count", keywords: "statistiques"),
        .init(page: "activity", label: "Réinitialiser l’activité", anchor: "activity.reset", keywords: "zéro effacer"),
        .init(page: "about", label: "Version", anchor: "about.version", keywords: "à propos"),
        .init(page: "about", label: "Conçu pour rester privé", anchor: "about.privacy", keywords: "confidentialité données"),
    ]

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'")
    }
    static func search(_ query: String) -> [SettingsSearchItem] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let matches = all.filter { item in
            let haystack = fold(item.label + " " + item.keywords + " " + SettingsPage.named(item.page).title)
            return words.allSatisfy { haystack.contains($0) }
        }
        // Label matches first.
        return matches.sorted { a, b in
            let fa = fold(a.label).contains(words[0]), fb = fold(b.label).contains(words[0])
            return fa && !fb
        }
    }
}

// MARK: Root

struct SettingsRoot: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var engine: WindowEngine
    @EnvironmentObject var nav: SettingsNav

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar()
            Rectangle().fill(p.edge).frame(width: 0.5)
            content
        }
        .frame(width: 760, height: 560)
        .background(p.background)
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidBecomeKey)) { _ in
            if engine.trusted != AXIsProcessTrusted() { engine.trusted = AXIsProcessTrusted() }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text(SettingsPage.named(nav.page).title).font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
            .padding(.top, 8)
            Rectangle().fill(p.edge.opacity(0.6)).frame(height: 0.5)
            ScrollViewReader { proxy in
                ScrollView {
                    page.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(nav.page)
                .onAppear { jump(proxy) }
                .onChange(of: nav.target) { jump(proxy) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func jump(_ proxy: ScrollViewProxy) {
        guard let target = nav.target else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .center) }
            nav.target = nil
            nav.flash = target
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { if nav.flash == target { nav.flash = nil } }
        }
    }

    @ViewBuilder private var page: some View {
        switch nav.page {
        case "layout": SettingsLayoutPage(engine: engine)
        case "highlight": SettingsHighlightPage(engine: engine)
        case "mouse": SettingsMousePage(engine: engine)
        case "keyboard": SettingsKeyboardPage(engine: engine)
        case "apps": SettingsAppsPage(engine: engine)
        case "activity": SettingsActivityPage(engine: engine)
        case "about": SettingsAboutPage(engine: engine)
        default: SettingsGeneralPage(engine: engine)
        }
    }
}

// MARK: Sidebar

struct SettingsSidebar: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var nav: SettingsNav
    @FocusState private var searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField.padding(.bottom, 8).padding(.horizontal, 2)
            if nav.query.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(spacing: 2) { ForEach(SettingsPage.all) { navRow($0) } }
            } else {
                results
            }
            Spacer(minLength: 0)
        }
        // 14/10 padding below the traffic lights' strip.
        .padding(.top, 40).padding(.horizontal, 10).padding(.bottom, 14)
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .background(p.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .regular)).foregroundStyle(p.text3)
            TextField("Rechercher", text: $nav.query)
                .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(p.text)
                .focused($searching)
                .onSubmit { if let first = SettingsSearchItem.search(nav.query).first { nav.go(first) } }
                .onExitCommand { nav.query = "" }
            if !nav.query.isEmpty {
                Button { nav.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(p.text3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.fill))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(p.accent.opacity(searching ? 0.6 : 0), lineWidth: 1.5))
    }

    private func navRow(_ page: SettingsPage) -> some View {
        let on = nav.page == page.id
        return Button { nav.page = page.id } label: {
            HStack(spacing: 8) {
                SettingsNavIcon(symbol: page.symbol, colors: page.colors)
                Text(page.title).font(.system(size: 13)).foregroundStyle(on ? Color.white : p.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? p.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var results: some View {
        let found = SettingsSearchItem.search(nav.query)
        return VStack(alignment: .leading, spacing: 2) {
            if found.isEmpty {
                Text("Aucun réglage trouvé").font(.system(size: 12)).foregroundStyle(p.text3).padding(.horizontal, 6).padding(.top, 4)
            }
            ForEach(Array(found.prefix(12).enumerated()), id: \.element.id) { index, item in
                let page = SettingsPage.named(item.page)
                Button { nav.go(item) } label: {
                    HStack(spacing: 8) {
                        SettingsNavIcon(symbol: page.symbol, colors: page.colors)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.label).font(.system(size: 12.5)).foregroundStyle(index == 0 ? Color.white : p.text).lineLimit(1).minimumScaleFactor(0.8)
                            Text(page.title).font(.system(size: 10.5)).foregroundStyle(index == 0 ? Color.white.opacity(0.75) : p.text3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(index == 0 ? p.accent : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
