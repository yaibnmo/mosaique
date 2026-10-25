import SwiftUI
import AppKit

// Shared building blocks of the settings window: theme tokens, grouped cards and rows, and the
// reference's control styles (switch, segmented control, choice tiles, swatches, sliders, keycaps).
// Note: Layout.swift declares a `Divider` type, so hairlines here are drawn with rectangles.

extension Color {
    static func settingsHex(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// Light and dark tokens from the reference (`--text`, `--fill`, `--solid`, `--settings-bg`…).
struct SettingsPalette {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var text: Color { dark ? .settingsHex(0xF5F5F7) : .settingsHex(0x1D1D1F) }
    var text2: Color { dark ? .settingsHex(0xEBEBF5, 0.62) : .settingsHex(0x3C3C43, 0.78) }
    var text3: Color { dark ? .settingsHex(0xEBEBF5, 0.36) : .settingsHex(0x3C3C43, 0.5) }
    var fill: Color { dark ? .settingsHex(0xFFFFFF, 0.08) : .settingsHex(0x000000, 0.06) }
    var fill2: Color { dark ? .settingsHex(0xFFFFFF, 0.14) : .settingsHex(0x000000, 0.10) }
    var edge: Color { dark ? .settingsHex(0xFFFFFF, 0.13) : .settingsHex(0x000000, 0.14) }
    var solid: Color { dark ? .settingsHex(0x36363C) : .white }
    var background: Color { dark ? .settingsHex(0x232327) : .settingsHex(0xECECEE) }
    var sidebar: Color { dark ? .settingsHex(0x1E1E22) : .settingsHex(0xE6E6E8) }
    var accent: Color { Color(nsColor: .controlAccentColor) }
    var green: Color { .settingsHex(0x1F9D57) }
    var orange: Color { .settingsHex(0xFF9F0A) }

    static let windowBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0x23 / 255, green: 0x23 / 255, blue: 0x27 / 255, alpha: 1)
                                                                      : NSColor(srgbRed: 0xEC / 255, green: 0xEC / 255, blue: 0xEE / 255, alpha: 1)
    }
}

/// Reads the palette for the current appearance.
protocol SettingsThemed: View { var scheme: ColorScheme { get } }
extension SettingsThemed { var p: SettingsPalette { SettingsPalette(scheme) } }

// MARK: Navigation and search state

final class SettingsNav: ObservableObject {
    @Published var page = "general"
    @Published var query = ""
    /// The row to scroll to once its page is showing.
    @Published var target: String?
    /// The row that briefly lights up after a search jump.
    @Published var flash: String?

    func go(_ item: SettingsSearchItem) {
        query = ""
        page = item.page
        target = item.anchor
    }
}

private struct SettingsAnchor: ViewModifier {
    let id: String?
    @EnvironmentObject var nav: SettingsNav
    func body(content: Content) -> some View {
        if let id {
            content.id(id).background(
                Color(nsColor: .controlAccentColor).opacity(nav.flash == id ? 0.16 : 0)
                    .animation(.easeOut(duration: nav.flash == id ? 0.2 : 0.8), value: nav.flash)
            )
        } else { content }
    }
}
extension View {
    func settingsAnchor(_ id: String?) -> some View { modifier(SettingsAnchor(id: id)) }
}

// MARK: Groups and rows

/// `.s-group`: an optional 12/600 title, a card (radius 10, 0.5 pt edge) whose rows are separated by hairlines, an optional note.
struct SettingsGroup<Content: View>: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    var title: String? = nil
    var note: String? = nil
    var anchor: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.text2).padding(.leading, 4)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        VStack(spacing: 0) {
                            if index > 0 { Rectangle().fill(p.fill).frame(height: 0.5) }
                            row
                        }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.solid))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.edge, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let note {
                Text(note).font(.system(size: 11.5)).foregroundStyle(p.text3).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsAnchor(anchor)
    }
}

/// `.frow`: min 42 pt, padding 6/12, 13 pt label with an 11.5 pt hint in tertiary colour, control at right.
struct SettingsRow<Trailing: View>: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @Environment(\.isEnabled) private var enabled
    let label: String
    var hint: String? = nil
    var anchor: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13)).foregroundStyle(p.text)
                if let hint, !hint.isEmpty {
                    Text(hint).font(.system(size: 11.5)).foregroundStyle(p.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .frame(minHeight: 42)
        .settingsAnchor(anchor)
    }
}
extension SettingsRow where Trailing == EmptyView {
    init(label: String, hint: String? = nil, anchor: String? = nil) {
        self.init(label: label, hint: hint, anchor: anchor) { EmptyView() }
    }
}

/// A full-width row for content that is not a label plus a control (tiles, lists).
struct SettingsBlock<Content: View>: View {
    var anchor: String? = nil
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading).settingsAnchor(anchor)
    }
}

// MARK: Controls

/// `.sw`: 38×22, knob 18 with a springy overshoot (cubic-bezier .3,.7,.3,1.3 over 0.28 s). `.small` is 32×19.
struct SettingsSwitch: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @Environment(\.isEnabled) private var enabled
    @Binding var isOn: Bool
    var small = false

    var body: some View {
        let w: CGFloat = small ? 32 : 38, h: CGFloat = small ? 19 : 22, knob: CGFloat = small ? 15 : 18
        let inset = (h - knob) / 2
        ZStack(alignment: .leading) {
            Capsule().fill(isOn ? p.accent : p.fill2)
                .animation(.easeInOut(duration: 0.2), value: isOn)
            Circle().fill(Color.white).frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 1)
                .offset(x: isOn ? w - knob - inset : inset)
                .animation(.timingCurve(0.3, 0.7, 0.3, 1.3, duration: 0.28), value: isOn)
        }
        .frame(width: w, height: h)
        .contentShape(Capsule())
        .onTapGesture { if enabled { isOn.toggle() } }
        .opacity(enabled ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "activé" : "désactivé")
        .accessibilityAction { if enabled { isOn.toggle() } }
    }
}

/// `.seg`: fill background, radius 8, padding 2; 24 pt buttons, radius 6, 12 pt; the chosen one sits on a solid chip.
struct SettingsSegmented<Value: Hashable>: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @Namespace private var space

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index], on = option.value == selection
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selection = option.value } } label: {
                    Text(option.label).font(.system(size: 12, weight: on ? .medium : .regular))
                        .foregroundStyle(p.text)
                        .padding(.horizontal, 11).frame(height: 24)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.solid)
                                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.edge, lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "on", in: space)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.fill))
    }
}

/// `.choice`: fill, radius 9, min width 96, padding 10/6/8, 11.5 pt; chosen = accent 14 % with a 1.5 pt accent inset.
struct SettingsChoice<Thumb: View>: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let title: String
    let on: Bool
    var minWidth: CGFloat = 96
    let action: () -> Void
    @ViewBuilder var thumb: Thumb

    var body: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.18)) { action() } }) {
            VStack(spacing: 9) {
                thumb
                Text(title).font(.system(size: 12.5))
                    .foregroundStyle(p.text).lineLimit(2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 11).padding(.horizontal, 6).padding(.bottom, 10)
            // Rows of tiles use `.fixedSize(horizontal: false, vertical: true)` so every tile takes the tallest height.
            .frame(minWidth: minWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? p.accent.opacity(0.14) : p.fill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(p.accent, lineWidth: 1.5).opacity(on ? 1 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 18 pt colour circle. Selected: 2 pt solid ring, then 1.5 pt in tertiary text colour.
struct SettingsSwatch<Fill: ShapeStyle>: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let fill: Fill
    let on: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(p.text3).frame(width: 25, height: 25).opacity(on ? 1 : 0)
                Circle().fill(p.solid).frame(width: 22, height: 22).opacity(on ? 1 : 0)
                Circle().fill(fill).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(p.edge, lineWidth: 0.5))
            }
            .frame(width: 25, height: 25)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 150 pt slider with an accent tint and the value at right (40 pt, 12 pt tabular numerals).
struct SettingsSlider: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    @Environment(\.isEnabled) private var enabled
    @State private var dragging = false

    private func set(_ raw: Double) {
        let snapped = (raw / step).rounded() * step
        let clamped = min(range.upperBound, max(range.lowerBound, snapped))
        if abs(clamped - value) > step / 1000 { value = clamped }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Drawn rather than NSSlider: no tick marks and the same accent tint whether the window is key or not.
            GeometryReader { geo in
                let knob: CGFloat = 16, width = geo.size.width - knob
                let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                ZStack(alignment: .leading) {
                    Capsule().fill(p.fill).overlay(Capsule().strokeBorder(p.edge, lineWidth: 0.5)).frame(height: 6)
                    Capsule().fill(enabled ? p.accent : p.fill2).frame(width: max(6, fraction * width + knob / 2), height: 6)
                    Circle().fill(enabled ? p.accent : (p.dark ? Color.settingsHex(0x5A5A60) : Color.settingsHex(0xDCDCE0))).frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 0.5)
                        .scaleEffect(dragging ? 1.08 : 1)
                        .offset(x: fraction * width)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    dragging = true
                    let f = Double(min(1, max(0, (drag.location.x - knob / 2) / width)))
                    set(range.lowerBound + f * (range.upperBound - range.lowerBound))
                }.onEnded { _ in dragging = false })
                .animation(.easeOut(duration: 0.12), value: dragging)
            }
            .frame(width: 150, height: 20)
            .accessibilityElement()
            .accessibilityValue(format(value))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(value + step)
                case .decrement: set(value - step)
                @unknown default: break
                }
            }
            Text(format(value)).font(.system(size: 12).monospacedDigit()).foregroundStyle(p.text2)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// A round radio choice with its description, for "Quand un écran est plein".
struct SettingsRadioRow: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let label: String
    let hint: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.15)) { action() } }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 13)).foregroundStyle(p.text)
                    Text(hint).font(.system(size: 11.5)).foregroundStyle(p.text3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(p.solid)
                    Circle().strokeBorder(on ? p.accent : p.text3, lineWidth: on ? 1.5 : 1)
                    Circle().fill(p.accent).frame(width: 9, height: 9).opacity(on ? 1 : 0)
                }
                .frame(width: 18, height: 18)
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// `.caps kbd`: min 22×17, 500 11 pt, radius 4, fill.
struct SettingsKeycaps: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let keys: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys.indices, id: \.self) { index in
                Text(keys[index]).font(.system(size: 11, weight: .medium)).foregroundStyle(p.text2)
                    .padding(.horizontal, 5).frame(minWidth: 22, minHeight: 17)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(p.solid)
                        .shadow(color: .black.opacity(0.1), radius: 0, x: 0, y: 0.5))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(p.edge, lineWidth: 0.5))
            }
        }
        .fixedSize()
    }
}

/// A small bordered button in the reference's flat style.
struct SettingsButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View { SettingsButtonBody(configuration: configuration, prominent: prominent) }
    private struct SettingsButtonBody: SettingsThemed {
        @Environment(\.colorScheme) var scheme
        @Environment(\.isEnabled) private var enabled
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(prominent ? Color.white : p.text)
                .padding(.horizontal, 10).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(prominent ? p.accent : p.solid)
                    .shadow(color: .black.opacity(0.12), radius: 0.5, x: 0, y: 0.5))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(prominent ? Color.clear : p.edge, lineWidth: 0.5))
                .opacity(configuration.isPressed ? 0.7 : (enabled ? 1 : 0.45))
                .contentShape(Rectangle())
                .fixedSize()
        }
    }
}

/// A short tag such as "Par défaut".
struct SettingsTag: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(p.text2)
            .padding(.horizontal, 6).frame(height: 16)
            .background(Capsule().fill(p.fill))
    }
}

// MARK: Thumbnails

/// Layout thumbnails drawn like the menu bar ones (a 1440×798 canvas, gap 40, radius 60), scaled to the tile.
struct SettingsLayoutThumb: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let kind: LayoutKind
    let count: Int
    let on: Bool
    var width: CGFloat = 64
    var height: CGFloat = 36

    static func panes(kind: LayoutKind, count: Int) -> [CGRect] {
        let n = max(1, min(4, count))
        if kind == .columns || n <= 2 {
            return (0..<n).map { CGRect(x: CGFloat($0) / CGFloat(n), y: 0, width: 1 / CGFloat(n), height: 1) }
        }
        if n == 3 { return [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)] }
        return [CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
    }

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 1440, gap = max(2.5, 40 * scale), radius = max(2.5, 60 * scale)
            let canvas = CGSize(width: size.width, height: 798 * scale)
            let top = (size.height - canvas.height) / 2
            for unit in Self.panes(kind: kind, count: count) {
                var rect = CGRect(x: unit.minX * canvas.width, y: top + unit.minY * canvas.height, width: unit.width * canvas.width, height: unit.height * canvas.height)
                rect = rect.insetBy(dx: gap / 2, dy: gap / 2)
                let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
                context.fill(path, with: .color(on ? p.accent : (p.dark ? Color.settingsHex(0xFFFFFF, 0.22) : Color.settingsHex(0x000000, 0.18))))
            }
        }
        .frame(width: width, height: height)
    }
}

/// 70×42 pictograms for the four highlight choices: a big pane and two small ones, as in the reference.
struct SettingsHighlightThumb: SettingsThemed {
    @Environment(\.colorScheme) var scheme
    let mode: String
    let on: Bool

    var body: some View {
        Canvas { context, size in
            let accent = p.accent
            let gap: CGFloat = 3, inset: CGFloat = 3
            let h = size.height - inset * 2
            let bigW = (size.width - inset * 2 - gap) * 0.58
            let smallW = size.width - inset * 2 - gap - bigW
            let smallH = (h - gap) / 2
            let panes = [CGRect(x: inset, y: inset, width: bigW, height: h),
                         CGRect(x: inset + bigW + gap, y: inset, width: smallW, height: smallH),
                         CGRect(x: inset + bigW + gap, y: inset + smallH + gap, width: smallW, height: smallH)]
            let grey = p.dark ? Color.settingsHex(0xFFFFFF, 0.22) : Color.settingsHex(0x000000, 0.18)
            if mode == "glow" {
                let r = panes[0]
                var glow = context
                glow.addFilter(.blur(radius: 3))
                glow.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY - 1, width: r.width, height: 6), cornerRadius: 3), with: .color(accent.opacity(0.9)))
            }
            for (index, rect) in panes.enumerated() {
                context.fill(Path(roundedRect: rect, cornerRadius: 3.5, style: .continuous), with: .color(grey))
                if mode == "all" || (mode == "active" && index == 0) {
                    context.stroke(Path(roundedRect: rect.insetBy(dx: 0.9, dy: 0.9), cornerRadius: 3, style: .continuous), with: .color(accent), lineWidth: 1.8)
                }
            }
        }
        .frame(width: 70, height: 42)
    }
}

/// The 20×20 gradient square of a sidebar row, with a white 12 pt symbol.
struct SettingsNavIcon: View {
    let symbol: String
    let colors: (UInt32, UInt32)
    var size: CGFloat = 20
    var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(LinearGradient(colors: [.settingsHex(colors.0), .settingsHex(colors.1)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.55, weight: .regular)).foregroundStyle(.white))
    }
}
