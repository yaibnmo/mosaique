import Foundation
import CoreGraphics

/// Model checks written from the reference behaviour (guides and the site's live demo).
@main
enum LayoutTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() { print("FAIL: " + name); exit(1) }
    }
    static func near(_ a: CGRect, _ b: CGRect, _ t: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) <= t && abs(a.minY - b.minY) <= t && abs(a.width - b.width) <= t && abs(a.height - b.height) <= t
    }

    static func main() {
        let mac = CGRect(x: 0, y: 0, width: 1440, height: 876)
        let g: CGFloat = 8
        let area = mac.insetBy(dx: g, dy: g)

        // The fold: each new window takes half of the newest space.
        let one = TileLayout.frames(in: mac, count: 1, kind: .grid, gap: g)
        expect(near(one[0], area), "1 fenêtre remplit l’écran, à l’intérieur de l’espacement")
        let two = TileLayout.frames(in: mac, count: 2, kind: .grid, gap: g)
        expect(abs(two[0].width - two[1].width) <= 1 && two[0].minX < two[1].minX && two[0].height == area.height, "2 fenêtres côte à côte, la principale à gauche")
        let three = TileLayout.frames(in: mac, count: 3, kind: .grid, gap: g)
        expect(three[0].height == area.height && three[1].minX == three[2].minX && three[1].minY < three[2].minY, "3 fenêtres : la moitié droite se partage en haut et en bas")
        let four = TileLayout.frames(in: mac, count: 4, kind: .grid, gap: g)
        expect(four[0].minX == four[3].minX && four[0].minY < four[3].minY && four[1].minY < four[2].minY && four[1].minX > four[0].minX,
               "4 fenêtres : principale en haut à gauche, puis haut droite, bas droite, bas gauche")
        for frames in [two, three, four] {
            for i in frames.indices { for j in frames.indices where i < j { expect(frames[i].intersection(frames[j]).isNull, "cases disjointes") } }
            expect(frames.allSatisfy { area.contains($0) }, "cases dans la zone utile")
        }
        expect(abs(three[0].maxX + g - three[1].minX) < 0.5 && abs(three[1].maxY + g - three[2].minY) < 0.5, "l’espacement sépare chaque case")

        // Columns: as many as fit at 440 pt; three on a MacBook, four on a 1920 monitor. Equal widths.
        expect(TileLayout.maxColumns(in: mac, gap: g) == 3, "3 colonnes sur un MacBook de 1440 pt")
        expect(TileLayout.maxColumns(in: CGRect(x: 0, y: 0, width: 1920, height: 1080), gap: g) == 4, "4 colonnes sur un écran de 1920 pt")
        expect(TileLayout.capacity(DisplaySettings(kind: .columns, capacity: 4), bounds: mac, gap: g) == 3, "les colonnes en trop ne s’affichent pas")
        let columns = TileLayout.frames(in: mac, count: 3, kind: .columns, gap: g)
        expect(columns.allSatisfy { abs($0.width - columns[0].width) <= 1 && $0.height == area.height }, "colonnes égales, pleine hauteur")
        // Tall screens always use rows, at most three.
        let tall = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        expect(TileLayout.style(.grid, bounds: tall) == .rows && TileLayout.capacity(DisplaySettings(capacity: 4), bounds: tall, gap: g) == 3, "écran vertical : 3 lignes au plus")
        let rows = TileLayout.frames(in: tall, count: 3, kind: .grid, gap: g)
        expect(rows.allSatisfy { $0.width == tall.width - 2 * g } && rows[0].minY < rows[1].minY, "lignes pleine largeur, la principale en haut")

        // Ratios: clamped to 5–95 %, step 5 %, the reference grow rule.
        expect(TileLayout.clampRatio(0.01) == 0.05 && TileLayout.clampRatio(0.99) == 0.95, "proportions bornées entre 5 et 95 %")
        let grid3 = DisplaySettings(kind: .grid, capacity: 3)
        let grown = TileLayout.grow(grid3, tile: 0, count: 3, bounds: mac, step: 0.05)
        expect(abs(grown[0] - 0.55) < 1e-9 && abs(grown[1] - 0.5) < 1e-9, "agrandir la principale déplace la ligne centrale")
        let last = TileLayout.grow(grid3, tile: 2, count: 3, bounds: mac, step: 0.05)
        expect(abs(last[0] - 0.45) < 1e-9 && abs(last[1] - 0.45) < 1e-9, "agrandir la dernière case de la grille réduit les deux précédentes")
        let grid4 = TileLayout.grow(DisplaySettings(kind: .grid, capacity: 4), tile: 3, count: 4, bounds: mac, step: 0.05)
        expect(abs(grid4[0] - 0.55) < 1e-9 && abs(grid4[1] - 0.5) < 1e-9 && abs(grid4[2] - 0.45) < 1e-9, "grille de 4 : la case en bas à gauche grandit des deux côtés")
        var custom = DisplaySettings(kind: .grid, capacity: 2); custom.ratios = [0.7]
        let wide = TileLayout.frames(in: mac, count: 2, kind: .grid, gap: g)
        let resized = TileLayout.plan(in: mac, minimums: [.zero, .zero], settings: custom, gap: g)!.frames
        expect(resized[0].width > wide[0].width && abs(resized[0].width - ((area.width - g) * 0.7).rounded()) <= 1, "une proportion personnalisée s’applique")
        let fitted = TileLayout.bisect(old: [0.5], new: [0.95]) { $0[0] <= 0.8 }
        expect(abs(fitted[0] - 0.8) < 0.001, "la bissection garde le plus grand changement qui respecte les minimums")

        // Dividers report where a dragged edge lands.
        let plan = TileLayout.plan(in: mac, minimums: [.zero, .zero, .zero], settings: grid3, gap: g)!
        let centre = plan.dividers.first { $0.ratioIndex == 0 }!
        expect(centre.vertical && centre.first == [0] && Set(centre.second) == [1, 2], "la ligne centrale sépare la principale des deux autres")
        expect(abs(centre.ratio(forPosition: centre.position, gap: g) - 0.5) < 0.002, "position actuelle = proportion actuelle")
        expect(centre.ratio(forPosition: centre.position + 144, gap: g) > 0.59, "déplacer la ligne vers la droite agrandit la principale")

        // Minimum sizes move the split lines; impossible fits return nil.
        let fit = TileLayout.plan(in: mac, minimums: [CGSize(width: 952, height: 300), .zero], settings: DisplaySettings(capacity: 2), gap: g)!.frames
        expect(fit[0].width >= 952, "une app qui ne rétrécit pas garde sa taille minimale")
        expect(TileLayout.plan(in: mac, minimums: [CGSize(width: 1000, height: 200), CGSize(width: 900, height: 200)], settings: DisplaySettings(capacity: 2), gap: g) == nil, "trop grand : pas de disposition")

        // Direction neighbour: from the primary, → goes to the top of the right column.
        expect(Direction.right.neighbor(of: 0, in: three) == 1, "→ depuis la principale vise la case du haut à droite")
        expect(Direction.down.neighbor(of: 1, in: three) == 2 && Direction.up.neighbor(of: 2, in: three) == 1, "↑ et ↓ dans une colonne")
        expect(Direction.left.neighbor(of: 2, in: three) == 0 && Direction.left.neighbor(of: 0, in: three) == nil, "← vers la principale ; rien au bord")
        expect(Direction.left.neighbor(of: 2, in: four) == 3 && Direction.right.neighbor(of: 3, in: four) == 2, "grille de 4 : voisins horizontaux en bas")

        // Screens.
        let monitors = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        expect(TileLayout.screenIndex(for: CGRect(x: -1800, y: 0, width: 800, height: 600), screens: monitors) == 1, "écran à coordonnées négatives")
        expect(TileLayout.screenIndex(for: .zero, screens: []) == nil, "aucun écran")

        // Float rules: app and the first two words of the title.
        let rule = FloatRule(bundle: "test.editor", prefix: "Push Commits")
        expect(rule.matches(bundle: "test.editor", title: "Push Commits to project") && !rule.matches(bundle: "other", title: "Push Commits") && !rule.matches(bundle: "test.editor", title: "Edit"), "règle de flottement")

        // Stacks.
        var s = StackLayout()
        s.reconcile(ids: [1, 2], capacity: 2, preferred: 1, stack: true)
        expect(s.groups == [[1], [2]], "chaque fenêtre a sa case tant qu’il y a de la place")
        s.reconcile(ids: [1, 2, 3], capacity: 2, preferred: 1, stack: true)
        expect(s.groups == [[1, 3], [2]], "écran plein : la nouvelle fenêtre rejoint la case active, au-dessus, rien d’autre ne bouge")
        s.activate(1)
        expect(s.groups == [[3, 1], [2]], "activer une fenêtre empilée la met au-dessus")
        s.swap(1, 2)
        expect(s.groups == [[3, 2], [1]], "un échange ne déplace que les fenêtres affichées ; chaque pile reste dans sa case")
        s.reconcile(ids: [1, 2, 3], capacity: 3, preferred: 1, stack: true)
        expect(s.groups.count == 3 && Set(s.groups.flatMap { $0 }) == [1, 2, 3], "plus de cases : une fenêtre en attente prend la case libre")
        var close = StackLayout()
        close.reconcile(ids: [1, 2], capacity: 2, preferred: 1, stack: true)
        close.reconcile(ids: [1, 2, 3], capacity: 2, preferred: 1, stack: true)
        close.reconcile(ids: [1, 2, 3, 4], capacity: 2, preferred: 1, stack: true)
        expect(close.groups == [[1, 3, 4], [2]], "les fenêtres s’empilent dans la case active")
        close.reconcile(ids: [1, 3, 4], capacity: 2, preferred: 4, stack: true)
        expect(close.groups == [[1, 4], [3]], "une case libérée va à la fenêtre en attente utilisée le plus récemment")
        close.reconcile(ids: [1, 3], capacity: 2, preferred: nil, stack: true)
        expect(close.groups == [[1], [3]], "fermer la fenêtre affichée : les autres gardent leur ordre")
        var merge = StackLayout()
        merge.reconcile(ids: [1, 2, 3], capacity: 3, preferred: nil, stack: true)
        merge.reconcile(ids: [1, 2, 3], capacity: 2, preferred: nil, stack: true)
        expect(merge.groups == [[1], [3, 2]], "moins de cases : la dernière rejoint la précédente, qui garde sa fenêtre affichée")
        var pinned = StackLayout()
        pinned.reconcile(ids: [1, 2, 3], capacity: 3, preferred: nil, stack: true)
        pinned.move(3, to: 0)
        pinned.reconcile(ids: [1, 2, 3], capacity: 3, preferred: nil, stack: true)
        expect(pinned.groups == [[1, 3], [2]], "ajouter à une pile exprès n’est pas défait aussitôt")
        var float = StackLayout()
        float.reconcile(ids: [1, 2, 3, 4, 5], capacity: 2, preferred: 1, stack: false)
        expect(float.groups.count == 2 && float.groups.allSatisfy { $0.count == 1 }, "« Flotter au milieu » : une fenêtre par case")
        var minimised = StackLayout()
        minimised.reconcile(ids: [1, 2, 3], capacity: 2, preferred: 1, stack: true)
        minimised.reconcile(ids: [1, 2], capacity: 2, preferred: 1, stack: true)
        minimised.reconcile(ids: [1, 2, 3], capacity: 2, preferred: 2, stack: true)
        expect(minimised.groups[0].last == 3, "une fenêtre réduite depuis une pile revient au-dessus de la même case")
        for count in 0...20 {
            for capacity in 1...4 {
                var state = StackLayout()
                let ids = Array(0..<count)
                state.reconcile(ids: ids, capacity: capacity, preferred: ids.first, stack: true)
                expect(Set(state.groups.flatMap { $0 }) == Set(ids) && state.groups.count <= capacity, "aucune fenêtre perdue")
                let flat = state.groups.flatMap { $0 }; expect(Set(flat).count == flat.count, "aucune fenêtre en double")
                state.reconcile(ids: ids.filter { $0 % 2 == 0 }, capacity: capacity, preferred: nil, stack: true)
                expect(Set(state.groups.flatMap { $0 }) == Set(ids.filter { $0 % 2 == 0 }), "fermetures sans perte")
            }
        }
        // Geometry sweep across ratios, counts and screen shapes.
        for bounds in [mac, CGRect(x: 0, y: 0, width: 1920, height: 1080), tall, CGRect(x: -1920, y: 0, width: 1920, height: 1080)] {
            for kind in LayoutKind.allCases {
                for count in 1...4 {
                    for r in stride(from: 0.05, through: 0.95, by: 0.15) {
                        let settings = DisplaySettings(kind: kind, capacity: count, ratios: [r, 1 - r, r])
                        guard let frames = TileLayout.plan(in: bounds, minimums: Array(repeating: .zero, count: count), settings: settings, gap: g)?.frames else { expect(false, "plan"); continue }
                        let inner = bounds.insetBy(dx: g, dy: g)
                        expect(frames.allSatisfy { inner.insetBy(dx: -0.5, dy: -0.5).contains($0) && $0.width > 0 && $0.height > 0 }, "cases valides")
                        for i in frames.indices { for j in frames.indices where i < j { expect(frames[i].intersection(frames[j]).width <= 0.5 || frames[i].intersection(frames[j]).height <= 0.5, "cases sans chevauchement") } }
                    }
                }
            }
        }
        // The window spring settles at 0.62 s with a small overshoot.
        expect(Easing.windowMove(0) == 0 && Easing.windowMove(0.62) == 1 && Easing.windowMove(0.3) > 0.85, "ressort : rapide puis posé")
        expect((0...62).map { Easing.windowMove(Double($0) / 100) }.max()! < 1.02, "dépassement inférieur à 2 %")

        print("PASS: \(checks) vérifications du modèle (pliage, colonnes, lignes, proportions, voisins, piles, ressort).")
    }
}
