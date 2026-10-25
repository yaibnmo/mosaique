import AppKit
import SwiftUI

/// The small guide that floats next to System Settings while the tour waits for Accessibility,
/// pointing at the switch. It follows the System Settings window and never takes clicks.
final class TourHintPanel {
    final class Placement: ObservableObject {
        enum Side { case left, right, none }
        /// Which side of the panel the arrow is on.
        @Published var side: Side = .left
    }

    static let size = CGSize(width: 292, height: 128)
    private var panel: NSPanel?
    private var timer: Timer?
    private var started = Date()
    private let placement = Placement()

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.contentView = NSHostingView(rootView: TourHintView(placement: placement))
            p.alphaValue = 0
            panel = p
        }
        started = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.follow() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        follow()
    }

    func close() {
        timer?.invalidate(); timer = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; panel.animator().alphaValue = 0 }, completionHandler: { panel.orderOut(nil) })
    }

    private func follow() {
        guard let panel else { return }
        let size = Self.size
        var origin: CGPoint?
        if let window = Self.systemSettingsFrame(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(window) }) ?? NSScreen.main {
            // The app switches sit near the right edge of the list, below the pane's header.
            let targetY = window.maxY - min(190, window.height * 0.42)
            let visible = screen.visibleFrame
            if window.maxX + size.width + 4 <= visible.maxX {
                placement.side = .left
                origin = CGPoint(x: window.maxX + 2, y: targetY - size.height / 2)
            } else if window.minX - size.width - 4 >= visible.minX {
                placement.side = .right
                origin = CGPoint(x: window.minX - size.width - 2, y: targetY - size.height / 2)
            } else {
                placement.side = .none
                origin = CGPoint(x: visible.maxX - size.width - 12, y: visible.minY + 12)
            }
            origin!.y = min(max(origin!.y, visible.minY + 4), visible.maxY - size.height - 4)
        } else if Date().timeIntervalSince(started) > 4, let screen = NSScreen.main {
            placement.side = .none
            origin = CGPoint(x: screen.visibleFrame.maxX - size.width - 12, y: screen.visibleFrame.maxY - size.height - 12)
        }
        guard let origin else { return }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }
    }

    /// Frame of the frontmost System Settings window, in Cocoa coordinates. Window bounds don't need
    /// screen recording permission; titles aren't read.
    private static func systemSettingsFrame() -> CGRect? {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 300, rect.height > 200 else { continue }
            let primary = NSScreen.screens.first?.frame.height ?? 0
            return CGRect(x: rect.minX, y: primary - rect.maxY, width: rect.width, height: rect.height)
        }
        return nil
    }
}

struct TourHintView: View {
    @ObservedObject var placement: TourHintPanel.Placement
    @State private var on = false
    @State private var nudge = false

    var body: some View {
        HStack(spacing: 0) {
            if placement.side == .left { arrow(pointing: .left) }
            card
            if placement.side == .right { arrow(pointing: .right) }
        }
        .frame(width: TourHintPanel.size.width, height: TourHintPanel.size.height)
        .environment(\.colorScheme, .dark)
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { nudge = true } }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { on.toggle() }
            }
        }
    }

    private enum Direction { case left, right }

    private func arrow(pointing d: Direction) -> some View {
        Image(systemName: d == .left ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
            .font(.system(size: 20))
            .foregroundStyle(Color.tourAccent)
            .shadow(color: .black.opacity(0.35), radius: 3)
            .offset(x: nudge ? (d == .left ? -5 : 5) : 0)
            .frame(width: 26)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20)
                Text("Mosaïque").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color(tourHex: 0xF5F5F7))
                Spacer()
                Capsule().fill(on ? Color.tourAccent : Color.white.opacity(0.2)).frame(width: 30, height: 18)
                    .overlay(Circle().fill(.white).frame(width: 14, height: 14).shadow(color: .black.opacity(0.3), radius: 1).offset(x: on ? 6 : -6))
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
            Text("Active Mosaïque dans la liste").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(tourHex: 0xF5F5F7))
            Text("Absente de la liste ? Clique sur + et choisis-la dans Applications.").font(.system(size: 11)).foregroundStyle(Color(tourHex: 0xEBEBF5, 0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(tourHex: 0x222226, 0.97)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        .padding(6)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}
