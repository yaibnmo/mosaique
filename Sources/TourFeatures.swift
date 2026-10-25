import SwiftUI

// The cards of the two feature steps ("Fonctions de base" and "Outils avancés"), each with a
// looping demo done with the keyboard or with the pointer, the hover bar and the menu bar.

enum TourInput: String, CaseIterable { case keyboard, mouse }

struct TourFeature: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let summary: String
    let keys: [String]
    let howKeys: String
    let howMouse: String
    let script: (TourInput) -> TourScript
    /// Shorter text for the small cards of the four-column step.
    var blurb: String { TourFeatures.blurbs[id] ?? summary }
}

enum TourFeatures {
    static let core: [TourFeature] = [tiling, swap, primary, drag, focus, stacks]
    static let power: [TourFeature] = [hoverBar, noPeek, tabView, cleanSpace, floating, resize, count, activity]

    private static var t3: [CGRect] { TourGeo.tiles(3) }

    static let blurbs: [String: String] = [
        "hoverbar": "Les actions utiles, juste au-dessus de la fenêtre active.",
        "nopeek": "Tout s’estompe sauf la fenêtre où tu travailles.",
        "tabview": "Toutes tes fenêtres, écran par écran. Choisis-en une.",
        "clean": "Ta fenêtre seule sur un fond uni, pour partager l’écran.",
        "float": "Sors une fenêtre de la disposition : elle se centre.",
        "resize": "Agrandis-en une, ses voisines lui font de la place.",
        "count": "De 1 à 4 fenêtres par écran, comme tu préfères.",
        "activity": "Les fenêtres rangées et le temps gagné cette semaine."]

    // MARK: Fonctions de base

    static let tiling = TourFeature(
        id: "tiling", symbol: "rectangle.split.3x1", title: "Rangement automatique",
        summary: "Ouvre une fenêtre, elle trouve sa place. Ferme-en une, les autres comblent l’espace.",
        keys: [], howKeys: "Rien à faire : chaque fenêtre qui s’ouvre prend sa place, chaque fenêtre fermée laisse la sienne aux autres.",
        howMouse: "Rien à faire : ouvre et ferme tes fenêtres comme d’habitude, Mosaïque s’occupe du reste.") { input in
        let b = TourScriptBuilder()
        b.then(0.4) { $0.add(1, .notes, TourGeo.tiles(1)[0]) }
        b.then(1.0) { $0.add(2, .safari, TourGeo.tiles(2)[1]); $0.layout([1, 2]) }
        b.then(1.0) { $0.add(3, .terminal, TourGeo.tiles(3)[2]); $0.layout([1, 2, 3]) }
        b.poster()
        b.then(1.1) { $0.add(4, .mail, TourGeo.tiles(4)[3]); $0.layout([1, 2, 3, 4]) }
        b.then(1.3) { $0.remove(2); $0.layout([1, 3, 4]) }
        b.then(1.2) { $0.remove(4); $0.layout([1, 3]) }
        var s = TourDemoState(); s.highlight = "active"
        return b.build("tiling-\(input)", s)
    }

    static let swap = TourFeature(
        id: "swap", symbol: "arrow.left.arrow.right", title: "Échanger deux fenêtres",
        summary: "La fenêtre active change de place avec sa voisine, et prend sa taille.",
        keys: ["⌃", "⌥", "← →"], howKeys: "⌃⌥ et une flèche échange la fenêtre active avec sa voisine dans cette direction.",
        howMouse: "Maintiens ⌘ et glisse une fenêtre par sa barre de titre sur une autre.") { input in
        let b = TourScriptBuilder()
        if input == .keyboard {
            b.press(["⌃", "⌥", "→"], "Échanger à droite") { $0.swap(1, 2) }
            b.poster()
            b.press(["⌃", "⌥", "↓"], "Échanger en dessous") { $0.swap(1, 3) }
            b.press(["⌃", "⌥", "←"], "Échanger à gauche") { $0.swap(1, 2) }
            b.hideKeys()
        } else { cmdDrag(b, id: 3, onto: 2) }
        return b.build("swap-\(input)", .base(active: input == .keyboard ? 1 : 3))
    }

    static let primary = TourFeature(
        id: "primary", symbol: "rectangle.lefthalf.inset.filled", title: "La grande fenêtre",
        summary: "Envoie la fenêtre active à la place principale, la plus grande de l’écran.",
        keys: ["⌃", "⌥", "↩"], howKeys: "⌃⌥↩ échange la fenêtre active avec la fenêtre principale.",
        howMouse: "Repose le pointeur sur la poignée au-dessus de la fenêtre, puis clique sur Principale.") { input in
        let b = TourScriptBuilder()
        if input == .keyboard {
            b.press(["⌃", "⌥", "↩"], "Rendre principale", after: 0.6) { $0.swap(3, 1) }
            b.poster()
            b.hideKeys(after: 0.9)
            b.then(0.3, .tourQuick) { $0.raise(2) }
            b.press(["⌃", "⌥", "↩"], "Rendre principale") { $0.swap(2, 3) }
            b.hideKeys()
        } else {
            let br = t3[2]
            b.then(0, nil) { $0.cursor = CGPoint(x: 250, y: 150) }
            b.move(TourGeo.grip(br), after: 0.3)
            b.then(0.6, .tourQuick) { $0.bar = true }
            b.move(TourGeo.barButton(0, frame: br), after: 0.4)
            b.then(0.35, .tourQuick) { $0.barHot = 0 }
            b.poster()
            b.click(after: 0.4) { $0.bar = false; $0.barHot = nil; $0.swap(3, 1) }
            b.move(CGPoint(x: 120, y: 120), after: 0.6)
        }
        return b.build("primary-\(input)", .base(active: 3))
    }

    static let drag = TourFeature(
        id: "drag", symbol: "hand.draw", title: "Glisser pour échanger",
        summary: "Maintiens ⌘ et glisse une fenêtre sur une autre. Un simple glisser ne range jamais rien.",
        keys: ["⌘", "glisser"], howKeys: "Au clavier, ⌃⌥ et une flèche fait le même échange.",
        howMouse: "Maintiens ⌘, glisse la fenêtre par sa barre de titre et lâche-la sur une autre : la case est mise en évidence.") { input in
        let b = TourScriptBuilder()
        if input == .keyboard {
            b.press(["⌃", "⌥", "←"], "Échanger à gauche") { $0.swap(2, 1) }
            b.poster()
            b.press(["⌃", "⌥", "→"], "Échanger à droite") { $0.swap(2, 1) }
            b.hideKeys()
        } else {
            let tr = t3[1], l = t3[0]
            let grab = CGPoint(x: tr.midX, y: tr.minY + 3)
            b.then(0, nil) { $0.cursor = CGPoint(x: 240, y: 150) }
            b.move(grab, after: 0.3)
            b.then(0.6, .tourQuick) { $0.pressing = true; $0.dragging = true }
            b.then(0.15, .easeInOut(duration: 0.7)) { $0.cursor = CGPoint(x: l.midX, y: l.midY - 30); $0.set(2, tr.offsetBy(dx: l.midX - grab.x, dy: l.midY - 30 - grab.y)) }
            b.then(0.8, .tourQuick) { $0.pressing = false }
            b.then(0.02, .tourWindow) { $0.set(2, tr); $0.dragging = false; $0.toast = "Un simple glisser ne range jamais rien. Maintiens ⌘ pour échanger." }
            b.move(grab, after: 0.9)
            b.then(0.7, .tourQuick) { $0.toast = nil; $0.badge = "⌘"; $0.pressing = true; $0.dragging = true }
            b.then(0.25, .easeInOut(duration: 0.7)) { $0.cursor = CGPoint(x: l.midX, y: l.midY - 30); $0.set(2, tr.offsetBy(dx: l.midX - grab.x, dy: l.midY - 30 - grab.y)); $0.drop = 1 }
            b.poster()
            b.then(0.9, .tourQuick) { $0.pressing = false; $0.badge = nil; $0.drop = nil }
            b.then(0.02, .tourWindow) { $0.set(2, l); $0.set(1, tr); $0.dragging = false }
            b.move(CGPoint(x: 230, y: 130), after: 0.6)
        }
        return b.build("drag-\(input)", .base(active: 2))
    }

    static let focus = TourFeature(
        id: "focus", symbol: "arrow.up.left.and.arrow.down.right", title: "Mode Focus",
        summary: "La fenêtre active remplit l’écran. Rappuie, et tout revient exactement à sa place.",
        keys: ["⌃", "⌥", "Z"], howKeys: "⌃⌥Z agrandit la fenêtre active ; ⌃⌥Z encore la remet à sa place.",
        howMouse: "Repose le pointeur sur la poignée, puis clique sur Focus. Quitter la remet à sa place.") { input in
        let b = TourScriptBuilder()
        let tr = t3[1]
        if input == .keyboard {
            b.press(["⌃", "⌥", "Z"], "Focus") { $0.raise(2); $0.set(2, TourGeo.full); $0.focused = true; $0.focusTag = true }
            b.poster()
            b.hideKeys(after: 0.6)
            b.then(1.0, .tourFade) { $0.focusTag = false }
            b.press(["⌃", "⌥", "Z"], "Remettre à sa place", after: 0.3) { $0.set(2, tr); $0.focused = false }
            b.hideKeys()
        } else {
            b.then(0, nil) { $0.cursor = CGPoint(x: 120, y: 150) }
            b.move(TourGeo.grip(tr), after: 0.3)
            b.then(0.6, .tourQuick) { $0.bar = true }
            b.move(TourGeo.barButton(1, frame: tr), after: 0.4)
            b.then(0.35, .tourQuick) { $0.barHot = 1 }
            b.poster()
            b.click(after: 0.35) { $0.bar = false; $0.barHot = nil; $0.set(2, TourGeo.full); $0.focused = true; $0.focusTag = true }
            b.move(TourGeo.grip(TourGeo.full), after: 0.8)
            b.then(0.6, .tourQuick) { $0.bar = true; $0.focusTag = false }
            b.move(TourGeo.barButton(1, frame: TourGeo.full), after: 0.4)
            b.then(0.35, .tourQuick) { $0.barHot = 1 }
            b.click(after: 0.35) { $0.bar = false; $0.barHot = nil; $0.set(2, tr); $0.focused = false }
            b.move(CGPoint(x: 90, y: 130), after: 0.6)
        }
        return b.build("focus-\(input)", .base(active: 2))
    }

    static let stacks = TourFeature(
        id: "stacks", symbol: "square.stack", title: "Piles",
        summary: "Écran plein ? La nouvelle fenêtre rejoint la case active, par-dessus, sans rien déplacer.",
        keys: ["⌃", "⌥", "`"], howKeys: "⌃⌥` affiche la fenêtre suivante de la case ; ⌃⌥⇧` la précédente.",
        howMouse: "Clique sur un segment orange de la poignée, ou sur une fenêtre dans la barre d’actions.") { input in
        let b = TourScriptBuilder()
        let l = t3[0]
        b.then(0.5) { $0.add(4, .mail, l); $0.stackCount = 2; $0.stackShown = 1; $0.stackApps = [.notes, .mail]; $0.toast = "Empilée dans cette case" }
        b.then(1.4, .tourFade) { $0.toast = nil }
        if input == .keyboard {
            b.press(["⌃", "⌥", "`"], "Fenêtre suivante de la case", after: 0.3) { $0.raise(1); $0.stackShown = 0 }
            b.poster()
            b.press(["⌃", "⌥", "`"], "Fenêtre suivante de la case") { $0.raise(4); $0.stackShown = 1 }
            b.hideKeys()
        } else {
            let marks = TourGeo.marks(count: 2, shown: 1, at: TourGeo.grip(l))
            b.then(0, nil) { $0.cursor = CGPoint(x: 120, y: 150) }
            b.move(CGPoint(x: marks[0].midX - 1, y: marks[0].midY), after: 0.2)
            b.click(after: 0.7) { $0.raise(1); $0.stackShown = 0 }
            b.then(0.7, .tourQuick) { $0.bar = true; $0.barStack = true }
            b.move(TourGeo.barChip(1, frame: l), after: 0.4)
            b.then(0.3, .tourQuick) { $0.chipHot = 1 }
            b.poster()
            b.click(after: 0.4) { $0.raise(4); $0.stackShown = 1; $0.chipHot = nil }
            b.then(0.7, .tourQuick) { $0.bar = false; $0.barStack = false }
            b.move(CGPoint(x: 120, y: 120), after: 0.2)
        }
        return b.build("stacks-\(input)", .base(active: 1))
    }

    // MARK: Outils avancés

    static let hoverBar = TourFeature(
        id: "hoverbar", symbol: "rectangle.topthird.inset.filled", title: "Barre d’actions",
        summary: "Une poignée au-dessus de la fenêtre active. Repose le pointeur dessus : Principale, Focus et Flotter à portée de clic.",
        keys: [], howKeys: "Chaque bouton affiche son raccourci, la barre te les apprend : ⌃⌥↩, ⌃⌥Z, ⌃⌥F.",
        howMouse: "Repose le pointeur sur la poignée : la barre s’ouvre. Éloigne-le, elle se ferme toute seule.") { input in
        let b = TourScriptBuilder()
        if input == .keyboard {
            b.then(0.3, .tourQuick) { $0.bar = true }
            b.press(["⌃", "⌥", "↩"], "Principale", after: 0.6) { $0.barHot = 0; $0.swap(3, 1) }
            b.poster()
            b.then(0.3, .tourQuick) { $0.barHot = nil }
            b.press(["⌃", "⌥", "Z"], "Focus") { $0.barHot = 1; $0.set(3, TourGeo.full); $0.focused = true }
            b.then(0.3, .tourQuick) { $0.barHot = nil }
            b.press(["⌃", "⌥", "Z"], "Quitter Focus") { $0.barHot = 1; $0.set(3, TourGeo.tiles(3)[0]); $0.focused = false }
            b.then(0.3, .tourQuick) { $0.barHot = nil }
            b.hideKeys(after: 0.5)
            b.then(0.3, .tourQuick) { $0.bar = false }
            return b.build("hoverbar-keyboard", .base(active: 3))
        }
        let l = t3[0]
        b.then(0, nil) { $0.cursor = CGPoint(x: 200, y: 150) }
        b.move(TourGeo.grip(l), after: 0.3)
        b.then(0.6, .tourQuick) { $0.bar = true }
        b.move(TourGeo.barButton(0, frame: l), after: 0.35)
        b.then(0.3, .tourQuick) { $0.barHot = 0 }
        b.move(TourGeo.barButton(1, frame: l), after: 0.25, .easeInOut(duration: 0.35))
        b.then(0.3, .tourQuick) { $0.barHot = 1 }
        b.move(TourGeo.barButton(2, frame: l), after: 0.25, .easeInOut(duration: 0.35))
        b.then(0.3, .tourQuick) { $0.barHot = 2 }
        b.poster()
        b.click(after: 0.45) { $0.bar = false; $0.barHot = nil; $0.raise(1); $0.setFloating(1, true); $0.set(1, TourGeo.floating); $0.layout([2, 3]) }
        let f = TourGeo.floating
        b.move(TourGeo.grip(f, floating: true), after: 0.9)
        b.then(0.6, .tourQuick) { $0.bar = true }
        b.move(TourGeo.barButton(2, frame: f, floating: true), after: 0.35)
        b.then(0.3, .tourQuick) { $0.barHot = 2 }
        b.click(after: 0.4) { $0.bar = false; $0.barHot = nil; $0.setFloating(1, false); $0.layout([2, 3, 1]) }
        b.move(CGPoint(x: 150, y: 140), after: 0.6)
        return b.build("hoverbar-mouse", .base(active: 1))
    }

    static let noPeek = TourFeature(
        id: "nopeek", symbol: "eye.slash", title: "Mode No peek",
        summary: "Tout s’estompe sauf la fenêtre où tu travailles : tu te concentres, et personne ne lit par-dessus ton épaule.",
        keys: ["⌃", "⌥", "D"], howKeys: "⌃⌥D estompe les autres fenêtres ; ⌃⌥D encore les ramène.",
        howMouse: "Active No peek dans le panneau de la barre des menus. Clique sur une autre fenêtre : elle passe devant.") { input in
        let b = TourScriptBuilder()
        if input == .keyboard {
            b.press(["⌃", "⌥", "D"], "No peek activé", after: 0.6) { _ in }
            b.then(0, .tourFade) { $0.veil = 0.5 }
            b.poster()
            b.press(["⌃", "⌥", "]"], "Fenêtre suivante", after: 0.9) { $0.raise(2) }
            b.press(["⌃", "⌥", "D"], "No peek désactivé", after: 1.0) { _ in }
            b.then(0, .tourFade) { $0.veil = 0 }
            b.hideKeys()
        } else {
            let tr = t3[1]
            b.then(0, nil) { $0.cursor = CGPoint(x: 220, y: 120) }
            b.move(TourGeo.menuIcon, after: 0.3)
            b.click(after: 0.6) { $0.panel = true }
            b.move(TourGeo.panelNoPeekRow, after: 0.3)
            b.then(0.4, .tourQuick) { $0.panelHot = "nopeek" }
            b.click(after: 0.3) { $0.panelOn.insert("nopeek") }
            b.then(0, .tourFade) { $0.veil = 0.5 }
            b.poster()
            b.move(CGPoint(x: tr.midX, y: tr.midY + 10), after: 0.7)
            b.click(after: 0.6) { $0.panel = false; $0.panelHot = nil; $0.raise(2) }
            b.move(TourGeo.menuIcon, after: 1.0)
            b.click(after: 0.6) { $0.panel = true }
            b.move(TourGeo.panelNoPeekRow, after: 0.3)
            b.then(0.4, .tourQuick) { $0.panelHot = "nopeek" }
            b.click(after: 0.3) { $0.panelOn.remove("nopeek") }
            b.then(0, .tourFade) { $0.veil = 0 }
            b.then(0.6, .tourQuick) { $0.panel = false; $0.panelHot = nil }
        }
        return b.build("nopeek-\(input)", .base(active: 1))
    }

    static let tabView = TourFeature(
        id: "tabview", symbol: "rectangle.3.group", title: "Tab View",
        summary: "Toutes tes fenêtres, écran par écran, là où elles sont. Choisis-en une et vas-y.",
        keys: ["⌥", "⇥"], howKeys: "Maintiens ⌥ et appuie sur ⇥ ; ⇥ encore pour avancer. Lâche ⌥ pour passer à la fenêtre choisie.",
        howMouse: "Ouvre Tab View avec ⌥⇥, puis survole une fenêtre et clique dessus.") { input in
        let b = TourScriptBuilder()
        b.press(["⌥", "⇥"], "Tab View", after: 0.6, hold: true) { _ in }
        b.then(0.12, .easeOut(duration: 0.14)) { $0.tab = true; $0.tabPick = 2 }
        if input == .keyboard {
            b.poster()
            b.then(0.8, .tourQuick) { $0.keysDown = false }
            b.then(0.25, .tourQuick) { $0.keysDown = true; $0.tabPick = 3 }
            b.then(0.9, .tourQuick) { $0.keysDown = false; $0.keys = ["⌥"]; $0.caption = "Lâche ⌥" }
            b.then(0.3, .easeOut(duration: 0.12)) { $0.tab = false; $0.raise(3) }
            b.hideKeys(after: 0.5)
        } else {
            let tile = TourGeo.tabTile(t3[2])
            b.then(0, nil) { $0.cursor = CGPoint(x: 200, y: 160) }
            b.move(CGPoint(x: tile.midX, y: tile.midY), after: 0.4)
            b.then(0.45, .tourQuick) { $0.tabPick = 3 }
            b.poster()
            b.click(after: 0.5) { $0.tab = false; $0.raise(3); $0.keys = []; $0.caption = nil; $0.keysDown = false }
            b.move(CGPoint(x: 120, y: 120), after: 0.6)
        }
        return b.build("tabview-\(input)", .base(active: 1))
    }

    static let cleanSpace = TourFeature(
        id: "clean", symbol: "rectangle.inset.filled", title: "Clean Space",
        summary: "Pour partager ton écran : la fenêtre active s’affiche seule, sur un fond uni. Rien n’est fermé ni déplacé.",
        keys: ["⌃", "⌥", "P"], howKeys: "⌃⌥P referme l’écran autour de la fenêtre active ; ⌃⌥P encore et tout revient.",
        howMouse: "Active Clean Space dans le panneau de la barre des menus.") { input in
        let b = TourScriptBuilder()
        let tr = t3[1]
        func on(_ b: TourScriptBuilder) {
            b.then(0, .tourClean) { $0.cleanMeet = tr.midX; $0.cleanOn = true }
            b.then(0, .tourWindow) { $0.set(2, TourGeo.full) }
        }
        func off(_ b: TourScriptBuilder) {
            b.then(0, .tourClean) { $0.cleanMeet = nil }
            b.then(0, .tourWindow) { $0.set(2, tr) }
            b.then(0.4, nil) { $0.cleanOn = false }
        }
        if input == .keyboard {
            b.press(["⌃", "⌥", "P"], "Clean Space", after: 0.6) { _ in }
            on(b)
            b.poster()
            b.press(["⌃", "⌥", "P"], "Tout revient", after: 1.6) { _ in }
            off(b)
            b.hideKeys()
        } else {
            b.then(0, nil) { $0.cursor = CGPoint(x: 200, y: 120) }
            b.move(TourGeo.menuIcon, after: 0.3)
            b.click(after: 0.6) { $0.panel = true }
            b.move(TourGeo.panelCleanRow, after: 0.3)
            b.then(0.4, .tourQuick) { $0.panelHot = "clean" }
            b.click(after: 0.3) { $0.panelOn.insert("clean") }
            on(b)
            b.poster()
            b.then(1.6, .tourQuick) { $0.panelHot = "clean" }
            b.click(after: 0.3) { $0.panelOn.remove("clean") }
            off(b)
            b.then(0.5, .tourQuick) { $0.panel = false; $0.panelHot = nil }
        }
        return b.build("clean-\(input)", .base(active: 2))
    }

    static let floating = TourFeature(
        id: "float", symbol: "macwindow.on.rectangle", title: "Fenêtres flottantes",
        summary: "Sors une fenêtre de la disposition : elle se centre, les autres comblent sa place.",
        keys: ["⌃", "⌥", "F"], howKeys: "⌃⌥F fait flotter la fenêtre active ; ⌃⌥F encore la range à nouveau.",
        howMouse: "Clique sur Flotter dans la barre d’actions ; sur une fenêtre flottante, Ranger la remet en place.") { input in
        let b = TourScriptBuilder()
        let f = TourGeo.floating, br = t3[2]
        let float: (inout TourDemoState) -> Void = { $0.raise(3); $0.setFloating(3, true); $0.set(3, f); $0.layout([1, 2]) }
        let tile: (inout TourDemoState) -> Void = { $0.setFloating(3, false); $0.layout([1, 2, 3]) }
        if input == .keyboard {
            b.press(["⌃", "⌥", "F"], "Flotter", after: 0.6, float)
            b.poster()
            b.press(["⌃", "⌥", "F"], "Ranger à nouveau", after: 1.4, tile)
            b.hideKeys()
        } else {
            b.then(0, nil) { $0.cursor = CGPoint(x: 120, y: 150) }
            b.move(TourGeo.grip(br), after: 0.3)
            b.then(0.6, .tourQuick) { $0.bar = true }
            b.move(TourGeo.barButton(2, frame: br), after: 0.4)
            b.then(0.3, .tourQuick) { $0.barHot = 2 }
            b.click(after: 0.4) { $0.bar = false; $0.barHot = nil; float(&$0) }
            b.poster()
            b.move(TourGeo.grip(f, floating: true), after: 0.9)
            b.then(0.6, .tourQuick) { $0.bar = true }
            b.move(TourGeo.barButton(2, frame: f, floating: true), after: 0.4)
            b.then(0.3, .tourQuick) { $0.barHot = 2 }
            b.click(after: 0.4) { $0.bar = false; $0.barHot = nil; tile(&$0) }
            b.move(CGPoint(x: 90, y: 140), after: 0.6)
        }
        return b.build("float-\(input)", .base(active: 3))
    }

    static let resize = TourFeature(
        id: "resize", symbol: "arrow.left.and.right", title: "Redimensionner",
        summary: "Agrandis une fenêtre : ses voisines lui font de la place et tout reste rangé.",
        keys: ["⌃", "⌥", "= −"], howKeys: "⌃⌥= agrandit la fenêtre active, ⌃⌥- la réduit, ⌃⌥0 rend la même taille à tout le monde.",
        howMouse: "Glisse le bord entre deux fenêtres, comme pour n’importe quelle fenêtre du Mac.") { input in
        let b = TourScriptBuilder()
        let ids = [1, 2, 3]
        if input == .keyboard {
            b.press(["⌃", "⌥", "="], "Agrandir", after: 0.6) { $0.layout(ids, ratio: 0.56) }
            b.poster()
            b.press(["⌃", "⌥", "="], "Agrandir") { $0.layout(ids, ratio: 0.62) }
            b.press(["⌃", "⌥", "0"], "Rétablir les tailles", after: 0.9) { $0.layout(ids) }
            b.hideKeys()
        } else {
            let edge = { (r: CGFloat) -> CGFloat in TourGeo.tiles(3, ratio: r)[0].maxX + TourGeo.gap / 2 }
            let y = TourGeo.inner.midY
            b.then(0, nil) { $0.cursor = CGPoint(x: 230, y: 160) }
            b.move(CGPoint(x: edge(0.5), y: y), after: 0.3)
            b.then(0.6, .tourQuick) { $0.divider = CGPoint(x: edge(0.5), y: y) }
            b.then(0.4, .tourQuick) { $0.pressing = true }
            b.then(0.15, .easeInOut(duration: 0.8)) { $0.cursor = CGPoint(x: edge(0.66), y: y); $0.divider = CGPoint(x: edge(0.66), y: y); $0.layout(ids, ratio: 0.66) }
            b.poster()
            b.then(1.0, .easeInOut(duration: 0.7)) { $0.cursor = CGPoint(x: edge(0.4), y: y); $0.divider = CGPoint(x: edge(0.4), y: y); $0.layout(ids, ratio: 0.4) }
            b.then(0.9, .tourQuick) { $0.pressing = false }
            b.then(0.5, .tourQuick) { $0.divider = nil }
            b.move(CGPoint(x: 230, y: 150), after: 0.1)
        }
        return b.build("resize-\(input)", .base(active: 1))
    }

    static let count = TourFeature(
        id: "count", symbol: "square.grid.2x2", title: "Fenêtres par écran",
        summary: "Choisis combien de fenêtres partagent chaque écran, de 1 à 4. Les autres attendent dans une pile.",
        keys: ["⌃", "⌥", "⌘", "1–4"], howKeys: "⌃⌥⌘ et un chiffre de 1 à 4 règle cet écran, dans ce Space.",
        howMouse: "Choisis 1, 2, 3 ou 4 sous « Fenêtres sur cet écran » dans le panneau de la barre des menus.") { input in
        let b = TourScriptBuilder()
        let two: (inout TourDemoState) -> Void = { s in s.layout([1, 2]); s.set(3, TourGeo.tiles(2)[1]); s.raise(2); s.panelCount = 2 }
        let four: (inout TourDemoState) -> Void = { s in
            if !s.wins.contains(where: { $0.id == 4 }) { s.add(4, .mail, TourGeo.tiles(4)[3]) }
            s.layout([1, 2, 3, 4]); s.raise(3); s.panelCount = 4
        }
        let three: (inout TourDemoState) -> Void = { s in s.remove(4); s.layout([1, 2, 3]); s.raise(1); s.panelCount = 3 }
        if input == .keyboard {
            b.press(["⌃", "⌥", "⌘", "2"], "Jusqu’à 2 fenêtres", after: 0.6, two)
            b.poster()
            b.press(["⌃", "⌥", "⌘", "4"], "Jusqu’à 4 fenêtres", after: 1.0, four)
            b.press(["⌃", "⌥", "⌘", "3"], "Jusqu’à 3 fenêtres", after: 1.0, three)
            b.hideKeys()
        } else {
            b.then(0, nil) { $0.cursor = CGPoint(x: 200, y: 120) }
            b.move(TourGeo.menuIcon, after: 0.3)
            b.click(after: 0.6) { $0.panel = true }
            for (n, effect) in [(2, two), (4, four), (3, three)] {
                b.move(TourGeo.panelCount(n), after: 0.4)
                b.then(0.4, .tourQuick) { $0.panelHot = "count\(n)" }
                b.click(after: 0.3, effect)
                if n == 2 { b.poster() }
            }
            b.then(0.8, .tourQuick) { $0.panel = false; $0.panelHot = nil }
            b.move(CGPoint(x: 160, y: 140), after: 0.2)
        }
        return b.build("count-\(input)", .base(active: 1))
    }

    static let activity = TourFeature(
        id: "activity", symbol: "chart.bar", title: "Activité",
        summary: "Combien de fenêtres Mosaïque a rangées pour toi cette semaine, et le temps gagné. Des chiffres seulement, gardés sur ce Mac.",
        keys: [], howKeys: "Chaque raccourci compte : Activité te montre ceux que tu utilises le plus, et lequel essayer ensuite.",
        howMouse: "Glisser, redimensionner par un bord, la barre d’actions et le panneau comptent aussi.") { input in
        let b = TourScriptBuilder()
        b.then(0.3, .tourFade) { $0.activity = 0; $0.activityMouse = input == .mouse }
        for n in [24, 57, 93, 128] { b.then(0.45, .easeOut(duration: 0.4)) { $0.activity = n } }
        b.poster()
        b.then(2.0, .tourFade) { $0.activity = nil }
        var s = TourDemoState.base(active: 1); s.grip = false
        return b.build("activity-\(input)", s)
    }

    /// ⌘-drag `id` by its title bar onto `target`; both trade places with the window spring.
    private static func cmdDrag(_ b: TourScriptBuilder, id: Int, onto target: Int) {
        let from = TourDemoState.base().frame(id), to = TourDemoState.base().frame(target)
        let grab = CGPoint(x: from.midX, y: from.minY + 3)
        let drop = CGPoint(x: to.midX, y: to.midY - 10)
        b.then(0, nil) { $0.cursor = CGPoint(x: 120, y: 150) }
        b.move(grab, after: 0.3)
        b.then(0.6, .tourQuick) { $0.badge = "⌘"; $0.pressing = true; $0.dragging = true }
        b.then(0.3, .easeInOut(duration: 0.75)) { $0.cursor = drop; $0.set(id, from.offsetBy(dx: drop.x - grab.x, dy: drop.y - grab.y)); $0.drop = target }
        b.poster()
        b.then(0.9, .tourQuick) { $0.pressing = false; $0.badge = nil; $0.drop = nil }
        b.then(0.02, .tourWindow) { $0.set(id, to); $0.set(target, from); $0.dragging = false }
        b.move(CGPoint(x: to.midX, y: to.maxY - 20), after: 0.6)
    }
}

// MARK: Cards

struct TourKeycaps: View {
    let keys: [String]
    var size: CGFloat = 11
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                Text(k).font(.system(size: size, weight: .medium)).lineLimit(1).fixedSize()
                    .padding(.horizontal, k.count > 1 ? 4 : 0)
                    .frame(minWidth: size * 2, minHeight: size * 1.55)
                    .background(RoundedRectangle(cornerRadius: 4).fill(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
            }
        }
        .foregroundStyle(TourPalette(scheme).text2)
    }
}

struct TourFeatureCard: View {
    let feature: TourFeature
    let input: TourInput
    var compact = false
    let open: () -> Void
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TourPalette(scheme)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                TourDemoPlayer(script: feature.script(input), playing: hover, corner: 7)
                    .padding(6)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(feature.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 0)
                        if !compact && !feature.keys.isEmpty && input == .keyboard { TourKeycaps(keys: feature.keys, size: 9.5) }
                    }
                    Text(compact ? feature.blurb : feature.summary).font(.system(size: 11.5)).foregroundStyle(p.text2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                }
                .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 2)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.solid))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(hover ? Color.tourAccent.opacity(0.6) : p.edge, lineWidth: hover ? 1 : 0.5))
            .shadow(color: .black.opacity(hover ? 0.12 : 0.04), radius: hover ? 10 : 3, y: hover ? 4 : 1)
            .scaleEffect(hover ? 1.012 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hover = h } }
        .accessibilityLabel(feature.title)
    }
}

/// Larger demo shown when a card is clicked, with the Keyboard | Mouse switch and the previous/next cards.
struct TourFeatureDetail: View {
    let features: [TourFeature]
    @Binding var index: Int?
    @Binding var input: TourInput
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TourPalette(scheme)
        if let i = index, features.indices.contains(i) {
            let f = features[i]
            ZStack {
                Color.black.opacity(scheme == .dark ? 0.45 : 0.25).ignoresSafeArea()
                    .onTapGesture { close() }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: f.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Color.tourAccent.gradient))
                        Text(f.title).font(.system(size: 19, weight: .bold)).foregroundStyle(p.text)
                        Spacer()
                        TourInputSwitch(input: $input)
                        Button(action: close) {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(p.text2)
                                .frame(width: 24, height: 24).background(Circle().fill(p.fill))
                        }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Fermer")
                    }
                    TourDemoPlayer(script: f.script(input), playing: true, corner: 10)
                        .id("\(f.id)-\(input)")
                        .frame(maxWidth: .infinity)
                    Text(f.summary).font(.system(size: 13.5)).foregroundStyle(p.text).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: input == .keyboard ? "keyboard" : "cursorarrow.rays").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.tourAccent).frame(width: 18)
                        Text(input == .keyboard ? f.howKeys : f.howMouse).font(.system(size: 12.5)).foregroundStyle(p.text2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if input == .keyboard && !f.keys.isEmpty { TourKeycaps(keys: f.keys, size: 11) }
                    }
                    HStack {
                        Button { go(-1) } label: { Label("Précédente", systemImage: "chevron.left") }
                            .buttonStyle(TourButtonStyle(kind: .secondary)).disabled(i == 0).opacity(i == 0 ? 0.4 : 1)
                        Spacer()
                        Text("\(i + 1) sur \(features.count)").font(.system(size: 11.5)).foregroundStyle(p.text3).monospacedDigit()
                        Spacer()
                        Button { go(1) } label: { HStack(spacing: 4) { Text("Suivante"); Image(systemName: "chevron.right") } }
                            .buttonStyle(TourButtonStyle(kind: .secondary)).disabled(i == features.count - 1).opacity(i == features.count - 1 ? 0.4 : 1)
                    }
                }
                .padding(20)
                .frame(width: 640)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.glass))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.edge, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private func close() { withAnimation(.easeOut(duration: 0.2)) { index = nil } }
    private func go(_ d: Int) { if let i = index { withAnimation(.easeInOut(duration: 0.2)) { index = min(max(0, i + d), features.count - 1) } } }
}

struct TourInputSwitch: View {
    @Binding var input: TourInput
    var body: some View {
        TourSegmented(selection: $input, options: [(.keyboard, "Clavier", "keyboard"), (.mouse, "Souris", "computermouse")])
            .frame(width: 190)
    }
}

/// One step listing feature cards in a grid.
struct TourFeatureStep: View {
    let title: String
    let subtitle: String
    let features: [TourFeature]
    let columns: Int
    @ObservedObject var model: TourModel
    @Binding var detail: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                TourHeading(title: title, subtitle: subtitle)
                Spacer(minLength: 20)
                TourInputSwitch(input: $model.input).padding(.bottom, 2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columns), spacing: 14) {
                ForEach(Array(features.enumerated()), id: \.element.id) { i, f in
                    TourFeatureCard(feature: f, input: model.input, compact: columns > 3) { withAnimation(.easeOut(duration: 0.22)) { detail = i } }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
