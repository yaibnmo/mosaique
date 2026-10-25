import SwiftUI
import AppKit

// Tab View's content (⌥⇥): every screen as a map of its windows, then the windows waiting in stacks and the minimized ones.
// Colours and sizes follow the reference `.tabview`.

struct TabViewItem: Identifiable {
    enum State { case tiled, free, waiting, minimized }
    let id: Int
    let app: String
    let title: String
    let icon: NSImage?
    /// Real frame, in Accessibility coordinates.
    let frame: CGRect
    let state: State
    let screenName: String
}

struct TabViewScreen: Identifiable {
    let id: String
    let name: String
    let builtIn: Bool
    /// Usable area of the screen, in Accessibility coordinates.
    let frame: CGRect
    /// Windows drawn on the map, back to front.
    let mapItems: [TabViewItem]
    /// Windows waiting in stacks, then minimized windows.
    let chips: [TabViewItem]
    var count: Int { mapItems.count + chips.count }
}

struct TabViewSnapshot {
    var screens: [TabViewScreen] = []
    /// Selection order: per screen, tiled windows in layout order, free windows, waiting, then minimized.
    var order: [Int] = []
    /// Points per screen point on the maps.
    var scale: CGFloat = 0.25

    func item(_ id: Int?) -> TabViewItem? {
        guard let id else { return nil }
        for screen in screens {
            if let item = screen.mapItems.first(where: { $0.id == id }) ?? screen.chips.first(where: { $0.id == id }) { return item }
        }
        return nil
    }
    /// Map width: at most 560 pt and half the screen, scaled down together so several screens fit side by side.
    static func scale(for frames: [CGRect], maxWidth: CGFloat) -> CGFloat {
        guard !frames.isEmpty else { return 0.25 }
        let natural = frames.map { min(560, $0.width * 0.5) / $0.width }
        let base = natural.min() ?? 0.25
        let total = frames.reduce(0) { $0 + $1.width * base } + CGFloat(frames.count - 1) * 24
        return total > maxWidth ? base * maxWidth / total : base
    }
}

final class TabViewModel: ObservableObject {
    @Published var snapshot = TabViewSnapshot()
    @Published var selected: Int?
    @Published var current: Int?
    @Published var visible = false
    /// Hover only selects once the pointer has moved since Tab View appeared.
    var hoverEnabled = false
    /// Where each tile and chip sits in the panel, for the arrow keys.
    var rects: [Int: CGRect] = [:]
    var choose: (Int) -> Void = { _ in }
}

private func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
}

private enum TV {
    static let text = rgb(0xF5F5F7)
    static let text2 = rgb(0xEBEBF5, 0.62)
    static let text3 = rgb(0xEBEBF5, 0.42)
    static let tile = rgb(0xFFFFFF, 0x12 / 255)
    static let map = rgb(0xFFFFFF, 0x0F / 255)
    static let mapLine = rgb(0xFFFFFF, 0x1A / 255)
    static var accent: Color { Color(nsColor: .controlAccentColor) }
}

private struct TabViewRectsKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { $1 }) }
}

private extension View {
    func reportRect(_ id: Int) -> some View {
        background(GeometryReader { geo in Color.clear.preference(key: TabViewRectsKey.self, value: [id: geo.frame(in: .named("tabview"))]) })
    }
}

struct TabViewRoot: View {
    @ObservedObject var model: TabViewModel
    /// Draws the background fully opaque (for renders, where there is nothing behind to blur).
    var opaque = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        TabViewContent(model: model)
            .padding(20)
            .background(shape.fill(rgb(0x202024, opaque ? 1 : 0.86)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(rgb(0xFFFFFF, 0x29 / 255), lineWidth: 0.5))
            .environment(\.colorScheme, .dark)
            .fixedSize()
    }
}

private struct TabViewContent: View {
    @ObservedObject var model: TabViewModel

    var body: some View {
        let snapshot = model.snapshot
        let selected = snapshot.item(model.selected)
        let width = snapshot.screens.reduce(0) { $0 + ($1.frame.width * snapshot.scale).rounded() } + CGFloat(max(0, snapshot.screens.count - 1)) * 24
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(snapshot.screens) { screen in
                    TabViewScreenView(model: model, screen: screen, scale: snapshot.scale)
                }
            }
            Rectangle().fill(rgb(0xFFFFFF, 0.1)).frame(height: 0.5)
                .padding(.top, 11).padding(.bottom, 12)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Group {
                    if let selected {
                        (Text(selected.app).font(.system(size: 13, weight: .semibold)).foregroundColor(TV.text)
                         + Text("  " + selected.screenName + suffix(selected)).font(.system(size: 13)).foregroundColor(TV.text2))
                    } else {
                        Text("Aucune fenêtre").font(.system(size: 13)).foregroundColor(TV.text2)
                    }
                }
                .lineLimit(1).truncationMode(.tail)
                .layoutPriority(1)
                Spacer(minLength: 0)
                Text("Tab suivante · ⇧Tab précédente · flèches · lâche ⌥ pour changer · Échap")
                    .font(.system(size: 11.5)).foregroundColor(TV.text3)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(height: 17)
        }
        .frame(width: max(width, 320), alignment: .leading)
        .coordinateSpace(name: "tabview")
        .onPreferenceChange(TabViewRectsKey.self) { model.rects = $0 }
    }

    private func suffix(_ item: TabViewItem) -> String {
        switch item.state {
        case .minimized: return " · réduite"
        case .waiting: return " · en attente dans une case"
        default: return ""
        }
    }
}

private struct TabViewScreenView: View {
    @ObservedObject var model: TabViewModel
    let screen: TabViewScreen
    let scale: CGFloat

    var body: some View {
        let width = (screen.frame.width * scale).rounded()
        let height = (screen.frame.height * scale).rounded()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "display").font(.system(size: 11)).foregroundColor(TV.text2)
                    .padding(.trailing, 7)
                Text(screen.name).font(.system(size: 13, weight: .semibold)).foregroundColor(TV.text2).lineLimit(1)
                    .padding(.trailing, 7)
                Text(screen.count == 1 ? "1 fenêtre" : "\(screen.count) fenêtres").font(.system(size: 13)).foregroundColor(TV.text3)
                    .lineLimit(1)
            }
            .frame(height: 17)
            .padding(.bottom, 10)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TV.map)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TV.mapLine, lineWidth: 1))
                ForEach(screen.mapItems) { item in
                    let rect = tileRect(item.frame, map: CGSize(width: width, height: height))
                    TabViewTile(model: model, item: item, size: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .frame(width: width, height: height)
            TabViewChipRow(model: model, chips: screen.chips)
                .frame(width: width, alignment: .leading)
                .padding(.top, 11)
        }
        .frame(width: width)
    }

    /// The window's frame mapped into the map, inset 3, at least 20 × 20, kept inside the map.
    private func tileRect(_ frame: CGRect, map: CGSize) -> CGRect {
        var r = CGRect(x: (frame.minX - screen.frame.minX) * scale, y: (frame.minY - screen.frame.minY) * scale,
                       width: frame.width * scale, height: frame.height * scale).insetBy(dx: 3, dy: 3)
        r.size.width = max(20, min(r.width, map.width - 6)); r.size.height = max(20, min(r.height, map.height - 6))
        r.origin.x = min(max(r.minX, 3), map.width - 3 - r.width); r.origin.y = min(max(r.minY, 3), map.height - 3 - r.height)
        return r
    }
}

private struct TabViewTile: View {
    @ObservedObject var model: TabViewModel
    let item: TabViewItem
    let size: CGSize

    var body: some View {
        let on = model.selected == item.id
        let current = model.current == item.id
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let iconSize: CGFloat = size.height >= 90 ? 40 : 28
        let showIcon = size.height >= iconSize + 8 && size.width >= iconSize + 8
        let showName = size.height >= iconSize + 30 && size.width >= 64
        VStack(spacing: 6) {
            if showIcon, let icon = item.icon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            }
            if showName {
                Text(item.app).font(.system(size: 13, weight: .semibold)).foregroundColor(TV.text).lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: size.width, height: size.height)
        .background(shape.fill(on ? TV.accent.opacity(0.3) : TV.tile))
        .overlay(shape.strokeBorder(on ? TV.accent : (current ? rgb(0xFFFFFF, 0x4D / 255) : .clear), lineWidth: on ? 2 : 1))
        .animation(.easeOut(duration: 0.12), value: on)
        .contentShape(shape)
        .onHover { inside in if inside && model.hoverEnabled { model.selected = item.id } }
        .onTapGesture { model.choose(item.id) }
        .reportRect(item.id)
        .help(item.title)
    }
}

private struct TabViewChipRow: View {
    @ObservedObject var model: TabViewModel
    let chips: [TabViewItem]

    var body: some View {
        if chips.isEmpty {
            Text("Rien de réduit").font(.system(size: 12)).foregroundColor(TV.text3).frame(height: 28, alignment: .center)
        } else {
            TabViewFlow(spacing: 6) {
                ForEach(chips) { chip in TabViewChip(model: model, item: chip) }
            }
        }
    }
}

private struct TabViewChip: View {
    @ObservedObject var model: TabViewModel
    let item: TabViewItem

    var body: some View {
        let on = model.selected == item.id
        let current = model.current == item.id
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        HStack(spacing: 7) {
            if let icon = item.icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16) }
            Text(item.app).font(.system(size: 13)).foregroundColor(TV.text).lineLimit(1)
        }
        .padding(.leading, 6).padding(.trailing, 10)
        .frame(height: 28)
        .background(shape.fill(on ? TV.accent.opacity(0.3) : TV.tile))
        .overlay(shape.strokeBorder(on ? TV.accent : (current ? rgb(0xFFFFFF, 0x4D / 255) : .clear), lineWidth: on ? 2 : 1))
        .animation(.easeOut(duration: 0.12), value: on)
        .contentShape(shape)
        .onHover { inside in if inside && model.hoverEnabled { model.selected = item.id } }
        .onTapGesture { model.choose(item.id) }
        .reportRect(item.id)
        .help(item.title)
    }
}

/// Chips wrap onto new lines when a screen has many.
private struct TabViewFlow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += line + spacing; x = 0; line = 0 }
            x += size.width + spacing; line = max(line, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let fitted = CGSize(width: min(size.width, bounds.width), height: size.height)
            if x > bounds.minX && x + fitted.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(fitted))
            x += fitted.width + spacing; line = max(line, fitted.height)
        }
    }
}
