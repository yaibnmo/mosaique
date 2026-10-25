import AppKit

@main final class Fixture: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    static func main() { let app = NSApplication.shared; let delegate = Fixture(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() } }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(), submenu = NSMenu(), item = NSMenuItem()
        menu.addItem(item); item.submenu = submenu; submenu.addItem(withTitle: "Quitter les fenêtres de test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); NSApp.mainMenu = menu
        for i in 0..<5 {
            let window = NSWindow(contentRect: CGRect(x: 80 + i * 55, y: 100 + i * 55, width: 520, height: 380), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            window.title = "Mosaïque Test \(i + 1)"; window.minSize = CGSize(width: 240, height: 180); window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "Fenêtre de test \(i + 1)\nAucun document utilisateur"); label.frame = CGRect(x: 24, y: 40, width: 400, height: 80); label.font = .systemFont(ofSize: 22)
            window.contentView?.addSubview(label); window.orderFront(nil); windows.append(window)
        }
    }
}
