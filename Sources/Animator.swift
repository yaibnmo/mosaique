import AppKit
import QuartzCore

/// Moves other apps' windows smoothly by writing intermediate frames through Accessibility.
/// Each app gets its own queue, so a slow app never holds back the others.
final class WindowAnimator {
    static let shared = WindowAnimator()
    /// Seconds for a full move, from the reference spring (bounce 0.16, 0.62 s). Zero disables animation.
    var duration: TimeInterval = Easing.springDuration
    private let lock = NSLock()
    private var generation: [Int: Int] = [:]
    private var queues: [pid_t: DispatchQueue] = [:]

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Starts (or retargets) the animation of one window. `completion` runs on the main thread
    /// with the final write, and is skipped when a newer animation replaced this one.
    func animate(id: Int, element: AXUIElement, from: CGRect, to: CGRect, completion: @escaping (FrameWrite) -> Void) {
        let token = bump(id)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let distance = max(abs(from.minX - to.minX), abs(from.minY - to.minY), abs(from.width - to.width), abs(from.height - to.height))
        let length = (reduceMotion || distance < 4) ? 0 : duration
        queue(for: pid).async { [weak self] in
            guard let self else { return }
            if length > 0 {
                let app = AXUIElementCreateApplication(pid)
                let enhanced = axAttribute(app, "AXEnhancedUserInterface") as? Bool == true
                if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
                let start = CACurrentMediaTime()
                while self.current(id) == token {
                    let progress = min(1, (CACurrentMediaTime() - start) / length)
                    let eased = Easing.windowMove(progress * length)
                    if progress >= 1 { break }
                    axWriteFrame(element, interpolate(from, to, eased))
                    // About 60 steps a second; a slow app simply gets fewer, larger steps.
                    let next = start + (floor((CACurrentMediaTime() - start) * 60) + 1) / 60
                    let wait = next - CACurrentMediaTime()
                    if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
                }
                if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
            }
            guard self.current(id) == token else { return }
            let result = axSetFrame(element, to)
            DispatchQueue.main.async { if self.current(id) == token { completion(result) } }
        }
    }
    func cancel(_ id: Int) { _ = bump(id) }

    private func bump(_ id: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        let next = (generation[id] ?? 0) + 1
        generation[id] = next
        return next
    }
    private func current(_ id: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        return generation[id] ?? 0
    }
    private func queue(for pid: pid_t) -> DispatchQueue {
        lock.lock(); defer { lock.unlock() }
        if let queue = queues[pid] { return queue }
        let queue = DispatchQueue(label: "io.github.yaibnmo.mosaique.animate.\(pid)", qos: .userInteractive)
        queues[pid] = queue
        return queue
    }
}

func interpolate(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
           width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t).integral
}

