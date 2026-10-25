import SwiftUI
import AppKit
import Darwin

// All copies share a lock, including copies in Downloads. The kernel releases it on exit/crash.
final class InstanceLock {
    private let descriptor: Int32
    init?() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mosaïque", isDirectory: true)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { return nil }
        descriptor = Darwin.open(root.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(descriptor); return nil }
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}

@main enum MosaiqueMain {
    static func main() {
        guard let lock = InstanceLock() else { fputs("Mosaïque est déjà ouverte ou le verrou est inaccessible.\n", stderr); return }
        let app = NSApplication.shared
        let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.yaibnmo.mosaique").first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
        if let other { other.activate(); fputs("Une autre copie de Mosaïque est déjà ouverte.\n", stderr); return }
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime((lock, delegate)) { app.run() }
    }
}

/// Mosaïque lives in the menu bar: no Dock icon. Settings and the tour bring it forward when open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = WindowEngine()
    private var menuBar: MenuBarController!
    private var tabView: TabViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        IconStyles.apply(engine.iconStyle)
        menuBar = MenuBarController(engine: engine)
        menuBar.openSettings = { [weak self] page in self?.openSettings(page) }
        tabView = TabViewController(engine: engine)
        engine.showSettings = { [weak self] page in self?.openSettings(page) }
        engine.overviewStep = { [weak self] step in self?.tabView.open(step: step) }
        engine.showOverview = { [weak self] in self?.tabView.open(step: 1) }
        engine.didUpdate = { [weak self] in self?.menuBar.refresh() }
        // The tour runs on the first launch; nothing moves until it ends with "Ranger mon espace".
        if !engine.setupDone && !engine.qaMode { TourController.shared.show(engine: engine) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(nil); return true }
    func applicationWillTerminate(_ notification: Notification) { engine.noPeek = false; if engine.cleanSpace { engine.toggleCleanSpace() }; engine.endFocus() }
    private func openSettings(_ page: String?) { SettingsWindowController.shared.show(engine: engine, page: page) }
    private func setupMainMenu() {
        let menu = NSMenu(), appMenu = NSMenu(), item = NSMenuItem()
        menu.addItem(item); item.submenu = appMenu
        let settings = NSMenuItem(title: "Réglages…", action: #selector(showSettingsMenu), keyEquivalent: ","); settings.target = self; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Fermer la fenêtre", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quitter Mosaïque", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "Édition"); edit.submenu = editMenu; menu.addItem(edit)
        editMenu.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
    }
    @objc private func showSettingsMenu() { openSettings(nil) }
}
