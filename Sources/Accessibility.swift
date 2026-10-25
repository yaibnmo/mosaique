import AppKit
import ApplicationServices

func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let p = axAttribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = axAttribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: origin, size: size)
}

func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 3) -> Bool {
    abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
        && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
}

struct FrameWrite {
    let requested: CGRect
    let actual: CGRect?
    let error: AXError
    var accepted: Bool { error == .success && actual.map { approximatelyEqual($0, requested) } == true }
}

// Private but long-stable API used by yabai, Rectangle and AltTab to map an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

func axWindowID(_ element: AXUIElement) -> CGWindowID? {
    var id: CGWindowID = 0
    return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
}

/// One intermediate animation step: no read-back, no Enhanced UI toggling.
func axWriteFrame(_ element: AXUIElement, _ frame: CGRect) {
    var origin = frame.origin, size = frame.size
    guard let position = AXValueCreate(.cgPoint, &origin), let value = AXValueCreate(.cgSize, &size) else { return }
    AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
    AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
}

@discardableResult
func axSetFrame(_ element: AXUIElement, _ frame: CGRect) -> FrameWrite {
    guard frame.width > 0, frame.height > 0, frame.origin.x.isFinite, frame.origin.y.isFinite else {
        return FrameWrite(requested: frame, actual: axFrame(element), error: .illegalArgument)
    }
    var origin = frame.origin, size = frame.size
    guard let position = AXValueCreate(.cgPoint, &origin), let value = AXValueCreate(.cgSize, &size) else {
        return FrameWrite(requested: frame, actual: nil, error: .failure)
    }
    // AXEnhancedUserInterface (set by assistive tools) makes apps animate or drop frame writes.
    // Window managers such as Rectangle and yabai turn it off for the write, then restore it.
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    let app = AXUIElementCreateApplication(pid)
    let enhanced = axAttribute(app, "AXEnhancedUserInterface") as? Bool == true
    if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
    defer { if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }
    // Some apps constrain size according to the current screen. Repeat after moving.
    AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    let move = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
    let resize = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    return FrameWrite(requested: frame, actual: axFrame(element), error: move == .success ? resize : move)
}

final class TrackedWindow {
    let id: Int
    let element: AXUIElement
    let pid: pid_t
    let bundle: String
    let appName: String
    let original: CGRect
    var frame: CGRect
    var visible = false
    var minimized = false
    var eligible = true
    var minimum = CGSize.zero
    var lastTarget: CGRect?
    var refusal: (target: CGRect, actual: CGSize, time: TimeInterval)?
    var floated = false
    /// Final frame of a move in progress; the screen and the overlays follow this rather than the moving frame.
    var animatingTo: CGRect?
    var target: CGRect { animatingTo ?? frame }
    init(id: Int, element: AXUIElement, app: NSRunningApplication, frame: CGRect) {
        self.id = id; self.element = element; pid = app.processIdentifier
        bundle = app.bundleIdentifier ?? ""; appName = app.localizedName ?? "Application"
        original = frame; self.frame = frame
    }
    var title: String { axAttribute(element, kAXTitleAttribute) as? String ?? appName }
}

final class WindowCatalog {
    private(set) var known: [TrackedWindow] = []
    /// Front-to-back position of each tracked window at the last scan (0 is frontmost).
    private(set) var depth: [Int: Int] = [:]
    private var nextID = 1
    private var observers: [pid_t: AXObserver] = [:]
    var onChange: (() -> Void)?
    var exclusions: Set<String> = []
    /// Apps left out by name when their bundle identifier varies between macOS versions.
    var excludedNames: Set<String> = []
    var testOnly = false
    var floatRules: [FloatRule] = []

    func scan() -> [TrackedWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var visible: [pid_t: [CGRect]] = [:]
        var onScreen = Set<CGWindowID>()
        var stacking: [CGWindowID: Int] = [:]
        for row in info {
            if row[kCGWindowLayer as String] as? Int == 0, let number = row[kCGWindowNumber as String] as? Int { onScreen.insert(CGWindowID(number)); stacking[CGWindowID(number)] = stacking.count }
            guard let pid = row[kCGWindowOwnerPID as String] as? Int32,
                  row[kCGWindowLayer as String] as? Int == 0,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            visible[pid, default: []].append(rect)
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && (!testOnly || $0.bundleIdentifier == "io.github.yaibnmo.mosaique.fixture")
        }
        let livePIDs = Set(apps.map(\.processIdentifier))
        known.removeAll { !livePIDs.contains($0.pid) }
        for pid in Array(observers.keys) where !livePIDs.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        }
        for app in apps {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.08)
            // A busy app can miss the timeout. Its windows keep their last state instead of leaving
            // the layout for one scan, which used to reshuffle every tile.
            guard let elements = axAttribute(application, kAXWindowsAttribute) as? [AXUIElement] else {
                for window in known where window.pid == app.processIdentifier && app.isHidden { window.visible = false }
                continue
            }
            for window in known where window.pid == app.processIdentifier { window.visible = false }
            let live = elements
            known.removeAll { window in window.pid == app.processIdentifier && !live.contains(where: { CFEqual(window.element, $0) }) }
            observe(app: application, pid: app.processIdentifier, elements: elements)
            for element in elements {
                guard axAttribute(element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                      let frame = axFrame(element), frame.width > 1, frame.height > 1 else { continue }
                var position: DarwinBoolean = false, size: DarwinBoolean = false
                AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &position)
                AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &size)
                guard position.boolValue && size.boolValue else { continue }
                let window: TrackedWindow
                if let old = known.first(where: { CFEqual($0.element, element) }) { window = old }
                else { window = TrackedWindow(id: nextID, element: element, app: app, frame: frame); nextID += 1; known.append(window) }
                window.frame = frame
                window.minimized = axAttribute(element, kAXMinimizedAttribute) as? Bool == true
                window.eligible = !exclusions.contains(window.bundle) && !excludedNames.contains(window.appName) && axAttribute(element, "AXFullScreen") as? Bool != true && !floatRules.contains(where: { $0.matches(bundle: window.bundle, title: window.title) })
                // Match by window number: a window that is animating or being resized still counts as shown.
                let number = axWindowID(element)
                if let number, let position = stacking[number] { depth[window.id] = position } else { depth[window.id] = nil }
                let shown = number.map { onScreen.contains($0) }
                    ?? (visible[app.processIdentifier]?.contains(where: { approximatelyEqual($0, frame, tolerance: 5) }) ?? false)
                window.visible = !app.isHidden && !window.minimized && shown
            }
        }
        return known.filter { $0.visible && $0.eligible }
    }

    func focused(pid: pid_t?) -> TrackedWindow? {
        guard let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let element = axAttribute(app, kAXFocusedWindowAttribute) else { return nil }
        return known.first { CFEqual($0.element, element) }
    }

    private func observe(app: AXUIElement, pid: pid_t, elements: [AXUIElement]) {
        let observer: AXObserver
        if let existing = observers[pid] { observer = existing }
        else {
            var created: AXObserver?
            guard AXObserverCreate(pid, { _, _, _, context in
                guard let context else { return }
                Unmanaged<WindowCatalog>.fromOpaque(context).takeUnretainedValue().onChange?()
            }, &created) == .success, let created else { return }
            observer = created; observers[pid] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, context)
        }
        for element in elements {
            for name in [kAXUIElementDestroyedNotification, kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
                AXObserverAddNotification(observer, element, name as CFString, context)
            }
        }
    }

    deinit {
        for observer in observers.values { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }
}
