import AppKit
import SwiftUI
import ApplicationServices

/// The welcome tour: six steps in a centred window. Nothing on the user's screen moves before the
/// last step's "Ranger mon espace", which calls `engine.completeSetup()`.
final class TourController: NSObject, NSWindowDelegate {
    static let shared = TourController()
    static let size = CGSize(width: 920, height: 680)

    private var window: NSWindow?
    private var model: TourModel?
    private var ghost: NSWindow?
    private let hint = TourHintPanel()

    func show(engine: WindowEngine) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = TourModel(engine: engine)
        let w = Self.makeWindow(model: model)
        w.delegate = self
        w.center()
        model.onFinish = { [weak self] in self?.tuck() }
        model.onClose = { [weak self] in self?.window?.close() }
        model.onAskAccess = { [weak self] in self?.hint.show() }
        model.onHideHint = { [weak self] in self?.hint.close() }
        model.start()
        self.model = model
        window = w
        // Mosaïque has no Dock icon; it comes forward while the tour is open.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// A titled window whose content runs under the transparent title bar; 920×680 in total.
    static func makeWindow(model: TourModel) -> NSWindow {
        let w = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Bienvenue dans Mosaïque"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        let host = NSHostingView(rootView: TourRootView(model: model))
        host.sizingOptions = []
        w.contentView = host
        w.setFrame(CGRect(origin: .zero, size: size), display: false)
        return w
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        hint.close()
        model = nil
        window = nil
    }

    /// The tour shrinks toward the Mosaïque item in the menu bar, then closes.
    private func tuck() {
        hint.close()
        guard let w = window, let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { window?.close(); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        let g = NSWindow(contentRect: w.frame, styleMask: .borderless, backing: .buffered, defer: false)
        g.isOpaque = false
        g.backgroundColor = .clear
        g.hasShadow = true
        g.level = .floating
        g.ignoresMouseEvents = true
        g.isReleasedWhenClosed = false
        let layerView = NSView(frame: CGRect(origin: .zero, size: w.frame.size))
        layerView.wantsLayer = true
        layerView.layer?.contents = image
        layerView.layer?.contentsGravity = .resize
        layerView.layer?.cornerRadius = 12
        layerView.layer?.masksToBounds = true
        g.contentView = layerView
        g.orderFrontRegardless()
        ghost = g
        w.orderOut(nil)
        let target = Self.menuBarTarget(aspect: w.frame.width / w.frame.height)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.01 : 0.55
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            g.animator().setFrame(target, display: true)
            g.animator().alphaValue = 0.1
        }, completionHandler: { [weak self] in
            g.orderOut(nil)
            self?.ghost = nil
            w.close()
        })
    }

    /// Where the status item sits (its window lives in our process), or the top-right corner.
    private static func menuBarTarget(aspect: CGFloat) -> CGRect {
        let h: CGFloat = 22, wd = h * aspect
        if let item = NSApp.windows.first(where: { NSStringFromClass(type(of: $0)).contains("StatusBar") && $0.isVisible && $0.frame.width > 0 }) {
            let f = item.frame
            return CGRect(x: f.midX - wd / 2, y: f.midY - h / 2, width: wd, height: h)
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        return CGRect(x: screen.frame.maxX - 170 - wd / 2, y: screen.frame.maxY - 12 - h / 2, width: wd, height: h)
    }
}

// MARK: Model

final class TourModel: ObservableObject {
    static let stepNames = ["Bienvenue", "Autorisations", "Fonctions de base", "Outils avancés", "À ta façon", "Prêt"]

    let engine: WindowEngine?
    /// Opened again from Settings after setup: the last button just closes.
    let reopened: Bool

    @Published var step = 0
    @Published var forward = true
    @Published var settled = false
    @Published var input: TourInput = .keyboard
    @Published var trusted: Bool
    @Published var asked = false
    @Published var login: Bool
    @Published var loginNote = ""
    @Published var taken: [String] = []
    @Published var shortcutsOn = true
    @Published var finishing = false
    @Published var kind: LayoutKind { didSet { if engine?.defaultKind != kind { engine?.defaultKind = kind } } }
    @Published var capacity: Int { didSet { if engine?.defaultCapacity != capacity { engine?.defaultCapacity = capacity } } }
    @Published var highlight: String { didSet { if engine?.highlight != highlight { engine?.highlight = highlight } } }
    @Published var whenFull: String { didSet { if engine?.whenFull != whenFull { engine?.whenFull = whenFull } } }

    var onFinish: (() -> Void)?
    var onClose: (() -> Void)?
    var onAskAccess: (() -> Void)?
    var onHideHint: (() -> Void)?
    private var timer: Timer?
    private var loginApplied = false

    init(engine: WindowEngine?) {
        self.engine = engine
        reopened = engine?.setupDone ?? false
        trusted = engine == nil ? false : AXIsProcessTrusted()
        login = engine?.loginEnabled ?? true
        kind = engine?.defaultKind ?? .grid
        capacity = engine?.defaultCapacity ?? 3
        highlight = engine?.highlight ?? "none"
        whenFull = engine?.whenFull ?? "stack"
        taken = engine?.unavailableShortcuts ?? []
        shortcutsOn = engine?.shortcutsEnabled ?? true
        settled = reopened
    }

    func start() {
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }

    /// Live Accessibility status. The engine's own timer plays the trackpad tap when access arrives.
    private func poll() {
        let value = AXIsProcessTrusted()
        if value != trusted {
            withAnimation(.easeInOut(duration: 0.25)) { trusted = value; if value { asked = false } }
            if value { onHideHint?() }
        }
        if let engine {
            let list = engine.unavailableShortcuts
            if list != taken { taken = list }
            if engine.shortcutsEnabled != shortcutsOn { shortcutsOn = engine.shortcutsEnabled }
        }
    }

    // Navigation
    var canGoBack: Bool { step > 0 && !finishing }
    func go(to target: Int) {
        let target = min(max(0, target), Self.stepNames.count - 1)
        guard target != step else { return }
        forward = target > step
        onHideHint?()
        DispatchQueue.main.async { withAnimation(.tourWindow) { self.step = target } }
    }
    func next() { go(to: step + 1) }
    func back() { go(to: step - 1) }

    /// Step 1: the pile settles side by side, then the tour moves on.
    func useMosaique() {
        guard !settled else { next(); return }
        withAnimation(.tourWindow) { settled = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak self] in
            guard let self, self.step == 0 else { return }
            self.next()
        }
    }

    // Permissions
    func askAccess() {
        engine?.requestAccess()
        engine?.openAccessibility()
        withAnimation(.easeInOut(duration: 0.2)) { asked = true }
        onAskAccess?()
    }
    /// "Ouvrir à la connexion" is on by default the first time.
    func applyLoginDefault() {
        guard !loginApplied, !reopened, let engine else { return }
        loginApplied = true
        if !engine.loginEnabled { engine.setLogin(true) }
        refreshLogin()
    }
    func setLogin(_ on: Bool) {
        engine?.setLogin(on)
        if engine == nil { login = on } else { refreshLogin() }
    }
    private func refreshLogin() {
        guard let engine else { return }
        login = engine.loginEnabled
        loginNote = engine.loginMessage
    }

    /// Shortcut labels of the ids the engine couldn't register, in catalog order.
    var takenLabels: [String] {
        WindowEngine.shortcutCatalog.filter { taken.contains($0.id) }.map { $0.keys.joined() }
    }

    // Finish
    var canFinish: Bool { reopened || trusted }
    func finish() {
        guard !finishing else { return }
        if reopened { onClose?(); return }
        guard trusted else { return }
        finishing = true
        engine?.completeSetup()
        onFinish?()
    }
}

// MARK: Root view

struct TourRootView: View {
    @ObservedObject var model: TourModel
    @State private var detail: Int?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TourPalette(scheme)
        ZStack {
            p.background
            VStack(spacing: 0) {
                TourProgress(step: model.step, count: TourModel.stepNames.count) { model.go(to: $0) }
                    .frame(height: 44)
                ZStack(alignment: .top) {
                    stepView
                        .id(model.step)
                        .transition(.asymmetric(insertion: .modifier(active: TourSlide(x: model.forward ? 36 : -36, opacity: 0), identity: TourSlide(x: 0, opacity: 1)),
                                                removal: .modifier(active: TourSlide(x: model.forward ? -36 : 36, opacity: 0), identity: TourSlide(x: 0, opacity: 1))))
                }
                .padding(.horizontal, 36)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                bottomBar(p)
            }
            if let features = featureList {
                TourFeatureDetail(features: features, index: $detail, input: $model.input)
            }
        }
        .frame(minWidth: TourController.size.width, maxWidth: .infinity, minHeight: TourController.size.height, maxHeight: .infinity)
        .ignoresSafeArea()
        .onChange(of: model.step) { _, _ in detail = nil }
    }

    private var featureList: [TourFeature]? {
        guard detail != nil else { return nil }
        switch model.step { case 2: return TourFeatures.core; case 3: return TourFeatures.power; default: return nil }
    }

    @ViewBuilder private var stepView: some View {
        switch model.step {
        case 0: TourWelcomeStep(model: model)
        case 1: TourPermissionStep(model: model)
        case 2: TourFeatureStep(title: "Les gestes de tous les jours",
                                subtitle: "Survole une carte pour la voir en action, clique pour la démo complète.",
                                features: TourFeatures.core, columns: 3, model: model, detail: $detail)
        case 3: TourFeatureStep(title: "Les outils avancés",
                                subtitle: "Pour aller plus loin : la souris, le partage d’écran, la concentration.",
                                features: TourFeatures.power, columns: 4, model: model, detail: $detail)
        case 4: TourCustomizeStep(model: model)
        default: TourReadyStep(model: model)
        }
    }

    @ViewBuilder private func bottomBar(_ p: TourPalette) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(p.edge.opacity(0.6)).frame(height: 0.5)
            HStack(spacing: 10) {
                if model.canGoBack {
                    Button("Retour") { model.back() }
                        .buttonStyle(TourButtonStyle(kind: .secondary))
                        .keyboardShortcut(.leftArrow, modifiers: [.command])
                        .transition(.opacity)
                }
                Spacer()
                if model.step == 5 && !model.canFinish {
                    Label("En attente de l’accès Accessibilité", systemImage: "lock.fill")
                        .font(.system(size: 12)).foregroundStyle(p.text3)
                }
                Button(primaryTitle) { primaryAction() }
                    .buttonStyle(TourButtonStyle(kind: .primary))
                    .disabled(primaryDisabled)
                    .keyboardShortcut(detail == nil ? .defaultAction : nil)
            }
            .padding(.horizontal, 24)
            .frame(height: 60)
        }
        .animation(.easeInOut(duration: 0.2), value: model.step)
    }

    private var primaryTitle: String {
        switch model.step {
        case 0: return model.settled ? "Continuer" : "Utiliser Mosaïque"
        case 5: return model.reopened ? "Terminer" : "Ranger mon espace"
        default: return "Continuer"
        }
    }
    private var primaryDisabled: Bool { model.step == 5 ? (!model.canFinish || model.finishing) : false }
    private func primaryAction() {
        switch model.step {
        case 0: model.useMosaique()
        case 5: model.finish()
        default: model.next()
        }
    }
}

struct TourSlide: ViewModifier {
    let x: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.offset(x: x).opacity(opacity) }
}

/// Six segments in the title bar area; done and current steps are tinted.
struct TourProgress: View {
    let step: Int
    let count: Int
    let jump: (Int) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = TourPalette(scheme)
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.tourAccent : (i < step ? Color.tourAccent.opacity(0.45) : p.fill2))
                        .frame(width: i == step ? 34 : 18, height: 5)
                        .contentShape(Rectangle().inset(by: -6))
                        .onTapGesture { if i < step { jump(i) } }
                        .help(TourModel.stepNames[i])
                }
            }
            Text(TourModel.stepNames[step]).font(.system(size: 11.5, weight: .medium)).foregroundStyle(p.text3)
                .frame(width: 120, alignment: .leading)
                .contentTransition(.opacity)
        }
        .padding(.leading, 120)
        .frame(maxWidth: .infinity)
        .animation(.tourWindow, value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Étape \(step + 1) sur \(count) : \(TourModel.stepNames[step])")
    }
}
