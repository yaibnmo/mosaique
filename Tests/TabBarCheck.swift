import AppKit

/// Drives the real grip and hover bar and checks them against the reference sizes and behaviour.
@main
enum TabBarCheck {
    static func main() {
        _ = NSApplication.shared
        var failures = 0
        func check(_ name: String, _ condition: Bool) { print((condition ? "PASS " : "FAIL ") + name); if !condition { failures += 1 } }

        var showing = 1
        func tabs(_ n: Int = 3) -> [StackTab] {
            (0..<n).map { i in StackTab(id: i, title: ["Terminal", "Mail", "Fichiers", "Notes"][i], icon: nil, selected: i == showing, action: { showing = i }) }
        }
        let grip = StackGrip()
        let center = CGPoint(x: 600, y: 700)
        grip.update(center: center, tabs: tabs(1), kind: .active)
        check("poignée simple : zone de 48 × 18 centrée dans l’espacement", grip.frame.size == CGSize(width: 48, height: 18) && abs(grip.frame.midX - center.x) <= 1 && abs(grip.frame.midY - center.y) <= 1)
        let view = grip.contentView as! GripView
        check("poignée simple : aucun segment cliquable", view.segment(at: CGPoint(x: 24, y: 9)) == nil)

        grip.update(center: center, tabs: tabs(), kind: .active)
        let marks = view.markFrames()
        check("pile : une marque par fenêtre", marks.count == 3)
        check("pile : marque affichée 26 × 6, autres 10 × 6", marks[1].size == CGSize(width: 26, height: 6) && marks[0].size == CGSize(width: 10, height: 6) && marks[2].width == 10)
        check("pile : 4 pt entre les marques", abs(marks[1].minX - marks[0].maxX - 4) < 0.01)
        check("pile : zone élargie à 26 + 2 × 14 + 16", grip.frame.width == max(48, 26 + 2 * 14 + 16))
        for index in [0, 2] { check("clic sur la marque \(index + 1)", view.segment(at: CGPoint(x: marks[index].midX, y: marks[index].midY)) == index) }

        let dots = StackGrip()
        dots.update(center: center, tabs: tabs(), kind: .dots)
        let dotMarks = (dots.contentView as! GripView).markFrames()
        check("case inactive : points 16 et 7 pt", dotMarks[1].width == 16 && dotMarks[0].width == 7 && dots.frame.height == 14)

        let hud = StackHUD()
        var primary = 0, scroll = 0
        let actions = [BarAction(title: "Principale", symbol: "sidebar.left", keys: ["⌃", "⌥", "↩"], enabled: false, action: { primary += 1 }),
                       BarAction(title: "Focus", symbol: "arrow.up.left.and.arrow.down.right", keys: ["⌃", "⌥", "Z"], action: {}),
                       BarAction(title: "Flotter", symbol: "square.on.square", keys: ["⌃", "⌥", "F"], action: {})]
        hud.onScroll = { scroll += $0 }
        let area = CGRect(x: 0, y: 0, width: 1440, height: 876)
        hud.show(key: "a", center: CGPoint(x: grip.frame.midX, y: grip.frame.midY), area: area, tabs: tabs(1), actions: actions)
        check("barre sans pile : 440 × 54", hud.frame.size == CGSize(width: 440, height: 54))
        check("barre centrée sur la poignée", abs(hud.frame.midX - grip.frame.midX) <= 1 && abs(hud.frame.midY - grip.frame.midY) <= 1)
        check("clics ignorés pendant 400 ms", !hud.acceptsClicks)
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        check("clics acceptés ensuite", hud.acceptsClicks)
        check("bouton désactivé à 35 %", hud.actionButtons[0].alphaValue == 0.35)
        _ = hud.actionButtons[0].accessibilityPerformPress()
        check("un bouton désactivé ne fait rien", primary == 0)
        hud.dismiss(animated: false)

        hud.show(key: "b", center: CGPoint(x: grip.frame.midX, y: grip.frame.midY), area: area, tabs: tabs(), actions: actions)
        check("barre avec pile : 440 × 90", hud.frame.size == CGSize(width: 440, height: 90))
        check("une puce par fenêtre", hud.chipButtons.map(\.tab.title) == ["Terminal", "Mail", "Fichiers"])
        check("la puce affichée est sélectionnée", hud.chipButtons.filter(\.tab.selected).map(\.tab.id) == [1])
        _ = hud.chipButtons[2].accessibilityPerformPress()
        check("clic sur une puce : la fenêtre change", showing == 2)
        hud.refresh(key: "b", center: CGPoint(x: grip.frame.midX, y: grip.frame.midY), area: area, tabs: tabs(), actions: actions)
        check("la barre suit le changement", hud.chipButtons.filter(\.tab.selected).map(\.tab.id) == [2])
        hud.onScroll?(1)
        check("‹ › et le défilement parcourent la pile", scroll == 1)

        hud.show(key: "c", center: CGPoint(x: 20, y: 870), area: area, tabs: tabs(), actions: actions)
        check("près d’un bord : la barre reste à 6 pt dans l’écran", hud.frame.minX >= 6 && hud.frame.maxY <= area.maxY - 6)
        hud.dismiss(animated: false)
        check("la barre se ferme", !hud.isVisible && hud.anchorKey == nil)

        print(failures == 0 ? "PASS: poignée et barre conformes aux mesures de référence." : "ÉCHEC: \(failures) vérification(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
