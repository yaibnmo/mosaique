import AppKit
import ApplicationServices
import Carbon
import Combine
import ServiceManagement

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSManagedDisplayGetCurrentSpace") private func CGSManagedDisplayGetCurrentSpace(_ cid: Int32, _ display: CFString) -> UInt64

/// A screen in the macOS Space currently shown on it. Layout choices and sizes belong to this pair.
struct DisplayOption: Identifiable, Equatable {
    let id: String
    let uuid: String
    let space: UInt64
    let name: String
    /// Usable area (below the menu bar, beside the Dock), in Accessibility coordinates.
    let frame: CGRect
}

struct WindowRow: Identifiable {
    let id: Int
    let app: String
    let title: String
    let minimized: Bool
    let floating: Bool
    let waiting: Bool
    let screen: String
    let screenID: String
    let frame: CGRect
    let icon: NSImage?
    let pid: pid_t
}

struct PreviewPane: Identifiable {
    let id: Int
    /// Position inside the screen, from 0 to 1.
    let unit: CGRect
    let app: String
    let icon: NSImage?
    let active: Bool
    let stackCount: Int
    let focus: Bool
}

struct ShortcutInfo: Identifiable {
    let id: String
    let category: String
    let action: String
    let keys: [String]
}

struct MinimumRow: Identifiable {
    let id: String
    let name: String
    let width: Double
    let height: Double
}

struct ActivityStats: Codable, Equatable {
    var weekStart = ActivityStats.currentWeek()
    var placed = 0
    var keyboard = 0.0
    var mouse = 0.0
    var features: [String: Int] = [:]
    static func currentWeek() -> Date { Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: Date())?.start ?? Date() }
    /// The reference estimate: 4 s per window placed, 2 s per shortcut or mouse move.
    var secondsSaved: Double { Double(placed) * 4 + (keyboard + mouse) * 2 }
}

enum StatusKind { case active, paused, off, attention }

final class WindowEngine: ObservableObject {
    // MARK: Settings (saved)
    @Published private(set) var autoStart = true
    @Published var setupDone = false { didSet { persist() } }
    @Published var gap: Double = 8 { didSet { if oldValue != gap { persist(); arrange() } } }
    @Published var defaultKind: LayoutKind = .grid { didSet { persist(); arrange() } }
    @Published var defaultCapacity = 3 { didSet { persist(); arrange() } }
    @Published var whenFull = "stack" { didSet { persist(); arrange() } }
    @Published var moveIntoFull = "swap" { didSet { persist() } }
    @Published var hoverFocus = false { didSet { persist() } }
    @Published var quickActions = true { didSet { persist(); updateDecorations() } }
    @Published var floatRules: [FloatRule] = [] { didSet { catalog.floatRules = floatRules; persist(); arrange() } }
    @Published var borderWidth = 3.0 { didSet { persist(); arrange() } }
    @Published var highlight = "none" { didSet { persist(); arrange(); updateDecorations() } }
    @Published var tintName = "accent" { didSet { persist(); updateDecorations() } }
    @Published var customColor = NSColor.systemTeal { didSet { persist(); updateDecorations() } }
    @Published var dimAmount = 0.5 { didSet { persist(); updateDecorations() } }
    @Published var blurOthers = true { didSet { persist(); updateDecorations() } }
    @Published var cleanBackground = "graphite" { didSet { persist(); cleanPanel.color(cleanColor) } }
    @Published var iconStyle = "washi" { didSet { persist() } }
    @Published var shortcutsEnabled = true { didSet { persist(); installHotkeys() } }
    @Published var exclusions: Set<String> = [] { didSet { applyExclusions(); persist() } }
    @Published var removedDefaults: Set<String> = [] { didSet { applyExclusions(); persist() } }
    @Published var roomCardMuted: Set<String> = [] { didSet { persist() } }
    @Published var countActivity = true { didSet { persist() } }
    @Published var activity = ActivityStats()
    @Published var displaySettings: [String: DisplaySettings] = [:]

    // MARK: State
    @Published var enabled = false
    @Published var trusted = AXIsProcessTrusted()
    @Published var message = ""
    @Published var shortcutIssue = ""
    @Published var unavailableShortcuts: [String] = []
    @Published var secureInput = false
    @Published var focusActive = false
    @Published var noPeek = false { didSet { updateDecorations() } }
    @Published private(set) var cleanSpace = false
    @Published var displays: [DisplayOption] = []
    @Published var selectedDisplay = ""
    @Published var windowRows: [WindowRow] = []
    @Published var pendingRule: FloatRule?
    @Published var loginMessage = ""
    @Published var minimumRows: [MinimumRow] = []
    @Published var testReport = ""

    var showSettings: ((String?) -> Void)?
    var showOverview: (() -> Void)?
    var overviewStep: ((Int) -> Void)?
    var didUpdate: (() -> Void)?

    let catalog = WindowCatalog()
    let qaMode = ProcessInfo.processInfo.arguments.contains("--qa-mode")

    static let defaultExclusions: [(bundle: String, name: String)] = [
        ("com.apple.ScreenContinuity", "Recopie de l’iPhone"), ("com.apple.iphonesimulator", "Simulator"), ("com.apple.calculator", "Calculette"),
        ("com.apple.systempreferences", "Réglages Système"), ("com.apple.Stickies", "Stickies"), ("com.apple.clock", "Horloge"),
        ("com.apple.PhotoBooth", "Photo Booth"), ("com.apple.QuickTimePlayerX", "QuickTime Player"), ("com.apple.Magnifier", "Loupe"),
        ("com.apple.DeskView", "Vue du bureau"), ("com.apple.DigitalColorMeter", "Colorimètre numérique"), ("com.apple.screenshot.launcher", "Capture d’écran"),
        ("com.apple.archiveutility", "Utilitaire d’archive"), ("com.apple.installer", "Programme d’installation"), ("com.apple.iOSAppInstaller", "Installation d’apps iOS"),
        ("com.apple.MigrateAssistant", "Assistant migration"), ("com.apple.CaptiveNetworkAssistant", "Connexion au Wi‑Fi"), ("com.apple.ProblemReporter", "Rapport « quitter inopinément »")]
    static let defaultExcludedNames: Set<String> = ["Desk View", "Vue du bureau", "Magnifier", "Loupe", "iOS App Installer"]

    private static let baseCatalog: [ShortcutInfo] = [
        ShortcutInfo(id: "left", category: "Déplacer", action: "Échanger avec la fenêtre à gauche", keys: ["⌃", "⌥", "←"]),
        ShortcutInfo(id: "right", category: "Déplacer", action: "Échanger avec la fenêtre à droite", keys: ["⌃", "⌥", "→"]),
        ShortcutInfo(id: "up", category: "Déplacer", action: "Échanger avec la fenêtre au-dessus", keys: ["⌃", "⌥", "↑"]),
        ShortcutInfo(id: "down", category: "Déplacer", action: "Échanger avec la fenêtre en dessous", keys: ["⌃", "⌥", "↓"]),
        ShortcutInfo(id: "primary", category: "Activer", action: "Rendre la fenêtre active principale", keys: ["⌃", "⌥", "↩"]),
        ShortcutInfo(id: "next", category: "Activer", action: "Activer la fenêtre suivante", keys: ["⌃", "⌥", "]"]),
        ShortcutInfo(id: "previous", category: "Activer", action: "Activer la fenêtre précédente", keys: ["⌃", "⌥", "["]),
        ShortcutInfo(id: "stackNext", category: "Activer", action: "Afficher la fenêtre suivante de cette case", keys: ["⌃", "⌥", "`"]),
        ShortcutInfo(id: "stackPrevious", category: "Activer", action: "Afficher la fenêtre précédente de cette case", keys: ["⌃", "⌥", "⇧", "`"]),
        ShortcutInfo(id: "tabView", category: "Activer", action: "Voir toutes les fenêtres par écran et en choisir une", keys: ["⌥", "⇥"]),
        ShortcutInfo(id: "tabViewBack", category: "Activer", action: "Tab View, en arrière", keys: ["⌥", "⇧", "⇥"]),
        ShortcutInfo(id: "bigger", category: "Taille", action: "Agrandir la fenêtre active", keys: ["⌃", "⌥", "="]),
        ShortcutInfo(id: "smaller", category: "Taille", action: "Réduire la fenêtre active", keys: ["⌃", "⌥", "-"]),
        ShortcutInfo(id: "reset", category: "Taille", action: "Rétablir les tailles sur cet écran", keys: ["⌃", "⌥", "0"]),
        ShortcutInfo(id: "float", category: "Plus", action: "Faire flotter la fenêtre active, ou la ranger à nouveau", keys: ["⌃", "⌥", "F"]),
        ShortcutInfo(id: "alwaysFloat", category: "Plus", action: "Toujours faire flotter les fenêtres comme celle-ci", keys: ["⌃", "⌥", "⇧", "F"]),
        ShortcutInfo(id: "focus", category: "Plus", action: "Remplir l’écran avec la fenêtre active, ou la remettre", keys: ["⌃", "⌥", "Z"]),
        ShortcutInfo(id: "noPeek", category: "Plus", action: "Mode No peek", keys: ["⌃", "⌥", "D"]),
        ShortcutInfo(id: "clean", category: "Plus", action: "Rendre cet écran uni pour partager ou présenter", keys: ["⌃", "⌥", "P"]),
        ShortcutInfo(id: "count", category: "Plus", action: "Ranger 1 à 4 fenêtres sur cet écran", keys: ["⌃", "⌥", "⌘", "1–4"])]

    /// Shortcut list with the keys as printed on the current keyboard.
    static var shortcutCatalog: [ShortcutInfo] {
        baseCatalog.map { info in
            guard let entry = hotkeyTable.first(where: { $0.catalog == info.id }), entry.char != nil, let last = info.keys.last else { return info }
            let code = KeyboardLayout.resolve(entry.char, fallback: entry.code)
            return ShortcutInfo(id: info.id, category: info.category, action: info.action, keys: info.keys.dropLast() + [KeyboardLayout.label(for: code, default: last)])
        }
    }

    // MARK: Private state
    private var states: [String: StackLayout] = [:]
    private var plans: [String: TilePlan] = [:]
    private var windows: [TrackedWindow] = []
    private var originals: [Int: CGRect] = [:]
    private var focusSnapshot: (window: TrackedWindow, frame: CGRect, screen: String)?
    private var grips: [String: StackGrip] = [:]
    private let hud = StackHUD()
    private var hudPending: DispatchWorkItem?
    private var decorations: [String: DecorationPanel] = [:]
    private let glow = GlowPanel()
    private let cleanPanel = CleanSpacePanel()
    private let dropHighlight = DropHighlight()
    private var cleanDisplay: String?
    private var lastTiled: Int?
    /// Order of windows in a stack's bar and for ⌃⌥`; set by dragging chips, otherwise the order they joined.
    private var stackRank: [Int: Int] = [:]
    private func barOrder(_ ids: [Int]) -> [Int] {
        ids.sorted { (stackRank[$0] ?? 1_000_000 + $0) < (stackRank[$1] ?? 1_000_000 + $1) }
    }
    private var lastExternalPID: pid_t?
    private var learned: [String: [Double]] = [:]
    private var roomCardShown: [String: Date] = [:]
    private var overflowNoticed: Set<Int> = []
    private var stackNoticeSeen = false
    private var loading = true
    private var testing = false
    private var dirty = true
    private var running = false
    private var lastScan = Date.distantPast
    private var lastSignature = ""
    private var knownIDs: [String: Set<Int>] = [:]
    private var timer: Timer?
    private var dragTimer: Timer?
    private var deferred: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var flagsMonitor: Any?
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var heldHotkey: UInt32?
    private var heldSince = Date.distantPast
    // Mouse and drag tracking
    private var mouseWasDown = false
    private var drag: (window: TrackedWindow, start: CGRect, screen: String)?
    private var dragKind: DragKind = .none
    private var lastMouse = NSEvent.mouseLocation
    private var hoverCandidate: (Int, Date)?
    private var lastKeyAge: Double = 0
    private var hoverArmed = false
    private enum DragKind { case none, move, resize }

    // MARK: Lifecycle
    init() {
        let d = UserDefaults.standard
        migrateDefaults(d)
        autoStart = d.object(forKey: "autoStart") as? Bool ?? true
        setupDone = d.object(forKey: "setupDone") as? Bool ?? false
        gap = max(0, min(24, d.object(forKey: "gap") as? Double ?? 8))
        defaultKind = LayoutKind(rawValue: d.string(forKey: "defaultKind") ?? "") ?? .grid
        defaultCapacity = min(4, max(1, d.object(forKey: "defaultCapacity") as? Int ?? 3))
        whenFull = d.string(forKey: "whenFull") ?? "stack"
        moveIntoFull = d.string(forKey: "moveIntoFull") ?? "swap"
        hoverFocus = d.bool(forKey: "hoverFocus")
        quickActions = d.object(forKey: "quickActions") as? Bool ?? true
        shortcutsEnabled = d.object(forKey: "shortcutsEnabled") as? Bool ?? true
        borderWidth = min(6, max(2, d.object(forKey: "borderWidth") as? Double ?? 3))
        highlight = d.string(forKey: "highlight") ?? "none"
        tintName = d.string(forKey: "tintName") ?? "accent"
        if let rgb = d.array(forKey: "customColor") as? [Double], rgb.count == 3 { customColor = NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1) }
        dimAmount = min(0.9, max(0.1, d.object(forKey: "dimAmount") as? Double ?? 0.5))
        blurOthers = d.object(forKey: "blurOthers") as? Bool ?? true
        cleanBackground = d.string(forKey: "cleanBackground") ?? "graphite"
        iconStyle = d.string(forKey: "iconStyle") ?? "washi"
        exclusions = Set(d.stringArray(forKey: "exclusions") ?? [])
        removedDefaults = Set(d.stringArray(forKey: "removedDefaults") ?? [])
        roomCardMuted = Set(d.stringArray(forKey: "roomCardMuted") ?? [])
        roomCardShown = d.dictionary(forKey: "roomCardShown") as? [String: Date] ?? [:]
        countActivity = d.object(forKey: "countActivity") as? Bool ?? true
        if let data = d.data(forKey: "activity"), let stats = try? JSONDecoder().decode(ActivityStats.self, from: data) { activity = stats }
        stackNoticeSeen = d.bool(forKey: "stackNoticeSeen")
        if let data = d.data(forKey: "floatRules"), let rules = try? JSONDecoder().decode([FloatRule].self, from: data) { floatRules = rules }
        if let data = d.data(forKey: "displaySettings"), let settings = try? JSONDecoder().decode([String: DisplaySettings].self, from: data) { displaySettings = settings }
        learned = d.dictionary(forKey: "learnedMinimums") as? [String: [Double]] ?? [:]
        applyExclusions()
        catalog.floatRules = floatRules; catalog.testOnly = qaMode
        catalog.onChange = { [weak self] in self?.scheduleScan() }
        hud.onScroll = { [weak self] step in self?.cycleStack(step, notify: false) }
        hud.onChipDrag = { [weak self] id, point, ended in self?.chipDragged(id, to: point, ended: ended) }
        hud.onReorder = { [weak self] ids in
            guard let self else { return }
            for (rank, id) in ids.enumerated() { self.stackRank[id] = rank }
            self.updateDecorations()
        }
        lastExternalPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if name == NSWorkspace.didActivateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.lastExternalPID = app.processIdentifier; self.hoverArmed = false; self.hud.dismiss() }
                if [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification].contains(name) {
                    if self.cleanSpace { self.toggleCleanSpace() }
                }
                if name == NSWorkspace.activeSpaceDidChangeNotification { self.endFocus(); self.clearDecorations() }
                self.dirty = true; self.scheduleScan()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if let clean = self.cleanDisplay { self.updateScreens(); if !self.displays.contains(where: { $0.id == clean }) && self.cleanSpace { self.toggleCleanSpace() } }
            self.dirty = true; self.scheduleScan()
        })
        // Shortcuts follow the keyboard layout; register them again when it changes.
        observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.installHotkeys(); self?.objectWillChange.send()
        })
        // Holding ⌥ turns Float into Always float in the hover bar.
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] _ in self?.updateDecorations() }
        loading = false
        updateScreens(); installHotkeys()
        timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        if trusted && autoStart && setupDone && !qaMode { enabled = true; arrange() }
        updateStatus()
    }
    deinit {
        timer?.invalidate(); dragTimer?.invalidate(); deferred?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        hotkeys.forEach { UnregisterEventHotKey($0) }; if let handler { RemoveEventHandler(handler) }
    }

    /// Earlier versions saved their own defaults (gap 10, teal border). Version 2 follows the reference defaults once.
    private func migrateDefaults(_ d: UserDefaults) {
        guard d.integer(forKey: "defaultsVersion") < 2 else { return }
        let existing = d.object(forKey: "gap") != nil || d.object(forKey: "autoStart") != nil
        for key in ["gap", "highlight", "tintName", "dimAmount", "displaySettings", "stackOverflow"] { d.removeObject(forKey: key) }
        // Excluded apps that are defaults now live in the default list.
        if let old = d.stringArray(forKey: "exclusions") {
            let defaults = Set(Self.defaultExclusions.map(\.bundle))
            d.set(old.filter { !defaults.contains($0) }, forKey: "exclusions")
        }
        if existing { d.set(true, forKey: "setupDone") }
        d.set(2, forKey: "defaultsVersion")
    }

    private func persist() {
        guard !loading else { return }
        let d = UserDefaults.standard
        d.set(autoStart, forKey: "autoStart"); d.set(setupDone, forKey: "setupDone")
        d.set(gap, forKey: "gap"); d.set(defaultKind.rawValue, forKey: "defaultKind"); d.set(defaultCapacity, forKey: "defaultCapacity")
        d.set(whenFull, forKey: "whenFull"); d.set(moveIntoFull, forKey: "moveIntoFull")
        d.set(hoverFocus, forKey: "hoverFocus"); d.set(quickActions, forKey: "quickActions")
        d.set(try? JSONEncoder().encode(floatRules), forKey: "floatRules")
        d.set(borderWidth, forKey: "borderWidth"); d.set(highlight, forKey: "highlight"); d.set(tintName, forKey: "tintName")
        if let color = customColor.usingColorSpace(.sRGB) { d.set([color.redComponent, color.greenComponent, color.blueComponent], forKey: "customColor") }
        d.set(dimAmount, forKey: "dimAmount"); d.set(blurOthers, forKey: "blurOthers")
        d.set(cleanBackground, forKey: "cleanBackground"); d.set(iconStyle, forKey: "iconStyle")
        d.set(shortcutsEnabled, forKey: "shortcutsEnabled")
        d.set(Array(exclusions).sorted(), forKey: "exclusions"); d.set(Array(removedDefaults).sorted(), forKey: "removedDefaults")
        d.set(Array(roomCardMuted).sorted(), forKey: "roomCardMuted"); d.set(roomCardShown, forKey: "roomCardShown")
        d.set(countActivity, forKey: "countActivity"); d.set(try? JSONEncoder().encode(activity), forKey: "activity")
        d.set(stackNoticeSeen, forKey: "stackNoticeSeen")
        d.set(try? JSONEncoder().encode(displaySettings), forKey: "displaySettings")
        d.set(learned, forKey: "learnedMinimums")
    }

    // MARK: Derived values
    var tint: NSColor {
        switch tintName {
        case "custom": return customColor
        case "purple": return NSColor(hex: 0xA550F5)
        case "pink": return NSColor(hex: 0xF7418F)
        case "orange": return NSColor(hex: 0xFF9500)
        case "green": return NSColor(hex: 0x34C759)
        case "graphite": return NSColor(hex: 0x8E8E93)
        default: return .controlAccentColor
        }
    }
    var cleanColor: NSColor {
        switch cleanBackground { case "mist": return NSColor(hex: 0xD9D8D4); case "stone": return NSColor(hex: 0x6E6C68); default: return NSColor(hex: 0x2A2A2D) }
    }
    /// The space grows to fit a border, and to 4 pt for the glow.
    var effectiveGap: Double {
        switch highlight { case "active", "all": return max(gap, borderWidth); case "glow": return max(gap, 4); default: return gap }
    }
    var stageManager: Bool { CFPreferencesCopyAppValue("GloballyEnabled" as CFString, "com.apple.WindowManager" as CFString) as? Bool == true }
    var effectiveExclusions: Set<String> { Set(Self.defaultExclusions.map(\.bundle)).subtracting(removedDefaults).union(exclusions) }
    private func applyExclusions() {
        let before = catalog.exclusions
        catalog.exclusions = effectiveExclusions
        catalog.excludedNames = Self.defaultExcludedNames.filter { name in !removedDefaults.contains(name) }
        guard !loading else { return }
        // An app that leaves the layout goes back to its own size, centred; the rest reflow.
        let added = catalog.exclusions.subtracting(before)
        for window in catalog.known where added.contains(window.bundle) {
            guard let screen = display(for: window) else { continue }
            let size = CGSize(width: min(window.original.width, screen.frame.width - 40), height: min(window.original.height, screen.frame.height - 40))
            place(window, target: CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height).integral)
        }
        arrange()
    }

    var activeWindow: TrackedWindow? {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return catalog.focused(pid: front == ProcessInfo.processInfo.processIdentifier ? lastExternalPID : front)
    }
    var frontApp: NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return lastExternalPID.flatMap { NSRunningApplication(processIdentifier: $0) } }
        return front
    }
    func isTiled(bundle: String) -> Bool { !effectiveExclusions.contains(bundle) }
    func setTiled(bundle: String, _ tiled: Bool) {
        let isDefault = Self.defaultExclusions.contains { $0.bundle == bundle }
        if tiled { exclusions.remove(bundle); if isDefault { removedDefaults.insert(bundle) } }
        else { if isDefault { removedDefaults.remove(bundle) } else { exclusions.insert(bundle) } }
    }

    /// Settings for a screen in its current Space: its own choice, else the last pick on that screen, else the defaults.
    func config(for screen: DisplayOption) -> DisplaySettings {
        displaySettings[screen.id] ?? displaySettings[screen.uuid] ?? DisplaySettings(kind: defaultKind, capacity: defaultCapacity)
    }
    private func setConfig(_ value: DisplaySettings, for screen: DisplayOption, save: Bool = true) {
        displaySettings[screen.id] = value; displaySettings[screen.uuid] = value
        if save { persist() }
    }
    var selected: DisplayOption? { displays.first { $0.id == selectedDisplay } ?? displays.first }
    var settings: DisplaySettings { selected.map(config) ?? DisplaySettings(kind: defaultKind, capacity: defaultCapacity) }
    func changeSettings(for screen: DisplayOption? = nil, notify: Bool = false, _ edit: (inout DisplaySettings) -> Void) {
        guard let screen = screen ?? selected else { return }
        var value = config(for: screen)
        let before = value
        edit(&value); value.capacity = min(4, max(1, value.capacity))
        if value.kind != before.kind { value.ratios = [] }
        setConfig(value, for: screen)
        endFocus(); arrange()
        guard notify else { return }
        let area = ScreenSpace.cocoa(screen.frame)
        if value.capacity != before.capacity {
            let cap = TileLayout.capacity(value, bounds: screen.frame, gap: effectiveGap)
            let style = TileLayout.style(value.kind, bounds: screen.frame)
            NoticeCenter.shared.show(Notice(title: value.capacity == 1 ? "1 fenêtre" : "Jusqu’à \(value.capacity) fenêtres",
                                            message: style == .columns ? "En colonnes sur cet écran (jusqu’à \(cap))." : "Sur cet écran, dans ce Space.",
                                            symbol: "rectangle.split.2x2"), on: area)
        } else if value.kind != before.kind {
            let cap = TileLayout.maxColumns(in: screen.frame, gap: effectiveGap)
            NoticeCenter.shared.show(value.kind == .grid ? Notice(title: "Grille", message: "Une grande fenêtre, les autres à côté, sur cet écran.", symbol: "rectangle.split.2x1")
                                     : Notice(title: "Colonnes", message: "Côte à côte. Cet écran tient \(cap) colonnes.", symbol: "rectangle.split.3x1"), on: area)
        }
    }
    func hasCustomSizes(_ screen: DisplayOption) -> Bool { config(for: screen).customSizes }
    func columnCapacity(_ screen: DisplayOption) -> Int { TileLayout.maxColumns(in: screen.frame, gap: effectiveGap) }

    var pointerDisplay: DisplayOption? {
        let p = ScreenSpace.axPoint(NSEvent.mouseLocation)
        return displays.first { $0.frame.insetBy(dx: -1, dy: -40).contains(p) } ?? displays.first
    }

    var statusKind: StatusKind {
        if !trusted { return .attention }
        if !setupDone { return .paused }
        if !enabled { return .off }
        if stageManager { return .paused }
        return .active
    }
    var statusLine: String {
        if !trusted { return "A besoin de l’accès Accessibilité" }
        if !setupDone { return "En attente de la fin de la configuration" }
        if !enabled { return "Le rangement automatique est désactivé" }
        if stageManager { return "En pause pendant Stage Manager" }
        let count = windows.filter { !$0.floated }.count
        let text = count == 1 ? "Range 1 fenêtre" : "Range \(count) fenêtres"
        return focusActive ? "Mode Focus · \(count) fenêtre\(count == 1 ? "" : "s")" : text
    }
    private func updateStatus() { if message != statusLine { message = statusLine } }

    // MARK: Switches
    func requestAccess() {
        guard !AXIsProcessTrusted() else { trusted = true; return }
        trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    func openAccessibility() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    func setAutomaticTiling(_ on: Bool) {
        autoStart = on; persist()
        trusted = AXIsProcessTrusted()
        guard trusted, setupDone else { return }
        endFocus()
        if on && !enabled {
            enabled = true; arrange(); playTidy(chime: true)
        } else if !on && enabled {
            // Every window keeps its current frame; borders disappear straight away.
            enabled = false
            if cleanSpace { toggleCleanSpace() }
            noPeek = false; clearDecorations()
        }
        updateStatus()
    }
    func toggle() { setAutomaticTiling(!enabled) }
    /// "Ranger mon espace": the end of the welcome tour, or "Ranger" in the panel.
    func completeSetup() {
        setupDone = true; autoStart = true; persist()
        guard AXIsProcessTrusted() else { trusted = false; return }
        trusted = true; enabled = true
        arrange(); playTidy(chime: true); Haptic.tap()
        updateStatus()
    }
    func retile() {
        guard enabled else { return }
        for window in windows { window.lastTarget = nil }
        arrange()
        if let screen = pointerDisplay { NoticeCenter.shared.show(Notice(title: "Rangé à nouveau", symbol: "checkmark"), on: ScreenSpace.cocoa(screen.frame)) }
        record("retile", .mouse)
    }
    func toggleBorders() { highlight = highlight == "all" ? "none" : "all" }
    func toggleNoPeek(notify: Bool = false) {
        guard enabled else { return }
        noPeek.toggle()
        if notify, let screen = activeWindow.flatMap(display(for:)) ?? pointerDisplay {
            NoticeCenter.shared.show(noPeek ? Notice(title: "No peek activé", message: "Les autres fenêtres s’effacent. ⌃⌥D pour arrêter.", symbol: "circle.lefthalf.filled")
                                     : Notice(title: "No peek désactivé", message: "⌃⌥D pour le réactiver.", symbol: "circle.lefthalf.filled"), on: ScreenSpace.cocoa(screen.frame))
        }
    }
    private func playTidy(chime: Bool) {
        let color = tint
        for screen in displays {
            let frames = (plans[screen.id]?.frames ?? []).map(ScreenSpace.cocoa)
            TidySweep.shared.play(screen: ScreenSpace.cocoa(screen.frame), tiles: frames, color: color)
        }
        if chime { Chime.play() }
    }

    // MARK: Main loop
    func arrange() { dirty = true; refresh() }
    private func scheduleScan() {
        guard !testing, deferred == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.deferred = nil; self?.refresh() }
        deferred = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    private func tick() {
        guard !testing else { return }
        let value = AXIsProcessTrusted()
        if value != trusted {
            trusted = value; dirty = true
            if !value { enabled = false; noPeek = false; if cleanSpace { toggleCleanSpace() }; clearDecorations() }
            else { Haptic.tap(); if autoStart && setupDone && !enabled && !qaMode { enabled = true } }
        }
        let secure = IsSecureEventInputEnabled()
        if secure != secureInput { secureInput = secure }
        let down = NSEvent.pressedMouseButtons & 1 != 0
        if down && !mouseWasDown { beginDrag() }
        if !down && mouseWasDown { finishDrag() }
        mouseWasDown = down
        if !down && Date().timeIntervalSince(lastScan) > 0.8 { refresh() }
        if enabled && trusted && !down { trackHover() }
        if Date().timeIntervalSince(lastScan) > 5 { updateStatus() }
    }
    private func updateScreens() {
        let top = ScreenSpace.top
        let connection = CGSMainConnectionID()
        let next = NSScreen.screens.map { screen -> DisplayOption in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
            let uuid = CGDisplayCreateUUIDFromDisplayID(number).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? String(number)
            let space = CGSManagedDisplayGetCurrentSpace(connection, uuid as CFString)
            let frame = screen.visibleFrame
            return DisplayOption(id: uuid + "#\(space)", uuid: uuid, space: space, name: screen.localizedName,
                                 frame: CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height))
        }
        if next != displays { displays = next; dirty = true }
        if !displays.contains(where: { $0.id == selectedDisplay }) { selectedDisplay = displays.first?.id ?? "" }
    }
    func display(for window: TrackedWindow) -> DisplayOption? {
        TileLayout.screenIndex(for: window.target, screens: displays.map(\.frame)).map { displays[$0] }
    }

    func refresh() {
        guard !running, trusted, !mouseWasDown else { return }
        running = true; defer { running = false }
        lastScan = Date(); updateScreens()
        windows = catalog.scan()
        let allIDs = Set(catalog.known.map(\.id)); originals = originals.filter { allIDs.contains($0.key) }
        let active = activeWindow
        if let window = active {
            for key in states.keys { states[key]?.activate(window.id) }
            // Activating another tiled window on that screen ends Focus mode.
            if let focus = focusSnapshot, focus.window.id != window.id, display(for: window)?.id == focus.screen, !window.floated {
                endFocus(); if cleanSpace { cleanPanel.follow(window: ScreenSpace.cocoa(window.frame)) }
            }
            if let screen = display(for: window), states[screen.id]?.tile(of: window.id) != nil { lastTiled = window.id }
        }
        updateRows()
        guard enabled, setupDone else { clearDecorations(); updateStatus(); didUpdate?(); return }
        guard !stageManager else { clearDecorations(); updateStatus(); dirty = true; didUpdate?(); return }
        let signature = windows.map { "\($0.id):\(display(for: $0)?.id ?? ""):\($0.floated)" }.joined(separator: ",") + displays.map { "\($0.id):\($0.frame)" }.joined()
        if signature != lastSignature { dirty = true; lastSignature = signature }
        if focusActive, let focus = focusSnapshot {
            // A window opening on the focused screen ends Focus mode.
            let ids = Set(windows.filter { display(for: $0)?.id == focus.screen && !$0.floated }.map(\.id))
            if !ids.subtracting(knownIDs[focus.screen] ?? []).isEmpty { endFocus() }
            else { updateDecorations(); updateStatus(); didUpdate?(); return }
        }
        if dirty { dirty = false; layoutAll(active: active) }
        updateRows(); updateDecorations(); updateStatus(); didUpdate?()
    }

    private func layoutAll(active: TrackedWindow?) {
        for screen in displays {
            let group = windows.filter { display(for: $0)?.id == screen.id && !$0.floated }
            let config = config(for: screen)
            let capacity = TileLayout.capacity(config, bounds: screen.frame, gap: effectiveGap)
            var state = states[screen.id] ?? StackLayout()
            let previous = knownIDs[screen.id] ?? []
            // Front-to-back order: on a fresh layout the windows in use get their own tiles and older ones stack.
            let ordered = group.sorted { catalog.depth[$0.id, default: .max] < catalog.depth[$1.id, default: .max] }
            let activeID = active.flatMap { window in state.tile(of: window.id) != nil ? window.id : nil }
            state.reconcile(ids: ordered.map(\.id), capacity: capacity, preferred: activeID ?? lastTiled, stack: whenFull == "stack")
            let newIDs = Set(group.map(\.id)).subtracting(previous)
            knownIDs[screen.id] = Set(group.map(\.id))
            var groups = state.groups
            var plan: TilePlan?
            var overflow = group.filter { !groups.flatMap({ $0 }).contains($0.id) }
            var noRoom: [TrackedWindow] = []
            while !groups.isEmpty {
                let mins = groups.map { ids -> CGSize in
                    let members = group.filter { ids.contains($0.id) }
                    return CGSize(width: members.map { max(120, $0.minimum.width) }.max() ?? 120, height: members.map { max(100, $0.minimum.height) }.max() ?? 100)
                }
                if let result = TileLayout.plan(in: screen.frame, minimums: mins, settings: config, gap: effectiveGap) { plan = result; break }
                // Windows are never reordered to make one fit: the single window that cannot fit floats,
                // and its stack mates keep the tile.
                let candidates = group.filter { w in groups.contains { $0.contains(w.id) } }
                guard let biggest = candidates.max(by: { a, b in
                    let x = max(120, a.minimum.width) * max(100, a.minimum.height), y = max(120, b.minimum.width) * max(100, b.minimum.height)
                    return x == y ? (catalog.depth[a.id, default: 0] < catalog.depth[b.id, default: 0]) : x < y
                }) else { break }
                groups = groups.map { $0.filter { $0 != biggest.id } }.filter { !$0.isEmpty }
                noRoom.append(biggest)
            }
            states[screen.id] = state
            states[screen.id]?.groups = groups
            plans[screen.id] = plan
            for (index, ids) in groups.enumerated() {
                guard let target = plan?.frames[index] else { continue }
                for window in group where ids.contains(window.id) {
                    if originals[window.id] == nil { originals[window.id] = window.frame; if !testing { record(nil, .none, placed: true) } }
                    place(window, target: target)
                }
                // First time a window waits behind another one: explain the stack once.
                if ids.count > 1, let top = ids.last, newIDs.contains(top), !stackNoticeSeen, !testing {
                    stackNoticeSeen = true; persist()
                    NoticeCenter.shared.show(Notice(title: "Empilée dans cette case", message: "Appuie sur ⌃⌥` ou clique sur la poignée au-dessus de la fenêtre pour changer.", symbol: "square.3.layers.3d"), on: ScreenSpace.cocoa(screen.frame))
                }
            }
            overflow += noRoom
            for window in overflow {
                if originals[window.id] == nil { originals[window.id] = window.frame }
                // Floats in the middle once, at its own size within the screen, then stays where the user puts it.
                let size = CGSize(width: min(max(window.minimum.width, window.original.width), screen.frame.width - 40),
                                  height: min(max(window.minimum.height, window.original.height), screen.frame.height - 40))
                let target = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height).integral
                guard !overflowNoticed.contains(window.id) else { continue }
                overflowNoticed.insert(window.id)
                place(window, target: target)
                if testing { continue }
                if noRoom.contains(where: { $0.id == window.id }) { offerRoom(for: window, on: screen, capacity: capacity) }
                else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NoticeCenter.shared.show(Notice(title: "Ce Space est plein", message: "⌘-glisse une fenêtre sur une case pour échanger.", symbol: "square.grid.2x2"), on: ScreenSpace.cocoa(screen.frame))
                    }
                }
            }
            overflowNoticed.formIntersection(Set(overflow.map(\.id)))
        }
        if UserDefaults.standard.bool(forKey: "debugDump") { dumpState() }
    }
    /// Diagnostic snapshot for testing (enabled with `defaults write io.github.yaibnmo.mosaique debugDump -bool true`).
    private func dumpState() {
        var lines = ["\(Date())"]
        for screen in displays {
            lines.append("screen \(screen.name) \(screen.id) frame \(screen.frame) config \(config(for: screen))")
            for (index, ids) in (states[screen.id]?.groups ?? []).enumerated() {
                let names = ids.map { id in catalog.known.first { $0.id == id }.map { "\($0.appName)#\(id) frame=\($0.frame) target=\(String(describing: $0.lastTarget)) min=\($0.minimum)" } ?? "?\(id)" }
                lines.append("  tile \(index) \(plans[screen.id]?.frames[safe: index].map { "\($0)" } ?? "-"): " + names.joined(separator: " | "))
            }
        }
        lines.append("floating/overflow: " + windows.filter { w in !states.values.contains { $0.tile(of: w.id) != nil } }.map { "\($0.appName)#\($0.id) floated=\($0.floated) frame=\($0.frame)" }.joined(separator: ", "))
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mosaïque")
        try? lines.joined(separator: "\n").write(to: root.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
    }

    /// Moves a window, with the reference spring unless `animated` is false. Learns minimum sizes from refusals.
    @discardableResult func place(_ window: TrackedWindow, target: CGRect, animated: Bool = true) -> Bool {
        window.lastTarget = target
        if window.animatingTo.map({ approximatelyEqual($0, target, tolerance: 1) }) == true { return true }
        if window.animatingTo == nil && approximatelyEqual(window.frame, target) { return true }
        guard animated, !testing, WindowAnimator.shared.duration > 0 else {
            WindowAnimator.shared.cancel(window.id); window.animatingTo = nil
            let result = axSetFrame(window.element, target)
            return handlePlacement(window, target: target, result: result)
        }
        window.animatingTo = target
        WindowAnimator.shared.animate(id: window.id, element: window.element, from: window.frame, to: target) { [weak self, weak window] result in
            guard let self, let window else { return }
            window.animatingTo = nil
            self.handlePlacement(window, target: target, result: result)
            self.updateDecorations()
        }
        return true
    }
    @discardableResult private func handlePlacement(_ window: TrackedWindow, target: CGRect, result: FrameWrite) -> Bool {
        if let actual = result.actual { window.frame = actual }
        guard !result.accepted else { window.refusal = nil; return true }
        // A transport error or one opening animation is not a minimum: the refusal must repeat after a moment.
        if result.error == .success, let actual = result.actual, actual.width > target.width + 3 || actual.height > target.height + 3 {
            let now = Date.timeIntervalSinceReferenceDate
            if let prior = window.refusal, approximatelyEqual(prior.target, target), now - prior.time > 0.35,
               abs(prior.actual.width - actual.width) < 3, abs(prior.actual.height - actual.height) < 3 {
                window.minimum = CGSize(width: actual.width > target.width + 3 ? actual.width : window.minimum.width,
                                        height: actual.height > target.height + 3 ? actual.height : window.minimum.height)
                // A "minimum" of nearly the whole screen is never remembered for the app.
                if let screen = display(for: window), window.minimum.width < screen.frame.width * 0.9, window.minimum.height < screen.frame.height * 0.9 {
                    learned[window.bundle] = [window.minimum.width, window.minimum.height]; persist()
                }
                window.refusal = nil
            } else if window.refusal == nil { window.refusal = (target, actual.size, now) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in if self?.testing == false { self?.arrange() } }
        } else if let actual = result.actual, let known = learned[window.bundle], known.count == 2,
                  actual.width + 3 < known[0] || actual.height + 3 < known[1] {
            // The app accepted a smaller size than remembered: the remembered size comes down by itself.
            learned[window.bundle] = [min(known[0], actual.width), min(known[1], actual.height)]; persist()
        }
        return false
    }

    // MARK: Focus, Clean Space, floating
    func toggleFocus() {
        guard enabled, trusted, !stageManager else { return }
        if focusActive { endFocus(); updateDecorations(); return }
        guard let window = activeWindow, windows.contains(where: { $0.id == window.id }), !window.floated, let screen = display(for: window) else { return }
        focusSnapshot = (window, window.lastTarget ?? window.frame, screen.id)
        knownIDs[screen.id] = Set(windows.filter { display(for: $0)?.id == screen.id && !$0.floated }.map(\.id))
        let target = screen.frame.insetBy(dx: effectiveGap, dy: effectiveGap)
        place(window, target: target)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        focusActive = true
        if !cleanSpace { FocusTag.shared.show(on: ScreenSpace.cocoa(target)) }
        hud.dismiss(); updateDecorations(); updateStatus()
        record("focus", .keyboard)
    }
    func endFocus() {
        guard let focus = focusSnapshot else { return }
        focusSnapshot = nil; focusActive = false
        FocusTag.shared.hide()
        place(focus.window, target: focus.frame)
        dirty = true
    }
    func toggleCleanSpace() {
        if cleanSpace {
            cleanSpace = false; cleanPanel.open(); cleanDisplay = nil; endFocus(); updateDecorations()
            return
        }
        guard enabled, trusted else { return }
        let window = activeWindow.flatMap { windows.contains($0) ? $0 : nil }
        guard let screen = window.flatMap(display(for:)) ?? pointerDisplay else { return }
        cleanDisplay = screen.id; cleanSpace = true
        hud.dismiss()
        var hole = CGRect(x: screen.frame.midX, y: screen.frame.midY, width: 0, height: 0)
        if let window, !window.floated {
            if !focusActive { toggleFocus() }
            hole = screen.frame.insetBy(dx: effectiveGap, dy: effectiveGap)
        } else if let window { hole = window.frame }
        cleanPanel.close(screen: ScreenSpace.cocoa(screen.frame), around: ScreenSpace.cocoa(hole), color: cleanColor)
        FocusTag.shared.hide()
        updateDecorations()
        record("cleanSpace", .keyboard)
    }
    func toggleFloat() {
        guard enabled, let window = activeWindow, let screen = display(for: window) else { return }
        endFocus(); hud.dismiss()
        window.floated.toggle()
        if window.floated {
            // Centred at 60 % × 75 % of the usable area, then left wherever the user moves it.
            let area = screen.frame.insetBy(dx: effectiveGap, dy: effectiveGap)
            let size = CGSize(width: max((area.width * 0.6).rounded(), window.minimum.width), height: max((area.height * 0.75).rounded(), window.minimum.height))
            place(window, target: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height).integral)
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            states[screen.id]?.remove(window.id)
        }
        // A window tiled again joins the end of its screen's order.
        arrange()
        record("float", .keyboard)
    }
    func proposeFloatRule() {
        guard let window = activeWindow, let screen = display(for: window) else { return }
        let words = window.title.split(whereSeparator: { $0.isWhitespace }).prefix(2).joined(separator: " ")
        let area = ScreenSpace.cocoa(screen.frame)
        guard !window.title.isEmpty, !words.isEmpty else {
            NoticeCenter.shared.show(Notice(title: "Cette fenêtre n’a pas de titre", message: "Fais-la flotter avec ⌃⌥F à chaque fois, ou exclus l’app entière.", symbol: "questionmark.square.dashed"), on: area); return
        }
        let rule = FloatRule(bundle: window.bundle, prefix: words)
        if floatRules.contains(rule) {
            NoticeCenter.shared.show(Notice(title: "Flotte déjà à chaque fois", message: "Cette fenêtre figure dans Réglages › Apps.", symbol: "checkmark"), on: area); return
        }
        pendingRule = rule
        NSSound(named: "Tink")?.play()
        ActionCard.shared.show(title: "Toujours faire flotter les fenêtres « \(words) » ?",
                               message: "Mosaïque fera flotter les fenêtres de \(window.appName) dont le titre commence par ces mots.",
                               buttons: [("Toujours flotter", true, { [weak self] in self?.confirmFloatRule() }), ("Pas maintenant", false, { [weak self] in self?.pendingRule = nil })],
                               near: ScreenSpace.cocoa(window.frame), timeout: 12)
    }
    func confirmFloatRule() {
        guard let rule = pendingRule else { return }
        if !floatRules.contains(rule) { floatRules.append(rule) }
        pendingRule = nil
    }

    /// "Besoin de place": a card under the title bar of a window that had to float, at most once a day per app.
    private func offerRoom(for window: TrackedWindow, on screen: DisplayOption, capacity: Int) {
        guard !roomCardMuted.contains(window.bundle) else { return }
        if let last = roomCardShown[window.bundle], Date().timeIntervalSince(last) < 86_400 { return }
        roomCardShown[window.bundle] = Date(); persist()
        var buttons: [(String, Bool, () -> Void)] = []
        let others = displays.filter { other in other.id != screen.id && (states[other.id]?.groups.count ?? 0) < TileLayout.capacity(config(for: other), bounds: other.frame, gap: effectiveGap) }
        if let other = others.first {
            buttons.append(("Déplacer vers \(other.name)", true, { [weak self, weak window] in guard let self, let window else { return }; self.transfer(window, to: other) }))
        }
        if capacity > 1 {
            let fewer = capacity - 1
            buttons.append(("Utiliser \(fewer) fenêtre\(fewer > 1 ? "s" : "") ici", others.isEmpty, { [weak self, weak window] in
                guard let self, let window else { return }
                self.changeSettings(for: screen) { $0.capacity = fewer }
                self.states[screen.id]?.groups.insert([window.id], at: 0)
                self.arrange()
            }))
        }
        buttons.append(("La laisser flotter", false, {}))
        buttons.append(("Ne plus afficher pour \(window.appName)", false, { [weak self] in self?.roomCardMuted.insert(window.bundle) }))
        let frame = ScreenSpace.cocoa(window.lastTarget ?? window.frame)
        ActionCard.shared.show(title: "Besoin de plus de place", message: "\(window.appName) ne peut pas devenir assez petite pour sa place.",
                               buttons: buttons, near: CGRect(x: frame.minX, y: frame.maxY - 40, width: frame.width, height: 40), timeout: 6)
    }

    // MARK: Selection and stacks
    func select(_ id: Int) {
        guard trusted, let window = catalog.known.first(where: { $0.id == id }) else { return }
        if focusSnapshot?.window.id != id { endFocus() }
        if window.minimized { AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        // Since macOS 14, activate() from a background app is only a request; Accessibility brings the app forward directly.
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != window.pid { NSRunningApplication(processIdentifier: window.pid)?.activate() }
        for key in states.keys { states[key]?.activate(id) }
        lastExternalPID = window.pid
        scheduleScan()
    }
    func cycleStack(_ step: Int = 1, notify: Bool = true) {
        guard enabled, let window = activeWindow else { return }
        guard let group = states.values.flatMap(\.groups).first(where: { $0.contains(window.id) }), group.count > 1 else {
            if notify, let screen = display(for: window) {
                NoticeCenter.shared.show(Notice(title: "Rien d’empilé ici", message: "Un écran plein empile les nouvelles fenêtres dans la case où tu travailles.", symbol: "square.3.layers.3d"), on: ScreenSpace.cocoa(screen.frame))
            }
            return
        }
        // Members are visited in the order they joined; the showing order stays most-recent-last.
        let ordered = barOrder(group), index = ordered.firstIndex(of: window.id)!
        select(ordered[(index + step + ordered.count) % ordered.count])
        record("stack", notify ? .keyboard : .mouse)
    }
    func cycleWindow(_ step: Int) {
        guard enabled else { return }
        let ids = displays.flatMap { states[$0.id]?.groups.compactMap(\.last) ?? [] }
        guard !ids.isEmpty else { return }
        let index = activeWindow.flatMap { ids.firstIndex(of: $0.id) } ?? (step > 0 ? -1 : 0)
        select(ids[(index + step + ids.count) % ids.count])
        record("cycle", .keyboard)
    }
    func primary() {
        guard enabled, let window = activeWindow, let screen = display(for: window), let primary = states[screen.id]?.groups.first?.last, primary != window.id else { return }
        endFocus(); states[screen.id]?.swap(window.id, primary); arrange()
        record("primary", .keyboard)
    }
    func isPrimary(_ window: TrackedWindow) -> Bool {
        display(for: window).flatMap { states[$0.id]?.groups.first?.contains(window.id) } ?? false
    }
    func move(_ direction: Direction) {
        guard enabled, let window = activeWindow, let screen = display(for: window),
              let state = states[screen.id], let tile = state.tile(of: window.id),
              let frames = plans[screen.id]?.frames, frames.indices.contains(tile) else { return }
        endFocus()
        record("move", .keyboard)
        if let next = direction.neighbor(of: tile, in: frames), let id = state.groups[next].last {
            states[screen.id]?.swap(window.id, id); arrange(); select(window.id); return
        }
        let screens = displays.filter { $0.id != screen.id }.compactMap { other -> (DisplayOption, CGFloat)? in direction.score(from: screen.frame, to: other.frame).map { (other, $0) } }
        if let next = screens.min(by: { $0.1 < $1.1 })?.0 { transfer(window, to: next) }
    }
    func nextScreen() {
        guard enabled, let window = activeWindow, let screen = display(for: window), let index = displays.firstIndex(where: { $0.id == screen.id }), displays.count > 1 else { return }
        transfer(window, to: displays[(index + 1) % displays.count])
    }
    /// Sends a window to another screen: it joins as the newest window, or when that screen is full it swaps
    /// with (or stacks on) the window it lands on, following Settings › Layout › Moving into a full screen.
    func transfer(_ window: TrackedWindow, to screen: DisplayOption, landing: CGPoint? = nil, stackOnFull: Bool? = nil) {
        endFocus()
        guard let source = display(for: window) else { return }
        let capacity = TileLayout.capacity(config(for: screen), bounds: screen.frame, gap: effectiveGap)
        let groups = states[screen.id]?.groups ?? []
        let landingTile: Int? = {
            guard let frames = plans[screen.id]?.frames, !frames.isEmpty else { return nil }
            let p = landing ?? CGPoint(x: screen.frame.minX + (window.target.midX - source.frame.minX) / source.frame.width * screen.frame.width,
                                          y: screen.frame.minY + (window.target.midY - source.frame.minY) / source.frame.height * screen.frame.height)
            return frames.indices.min { hypot(frames[$0].midX - p.x, frames[$0].midY - p.y) < hypot(frames[$1].midX - p.x, frames[$1].midY - p.y) }
        }()
        let center = CGRect(x: screen.frame.midX - window.frame.width / 2, y: screen.frame.midY - window.frame.height / 2, width: min(window.frame.width, screen.frame.width), height: min(window.frame.height, screen.frame.height))
        if groups.count < capacity || landingTile == nil {
            states[source.id]?.remove(window.id)
            place(window, target: center)
        } else if let tile = landingTile, groups.indices.contains(tile) {
            let stack = stackOnFull ?? (moveIntoFull == "stack")
            let sourceState = states[source.id]
            states[source.id]?.remove(window.id)
            if stack {
                states[screen.id]?.insert(window.id, onTile: tile)
                place(window, target: plans[screen.id]?.frames[tile] ?? center)
            } else if let otherID = groups[tile].last, let other = catalog.known.first(where: { $0.id == otherID }) {
                // Undo the removal above: the two windows trade places instead.
                let back = window.lastTarget ?? window.frame
                states[source.id] = sourceState
                states[source.id]?.replace(window.id, with: otherID)
                states[screen.id]?.replace(otherID, with: window.id)
                place(window, target: plans[screen.id]?.frames[tile] ?? center)
                place(other, target: back)
            }
        }
        arrange(); select(window.id)
    }
    private func stack(_ id: Int, on target: Int) {
        guard enabled, let screen = displays.first(where: { states[$0.id]?.tile(of: target) != nil }),
              let tile = states[screen.id]?.tile(of: target), let window = catalog.known.first(where: { $0.id == id }) else { return }
        if display(for: window)?.id != screen.id {
            states[display(for: window)?.id ?? ""]?.remove(id)
            states[screen.id]?.insert(id, onTile: tile)
            place(window, target: plans[screen.id]?.frames[tile] ?? window.frame)
        } else { states[screen.id]?.move(id, to: tile) }
        arrange(); select(id)
    }

    // MARK: Resizing
    func resize(_ step: Double) {
        guard enabled, let window = activeWindow, let screen = display(for: window), let tile = states[screen.id]?.tile(of: window.id) else { return }
        endFocus()
        let count = states[screen.id]?.groups.count ?? 0
        guard count > 1 else { sizeLimit(grow: step > 0, on: screen); return }
        var config = config(for: screen)
        let style = TileLayout.style(config.kind, bounds: screen.frame)
        let old = TileLayout.fullRatios(config, style, count: count)
        let wanted = TileLayout.grow(config, tile: tile, count: count, bounds: screen.frame, step: step)
        let mins = minimums(on: screen)
        let fitted = TileLayout.bisect(old: old, new: wanted) { ratios in
            var test = config; test.ratios = ratios
            guard let plan = TileLayout.plan(in: screen.frame, minimums: mins, settings: test, gap: self.effectiveGap) else { return false }
            return zip(plan.frames, mins).allSatisfy { $0.width + 0.5 >= $1.width && $0.height + 0.5 >= $1.height }
        }
        let moved = zip(old, fitted).contains { abs($0 - $1) > 0.002 }
        guard moved else { sizeLimit(grow: step > 0, on: screen); return }
        config.ratios = fitted
        setConfig(config, for: screen); arrange()
        record("resize", .keyboard)
    }
    /// Minimum size of each tile: what its apps accept, and never below a usable size.
    private func minimums(on screen: DisplayOption) -> [CGSize] {
        (states[screen.id]?.groups ?? []).map { ids in
            let members = windows.filter { ids.contains($0.id) }
            return CGSize(width: max(TileLayout.usableSize.width, members.map(\.minimum.width).max() ?? 0),
                          height: max(TileLayout.usableSize.height, members.map(\.minimum.height).max() ?? 0))
        }
    }
    private func sizeLimit(grow: Bool, on screen: DisplayOption) {
        NoticeCenter.shared.show(Notice(title: grow ? "Taille maximale atteinte" : "Taille minimale atteinte", symbol: grow ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left", sound: true), on: ScreenSpace.cocoa(screen.frame))
    }
    func resetSizes(for screen: DisplayOption? = nil) {
        guard let screen = screen ?? activeWindow.flatMap(display(for:)) ?? selected else { return }
        changeSettings(for: screen) { $0.ratios = [] }
    }

    // MARK: Drag: ⌘ swaps, ⌥⌘ stacks, edges resize live
    private func beginDrag() {
        // The window under the pointer, frontmost first: at mouse-down its app may not be active yet.
        let p = ScreenSpace.axPoint(NSEvent.mouseLocation)
        let under = windows.filter { ($0.animatingTo ?? $0.frame).insetBy(dx: -6, dy: -6).contains(p) }
            .min { catalog.depth[$0.id, default: .max] < catalog.depth[$1.id, default: .max] }
        guard enabled, trusted, let window = under ?? activeWindow.flatMap({ w in windows.first { $0.id == w.id } }), let screen = display(for: window) else { drag = nil; return }
        drag = (window, axFrame(window.element) ?? window.frame, screen.id)
        dragKind = .none
        dragTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.dragStep() }
        RunLoop.main.add(timer, forMode: .common); dragTimer = timer
    }
    private func dragStep() {
        guard let drag, NSEvent.pressedMouseButtons & 1 != 0, let actual = axFrame(drag.window.element) else { return }
        let start = drag.start
        if dragKind == .none {
            if abs(actual.width - start.width) > 2 || abs(actual.height - start.height) > 2 { dragKind = .resize; hud.dismiss(); WindowAnimator.shared.cancel(drag.window.id); drag.window.animatingTo = nil }
            else if hypot(actual.minX - start.minX, actual.minY - start.minY) > 4 { dragKind = .move; hud.dismiss(); WindowAnimator.shared.cancel(drag.window.id); drag.window.animatingTo = nil; if focusSnapshot?.window.id == drag.window.id { focusSnapshot = nil; focusActive = false } }
        }
        switch dragKind {
        case .move: updateDropTarget(for: drag.window)
        case .resize: liveResize(drag.window, actual: actual, start: start, screenID: drag.screen, final: false)
        case .none: break
        }
    }
    private func dropMode() -> String? {
        let flags = NSEvent.modifierFlags
        guard flags.contains(.command) || flags.contains(.control) else { return nil }
        return flags.contains(.option) ? "stack" : "swap"
    }
    /// The tile under the pointer whose showing window is not the dragged one.
    private func tileUnderPointer(excluding id: Int) -> (screen: DisplayOption, tile: Int, frame: CGRect)? {
        let p = ScreenSpace.axPoint(NSEvent.mouseLocation)
        for screen in displays {
            guard let frames = plans[screen.id]?.frames, let groups = states[screen.id]?.groups else { continue }
            if let tile = frames.indices.first(where: { frames[$0].contains(p) }), groups.indices.contains(tile), !groups[tile].contains(id) {
                return (screen, tile, frames[tile])
            }
        }
        return nil
    }
    private func updateDropTarget(for window: TrackedWindow) {
        guard let mode = dropMode(), let target = tileUnderPointer(excluding: window.id) else { dropHighlight.hide(); return }
        dropHighlight.show(ScreenSpace.cocoa(target.frame), text: mode == "stack" ? "Ajouter à la pile" : nil, color: tint)
    }
    private func liveResize(_ window: TrackedWindow, actual: CGRect, start: CGRect, screenID: String, final: Bool) {
        guard let screen = displays.first(where: { $0.id == screenID }), let plan = plans[screen.id],
              let tile = states[screen.id]?.tile(of: window.id) else { return }
        let g = CGFloat(effectiveGap)
        var config = config(for: screen)
        let style = TileLayout.style(config.kind, bounds: screen.frame)
        var ratios = TileLayout.fullRatios(config, style, count: plan.frames.count)
        var changed = false
        for divider in plan.dividers {
            let edgeMoved: CGFloat?
            if divider.first.contains(tile) {
                let old = divider.vertical ? start.maxX : start.maxY, new = divider.vertical ? actual.maxX : actual.maxY
                edgeMoved = abs(new - old) > 1 ? new + g / 2 : nil
            } else if divider.second.contains(tile) {
                let old = divider.vertical ? start.minX : start.minY, new = divider.vertical ? actual.minX : actual.minY
                edgeMoved = abs(new - old) > 1 ? new - g / 2 : nil
            } else { edgeMoved = nil }
            // Only the edges shared with another window move; outside edges do nothing.
            guard let position = edgeMoved, ratios.indices.contains(divider.ratioIndex) else { continue }
            ratios[divider.ratioIndex] = divider.ratio(forPosition: position, gap: g); changed = true
        }
        guard changed else { return }
        config.ratios = ratios
        setConfig(config, for: screen, save: final)
        guard let next = TileLayout.plan(in: screen.frame, minimums: minimums(on: screen).map { CGSize(width: min($0.width, 200), height: min($0.height, 150)) }, settings: config, gap: effectiveGap) else { return }
        plans[screen.id] = next
        // Neighbours follow the pointer one to one; the dragged window stays under the user's control until release.
        for (index, ids) in (states[screen.id]?.groups ?? []).enumerated() where next.frames.indices.contains(index) {
            for member in windows where ids.contains(member.id) && (member.id != window.id || final) {
                place(member, target: next.frames[index], animated: final)
            }
        }
    }
    private func finishDrag() {
        dragTimer?.invalidate(); dragTimer = nil
        dropHighlight.hide()
        defer { drag = nil; dragKind = .none; dirty = true; scheduleScan() }
        guard enabled, let drag, let actual = axFrame(drag.window.element) else { return }
        let window = drag.window
        switch dragKind {
        case .none: return
        case .resize:
            liveResize(window, actual: actual, start: drag.start, screenID: drag.screen, final: true)
            persist(); record("resize", .mouse)
        case .move:
            let mode = dropMode()
            let pointer = ScreenSpace.axPoint(NSEvent.mouseLocation)
            let targetScreen = displays.first { $0.frame.insetBy(dx: -1, dy: -40).contains(pointer) }
            if let mode, let target = tileUnderPointer(excluding: window.id) {
                guard let otherID = states[target.screen.id]?.groups[target.tile].last else { return }
                if mode == "stack" { stack(window.id, on: otherID) }
                else if target.screen.id == drag.screen { states[target.screen.id]?.swap(window.id, otherID); arrange() }
                else if let other = catalog.known.first(where: { $0.id == otherID }) {
                    // Across screens: the two windows trade places.
                    let back = window.lastTarget ?? drag.start
                    states[drag.screen]?.replace(window.id, with: otherID)
                    states[target.screen.id]?.replace(otherID, with: window.id)
                    place(window, target: target.frame); place(other, target: back)
                    arrange()
                }
                activity.keyboard += 0.5; activity.mouse += 0.5; record("swap", .none)
            } else if let targetScreen, targetScreen.id != drag.screen, !window.floated {
                // A window dropped on another screen joins it as its newest window, or goes back if that screen is full.
                let capacity = TileLayout.capacity(config(for: targetScreen), bounds: targetScreen.frame, gap: effectiveGap)
                if (states[targetScreen.id]?.groups.count ?? 0) < capacity { transfer(window, to: targetScreen, landing: pointer) }
                else if let back = window.lastTarget { place(window, target: back) }
                record("moveScreen", .mouse)
            } else if !window.floated, let back = window.lastTarget {
                // A plain drag never rearranges: the window goes back to its place.
                place(window, target: back)
                if let screen = displays.first(where: { $0.id == drag.screen }) {
                    NoticeCenter.shared.show(Notice(title: "Un simple glisser ne réorganise jamais.", message: "Maintiens ⌘ pour échanger.", symbol: "hand.draw"), on: ScreenSpace.cocoa(screen.frame))
                }
            }
        }
    }
    private func chipDragged(_ id: Int, to point: CGPoint, ended: Bool) {
        guard ended else {
            if let target = tileUnderPointer(excluding: id) { dropHighlight.show(ScreenSpace.cocoa(target.frame), text: "Déplacer ici", color: tint) } else { dropHighlight.hide() }
            return
        }
        dropHighlight.hide()
        guard let target = tileUnderPointer(excluding: id), let otherID = states[target.screen.id]?.groups[target.tile].last else { return }
        stack(id, on: otherID)
        record("chip", .mouse)
    }

    // MARK: Hover focus
    private func trackHover() {
        let point = NSEvent.mouseLocation
        let keyAge = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        if keyAge < lastKeyAge { hoverArmed = false; hoverCandidate = nil }
        lastKeyAge = keyAge
        if point != lastMouse { hoverArmed = true; lastMouse = point }
        guard hoverFocus, hoverArmed, !focusActive, !cleanSpace, !hud.isVisible else { hoverCandidate = nil; return }
        let p = ScreenSpace.axPoint(point)
        let showing = Set(states.values.flatMap { $0.groups.compactMap(\.last) })
        guard let target = windows.first(where: { showing.contains($0.id) && ($0.lastTarget ?? $0.frame).contains(p) }), target.id != activeWindow?.id else { hoverCandidate = nil; return }
        if hoverCandidate?.0 != target.id { hoverCandidate = (target.id, Date()) }
        else if let time = hoverCandidate?.1, Date().timeIntervalSince(time) >= 0.15 { hoverArmed = false; hoverCandidate = nil; select(target.id) }
    }

    // MARK: Overlays
    private func clearDecorations() {
        grips.values.forEach { $0.close() }; grips.removeAll(); hud.dismiss(animated: false)
        decorations.values.forEach { $0.close() }; decorations.removeAll()
        glow.hide(); dropHighlight.hide()
    }
    private func tabs(_ ids: [Int]) -> [StackTab] {
        let showing = ids.last
        let members = ids.compactMap { id in catalog.known.first(where: { $0.id == id }) }
        return barOrder(ids).compactMap { id -> StackTab? in
            guard let member = members.first(where: { $0.id == id }) else { return nil }
            // App names, until one app has two windows in the tile; then their titles tell them apart.
            let shared = members.filter { $0.pid == member.pid }.count > 1
            return StackTab(id: id, title: shared && !member.title.isEmpty ? member.title : member.appName,
                            icon: NSRunningApplication(processIdentifier: member.pid)?.icon, selected: showing == id,
                            action: { [weak self] in self?.select(id) })
        }
    }
    private func barActions(for window: TrackedWindow) -> [BarAction] {
        let floating = window.floated
        var list = [BarAction(title: "Principale", symbol: "sidebar.left", keys: ["⌃", "⌥", "↩"], enabled: !floating && !isPrimary(window), action: { [weak self] in self?.primary() }),
                    BarAction(title: focusActive ? "Quitter Focus" : "Focus", symbol: focusActive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                              keys: ["⌃", "⌥", "Z"], enabled: !floating, action: { [weak self] in self?.toggleFocus() })]
        if displays.count > 1 {
            list.append(BarAction(title: displays.count > 2 ? "Déplacer vers" : "Écran suivant", symbol: "display", keys: ["⌃", "⌥", "→"], action: { [weak self] in self?.nextScreen() }))
        }
        if NSEvent.modifierFlags.contains(.option) && !floating {
            list.append(BarAction(title: "Toujours flotter", symbol: "pin", keys: ["⌃", "⌥", "⇧", "F"], action: { [weak self] in self?.proposeFloatRule() }))
        } else {
            list.append(BarAction(title: floating ? "Ranger" : "Flotter", symbol: floating ? "rectangle.split.2x1" : "square.on.square", keys: ["⌃", "⌥", "F"], action: { [weak self] in self?.toggleFloat() }))
        }
        return list
    }
    func updateDecorations() {
        guard enabled, trusted, setupDone, !stageManager, !loading else { clearDecorations(); return }
        let focused = activeWindow
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownFront = front == ProcessInfo.processInfo.processIdentifier
        let tracked = focused.flatMap { f in windows.first { $0.id == f.id } }
        let dragging = dragKind != .none
        var live = Set<String>()
        if !cleanSpace && !dragging && (ownFront || tracked != nil) {
            for screen in displays {
                guard let state = states[screen.id] else { continue }
                for (index, ids) in state.groups.enumerated() {
                    let isActiveTile = ids.contains(tracked?.id ?? -1)
                    if focusActive && !isActiveTile { continue }
                    guard let window = windows.first(where: { $0.id == ids.last }), window.animatingTo == nil else { continue }
                    let frame = window.lastTarget ?? window.frame
                    let key = screen.id + ":\(index)"
                    if isActiveTile && quickActions {
                        live.insert(key)
                        let grip = grips[key] ?? StackGrip(); grips[key] = grip
                        let center = ScreenSpace.cocoa(CGRect(x: frame.midX, y: frame.minY - CGFloat(effectiveGap) / 2, width: 0, height: 0)).origin
                        grip.update(center: center, tabs: tabs(ids), kind: .active)
                        let area = ScreenSpace.cocoa(screen.frame)
                        grip.onEnter = { [weak self, weak grip] in
                            guard let self, let grip else { return }
                            self.hud.cancelClose(); self.hudPending?.cancel()
                            let work = DispatchWorkItem { [weak self, weak grip] in
                                guard let self, let grip, grip.isVisible else { return }
                                self.hud.show(key: key, center: CGPoint(x: grip.frame.midX, y: grip.frame.midY), area: area, tabs: self.tabs(ids), actions: self.barActions(for: window))
                            }
                            self.hudPending = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
                        }
                        grip.onExit = { [weak self] in self?.hudPending?.cancel(); if self?.hud.isVisible == true { self?.hud.scheduleClose() } }
                        hud.refresh(key: key, center: CGPoint(x: grip.frame.midX, y: grip.frame.midY), area: area, tabs: tabs(ids), actions: barActions(for: window))
                    } else if ids.count > 1 && !isActiveTile && !focusActive {
                        live.insert(key)
                        let grip = grips[key] ?? StackGrip(); grips[key] = grip
                        let center = ScreenSpace.cocoa(CGRect(x: frame.midX, y: frame.minY - CGFloat(effectiveGap) / 2, width: 0, height: 0)).origin
                        grip.update(center: center, tabs: tabs(ids), kind: .dots)
                        grip.onEnter = nil; grip.onExit = nil
                    }
                }
            }
            // A floating active window has its grip 5.5 pt above its top edge.
            if quickActions, let window = tracked, window.floated, let screen = display(for: window) {
                let key = "float:\(window.id)"; live.insert(key)
                let grip = grips[key] ?? StackGrip(); grips[key] = grip
                let center = ScreenSpace.cocoa(CGRect(x: window.frame.midX, y: window.frame.minY - 5.5, width: 0, height: 0)).origin
                let tab = StackTab(id: window.id, title: window.appName, icon: nil, selected: true, action: {})
                grip.update(center: center, tabs: [tab], kind: .active)
                let area = ScreenSpace.cocoa(screen.frame)
                grip.onEnter = { [weak self, weak grip] in
                    guard let self, let grip else { return }
                    self.hud.cancelClose(); self.hudPending?.cancel()
                    let work = DispatchWorkItem { [weak self, weak grip] in
                        guard let self, let grip else { return }
                        self.hud.show(key: key, center: CGPoint(x: grip.frame.midX, y: grip.frame.midY), area: area, tabs: [], actions: self.barActions(for: window))
                    }
                    self.hudPending = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
                }
                grip.onExit = { [weak self] in self?.hudPending?.cancel(); if self?.hud.isVisible == true { self?.hud.scheduleClose() } }
            }
        }
        for key in Array(grips.keys) where !live.contains(key) { grips.removeValue(forKey: key)?.close() }
        if let key = hud.anchorKey, !live.contains(key) { hud.dismiss() }

        // Glow on active.
        if highlight == "glow", let window = tracked, !window.floated, window.animatingTo == nil, !cleanSpace, !dragging {
            glow.show(above: ScreenSpace.cocoa(window.lastTarget ?? window.frame), gap: CGFloat(effectiveGap), color: tint)
        } else { glow.hide() }

        var decorationKeys = Set<String>()
        for screen in displays {
            let key = screen.id; decorationKeys.insert(key)
            let panel = decorations[key] ?? DecorationPanel(); decorations[key] = panel
            let active = tracked.flatMap { display(for: $0)?.id == key ? ($0.animatingTo ?? $0.frame) : nil }
            var holes = active.map { [ScreenSpace.cocoa($0)] } ?? []
            // The active app's sheets, popovers and dialogs stay bright with it.
            if let focused, noPeek {
                let app = AXUIElementCreateApplication(focused.pid)
                AXUIElementSetMessagingTimeout(app, 0.08)
                if let elements = axAttribute(app, kAXWindowsAttribute) as? [AXUIElement] {
                    holes += elements.filter { axAttribute($0, kAXSubroleAttribute) as? String != kAXStandardWindowSubrole }.compactMap { axFrame($0) }
                        .filter { $0.intersects(screen.frame) && $0 != focused.frame }.map(ScreenSpace.cocoa)
                }
            }
            var outlines: [CGRect] = []
            if !cleanSpace && !dragging {
                if highlight == "all" {
                    let showing = Set(states[key]?.groups.compactMap(\.last) ?? [])
                    outlines = windows.filter { showing.contains($0.id) && $0.animatingTo == nil }.map { ScreenSpace.cocoa($0.frame) }
                }
                else if highlight == "active", let window = tracked, !window.floated, window.animatingTo == nil, display(for: window)?.id == key { outlines = [ScreenSpace.cocoa(window.frame)] }
            }
            panel.render(screen: ScreenSpace.cocoa(screen.frame), holes: holes, dim: noPeek && !cleanSpace ? dimAmount : 0, outlines: outlines, color: tint, width: borderWidth, blur: noPeek && blurOthers)
        }
        for key in Array(decorations.keys) where !decorationKeys.contains(key) { decorations.removeValue(forKey: key)?.close() }
    }

    // MARK: Rows and previews for the interface
    private func updateRows() {
        for window in catalog.known where window.minimum == .zero {
            if let size = learned[window.bundle], size.count == 2 { window.minimum = CGSize(width: size[0], height: size[1]) }
        }
        let waiting = Set(states.values.flatMap { $0.groups.flatMap { $0.dropLast() } })
        windowRows = catalog.known.filter { $0.eligible && ($0.visible || $0.minimized) }.map { window in
            let screen = display(for: window)
            return WindowRow(id: window.id, app: window.appName, title: window.title, minimized: window.minimized, floating: window.floated,
                             waiting: waiting.contains(window.id), screen: screen?.name ?? "Écran", screenID: screen?.id ?? "", frame: window.frame,
                             icon: NSRunningApplication(processIdentifier: window.pid)?.icon, pid: window.pid)
        }
        let names = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }, uniquingKeysWith: { a, _ in a })
        minimumRows = learned.keys.sorted().map { MinimumRow(id: $0, name: names[$0] ?? $0, width: learned[$0]![0], height: learned[$0]![1]) }
    }
    /// The panes of a screen for the menu bar preview, positioned from 0 to 1 inside the usable area.
    func preview(for screen: DisplayOption) -> [PreviewPane] {
        guard let plan = plans[screen.id], let groups = states[screen.id]?.groups else { return [] }
        let active = activeWindow?.id
        return groups.enumerated().compactMap { index, ids in
            guard plan.frames.indices.contains(index), let top = ids.last, let window = catalog.known.first(where: { $0.id == top }) else { return nil }
            let f = plan.frames[index]
            let unit = CGRect(x: (f.minX - screen.frame.minX) / screen.frame.width, y: (f.minY - screen.frame.minY) / screen.frame.height,
                              width: f.width / screen.frame.width, height: f.height / screen.frame.height)
            return PreviewPane(id: index, unit: unit, app: window.appName, icon: NSRunningApplication(processIdentifier: window.pid)?.icon,
                               active: ids.contains(active ?? -1), stackCount: ids.count, focus: focusActive && focusSnapshot?.window.id == top)
        }
    }
    /// Windows for Tab View: tiled ones in layout order, then waiting ones, then minimized ones (newest first).
    func tabViewOrder(for screenID: String) -> [Int] {
        let groups = states[screenID]?.groups ?? []
        let tiled = groups.compactMap(\.last)
        let waiting = groups.flatMap { $0.dropLast().reversed() }
        let minimized = windowRows.filter { $0.minimized && $0.screenID == screenID }.map(\.id).reversed()
        return tiled + waiting + Array(minimized)
    }
    func forget(minimum bundle: String) {
        learned.removeValue(forKey: bundle); catalog.known.filter { $0.bundle == bundle }.forEach { $0.minimum = .zero; $0.refusal = nil }
        persist(); updateRows(); arrange()
    }
    func forgetMinimums() { learned.removeAll(); catalog.known.forEach { $0.minimum = .zero; $0.refusal = nil }; persist(); updateRows(); arrange() }

    // MARK: Activity
    enum Via { case keyboard, mouse, none }
    func record(_ feature: String?, _ via: Via, placed: Bool = false) {
        guard countActivity else { return }
        if activity.weekStart != ActivityStats.currentWeek() { activity = ActivityStats() }
        if placed { activity.placed += 1 }
        switch via { case .keyboard: activity.keyboard += 1; case .mouse: activity.mouse += 1; case .none: break }
        if let feature { activity.features[feature, default: 0] += 1 }
        persist()
    }
    func resetActivity() { activity = ActivityStats(); persist() }

    // MARK: Login item
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginMessage = SMAppService.mainApp.status == .requiresApproval ? "À approuver dans Réglages Système › Ouverture." : "" }
        catch { loginMessage = error.localizedDescription }
        objectWillChange.send()
    }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval }
    func openLoginItems() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!) }
    func apps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    // MARK: Keyboard shortcuts
    /// `char` is the printed key to look up in the current layout; nil keeps the fixed key code.
    private static let hotkeyTable: [(id: UInt32, code: Int, char: String?, mods: Int, catalog: String)] = [
        (1, kVK_ANSI_1, nil, controlKey | optionKey | cmdKey, "count"), (2, kVK_ANSI_2, nil, controlKey | optionKey | cmdKey, "count"),
        (3, kVK_ANSI_3, nil, controlKey | optionKey | cmdKey, "count"), (4, kVK_ANSI_4, nil, controlKey | optionKey | cmdKey, "count"),
        (5, kVK_ANSI_Z, "z", controlKey | optionKey, "focus"),
        (8, kVK_ANSI_Grave, "`", controlKey | optionKey, "stackNext"), (9, kVK_ANSI_Grave, "`", controlKey | optionKey | shiftKey, "stackPrevious"),
        (10, kVK_LeftArrow, nil, controlKey | optionKey, "left"), (11, kVK_RightArrow, nil, controlKey | optionKey, "right"),
        (12, kVK_UpArrow, nil, controlKey | optionKey, "up"), (13, kVK_DownArrow, nil, controlKey | optionKey, "down"),
        (14, kVK_Return, nil, controlKey | optionKey, "primary"), (15, kVK_ANSI_F, "f", controlKey | optionKey, "float"),
        (16, kVK_ANSI_D, "d", controlKey | optionKey, "noPeek"), (17, kVK_ANSI_P, "p", controlKey | optionKey, "clean"),
        (18, kVK_ANSI_RightBracket, "]", controlKey | optionKey, "next"), (19, kVK_ANSI_LeftBracket, "[", controlKey | optionKey, "previous"),
        (20, kVK_ANSI_Equal, "=", controlKey | optionKey, "bigger"), (21, kVK_ANSI_Minus, "-", controlKey | optionKey, "smaller"),
        (22, kVK_ANSI_0, nil, controlKey | optionKey, "reset"), (23, kVK_Tab, nil, optionKey, "tabView"), (24, kVK_Tab, nil, optionKey | shiftKey, "tabViewBack"),
        (25, kVK_ANSI_F, "f", controlKey | optionKey | shiftKey, "alwaysFloat")]

    private func installHotkeys() {
        hotkeys.forEach { UnregisterEventHotKey($0) }; hotkeys.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        shortcutIssue = ""; unavailableShortcuts = []
        guard shortcutsEnabled else { return }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            let engine = Unmanaged<WindowEngine>.fromOpaque(context).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) { engine.heldHotkey = nil } else { engine.handleHotkey(key.id) }
            return noErr
        }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { shortcutIssue = "macOS n’a pas pu installer les raccourcis de Mosaïque. Quitte Mosaïque et rouvre-la."; return }
        var failed: [String] = []
        for entry in Self.hotkeyTable {
            var ref: EventHotKeyRef?
            let code = KeyboardLayout.resolve(entry.char, fallback: entry.code)
            let status = RegisterEventHotKey(UInt32(code), UInt32(entry.mods), EventHotKeyID(signature: 0x4d4f5341, id: entry.id), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { hotkeys.append(ref) } else { failed.append(entry.catalog) }
        }
        unavailableShortcuts = Array(Set(failed))
        if !failed.isEmpty { shortcutIssue = "Une autre app utilise déjà certains raccourcis." }
    }
    private func handleHotkey(_ id: UInt32) {
        // Holding a shortcut acts once (Tab View keeps stepping while ⌥ is held).
        if heldHotkey == id && id != 23 && id != 24 && Date().timeIntervalSince(heldSince) < 0.4 { return }
        heldHotkey = id; heldSince = Date()
        guard enabled, trusted, setupDone, !stageManager else { return }
        if let window = activeWindow, let screen = display(for: window) { selectedDisplay = screen.id }
        switch id {
        case 1...4:
            let screen = activeWindow.flatMap(display(for:)) ?? pointerDisplay
            changeSettings(for: screen, notify: true) { $0.capacity = Int(id) }; record("count", .keyboard)
        case 5: toggleFocus()
        case 8: cycleStack()
        case 9: cycleStack(-1)
        case 10: move(.left)
        case 11: move(.right)
        case 12: move(.up)
        case 13: move(.down)
        case 14: primary()
        case 15: toggleFloat()
        case 16: toggleNoPeek(notify: true); record("noPeek", .keyboard)
        case 17: toggleCleanSpace()
        case 18: cycleWindow(1)
        case 19: cycleWindow(-1)
        case 20: resize(TileLayout.ratioStep)
        case 21: resize(-TileLayout.ratioStep)
        case 22: resetSizes(); record("reset", .keyboard)
        case 23: overviewStep?(1); record("tabView", .keyboard)
        case 24: overviewStep?(-1)
        case 25: proposeFloatRule()
        default: break
        }
    }

    // MARK: Built-in check on the demonstration windows
    func runFixtureTests() {
        guard trusted else { testReport = "BLOQUÉ : autorise cette copie dans Accessibilité avant le test réel."; return }
        guard !testing else { return }
        testing = true; deferred?.cancel(); deferred = nil
        Task { @MainActor in
            let saved = (displaySettings, exclusions, gap, whenFull, quickActions, learned, floatRules, catalog.testOnly, enabled, highlight)
            var results: [String] = []
            func check(_ name: String, _ condition: Bool) { results.append((condition ? "PASS " : "FAIL ") + name) }
            func settle() async { try? await Task.sleep(nanoseconds: 300_000_000) }
            defer {
                catalog.testOnly = saved.7
                displaySettings = saved.0; exclusions = saved.1; gap = saved.2; whenFull = saved.3; quickActions = saved.4; learned = saved.5; floatRules = saved.6; highlight = saved.9
                states.removeAll(); knownIDs.removeAll(); persist(); testing = false; enabled = saved.8
                testReport = results.joined(separator: "\n")
                let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mosaïque")
                try? ("Mosaïque " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " — " + ISO8601DateFormatter().string(from: Date()) + "\n" + testReport)
                    .write(to: root.appendingPathComponent("window-tests.txt"), atomically: true, encoding: .utf8)
                arrange()
            }
            catalog.testOnly = true; floatRules = []
            windows = catalog.scan()
            guard windows.count >= 5 else { results.append("BLOQUÉ : ouvre MosaiqueFixture.app (5 fenêtres de test), puis réessaie."); return }
            guard let screen = display(for: windows[0]) else { results.append("FAIL écran de test introuvable"); return }
            let fixtures = windows
            states.removeAll(); knownIDs.removeAll(); selectedDisplay = screen.id
            gap = 8; whenFull = "stack"; quickActions = true; highlight = "none"
            setConfig(DisplaySettings(kind: .grid, capacity: 2), for: screen)
            enabled = true; dirty = true; refresh(); await settle()
            check("5 fenêtres réelles suivies", windows.count == 5)
            check("2 cases sans perte de fenêtre", states[screen.id]?.groups.count == 2 && Set(states[screen.id]?.groups.flatMap { $0 } ?? []) == Set(fixtures.map(\.id)))
            let tops = states[screen.id]?.groups.compactMap { ids in fixtures.first(where: { $0.id == ids.last }).flatMap { axFrame($0.element) } } ?? []
            check("cases disjointes", tops.count == 2 && tops[0].intersection(tops[1]).isNull)
            check("positions et dimensions réellement acceptées", fixtures.allSatisfy { w in w.lastTarget.flatMap { t in axFrame(w.element).map { approximatelyEqual($0, t) } } == true })
            if let group = states[screen.id]?.groups.first(where: { $0.count > 1 }), let first = group.first, let second = group.last,
               let a = fixtures.first(where: { $0.id == first }), let b = fixtures.first(where: { $0.id == second }) {
                select(first); await settle(); check("activation d’un onglet", catalog.focused(pid: a.pid)?.id == first)
                select(second); await settle(); check("activation d’un autre onglet de la même app", catalog.focused(pid: b.pid)?.id == second)
            } else { check("pile disponible", false) }
            select(fixtures[0].id); await settle()
            let before = axFrame(fixtures[0].element)!
            toggleFocus(); await settle()
            check("Focus remplit l’écran", axFrame(fixtures[0].element).map { approximatelyEqual($0, screen.frame.insetBy(dx: effectiveGap, dy: effectiveGap)) } == true)
            endFocus(); await settle()
            check("Focus remet la fenêtre", axFrame(fixtures[0].element).map { approximatelyEqual($0, before) } == true)
            changeSettings(for: screen) { $0.kind = .columns; $0.capacity = 3 }; await settle()
            let columns = states[screen.id]?.groups.compactMap { ids in fixtures.first(where: { $0.id == ids.last }).flatMap { axFrame($0.element) } } ?? []
            check("colonnes pleine hauteur", columns.count >= 2 && columns.allSatisfy { abs($0.height - columns[0].height) < 3 })
            changeSettings(for: screen) { $0.kind = .grid; $0.capacity = 4 }; await settle()
            check("4 cases et une pile", states[screen.id]?.groups.count == 4 && states[screen.id]?.groups.contains(where: { $0.count > 1 }) == true)
            resize(0.05); await settle()
            check("⌃⌥= agrandit la fenêtre active", config(for: screen).customSizes)
            resetSizes(for: screen); await settle()
            check("⌃⌥0 rétablit les tailles", !config(for: screen).customSizes)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension Array where Element == TrackedWindow {
    func contains(_ window: TrackedWindow) -> Bool { contains { $0.id == window.id } }
}
