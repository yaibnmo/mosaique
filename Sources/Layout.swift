import Foundation
import CoreGraphics

enum LayoutKind: String, CaseIterable, Codable, Identifiable {
    case grid, columns
    var id: String { rawValue }
    var label: String { self == .grid ? "Grille" : "Colonnes" }
}

/// What a screen actually uses: tall screens always stack rows, whatever was picked.
enum LayoutStyle: Equatable { case fold, columns, rows }

struct DisplaySettings: Codable, Equatable {
    var kind: LayoutKind = .grid
    var capacity = 3
    /// Split ratios, empty until the user resizes. Grid: [centre, right column, left column].
    /// Columns and rows: the share of the remaining span for each split.
    var ratios: [Double] = []
    var customSizes: Bool { !ratios.isEmpty }

    init(kind: LayoutKind = .grid, capacity: Int = 3, ratios: [Double] = []) {
        self.kind = kind; self.capacity = capacity; self.ratios = ratios
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(LayoutKind.self, forKey: .kind) ?? .grid
        capacity = min(4, max(1, try c.decodeIfPresent(Int.self, forKey: .capacity) ?? 3))
        ratios = try c.decodeIfPresent([Double].self, forKey: .ratios) ?? []
    }
}

struct FloatRule: Codable, Identifiable, Equatable {
    let bundle: String
    let prefix: String
    var id: String { bundle + "|" + prefix }
    func matches(bundle: String, title: String) -> Bool {
        self.bundle == bundle && title.lowercased().hasPrefix(prefix.lowercased())
    }
}

enum Direction: CaseIterable {
    case left, right, up, down

    /// Screen-to-screen choice: the closest screen whose centre lies that way.
    func score(from: CGRect, to: CGRect) -> CGFloat? {
        let dx = to.midX - from.midX, dy = to.midY - from.midY
        switch self {
        case .left: guard dx < -1 else { return nil }; return -dx + abs(dy) * 2
        case .right: guard dx > 1 else { return nil }; return dx + abs(dy) * 2
        case .up: guard dy < -1 else { return nil }; return -dy + abs(dx) * 2
        case .down: guard dy > 1 else { return nil }; return dy + abs(dx) * 2
        }
    }

    /// The tile that way. A candidate must lie fully on that side (24 pt tolerance). Ranking:
    /// overlapping on the other axis first, then the nearest, then the top or left one, then the larger overlap.
    func neighbor(of index: Int, in frames: [CGRect]) -> Int? {
        guard frames.indices.contains(index) else { return nil }
        let from = frames[index], tolerance: CGFloat = 24
        let candidates = frames.indices.filter { $0 != index }.compactMap { other -> (Int, Bool, CGFloat, CGFloat, CGFloat)? in
            let to = frames[other]
            let gap: CGFloat, cross: CGFloat, overlap: CGFloat
            switch self {
            case .right: guard to.minX >= from.maxX - tolerance else { return nil }; gap = to.minX - from.maxX
                cross = to.minY; overlap = min(from.maxY, to.maxY) - max(from.minY, to.minY)
            case .left: guard to.maxX <= from.minX + tolerance else { return nil }; gap = from.minX - to.maxX
                cross = to.minY; overlap = min(from.maxY, to.maxY) - max(from.minY, to.minY)
            case .down: guard to.minY >= from.maxY - tolerance else { return nil }; gap = to.minY - from.maxY
                cross = to.minX; overlap = min(from.maxX, to.maxX) - max(from.minX, to.minX)
            case .up: guard to.maxY <= from.minY + tolerance else { return nil }; gap = from.minY - to.maxY
                cross = to.minX; overlap = min(from.maxX, to.maxX) - max(from.minX, to.minX)
            }
            return (other, overlap > 0, max(0, gap), cross, overlap)
        }
        return candidates.min { a, b in
            if a.1 != b.1 { return a.1 }
            if abs(a.2 - b.2) > 0.5 { return a.2 < b.2 }
            if abs(a.3 - b.3) > 0.5 { return a.3 < b.3 }
            if abs(a.4 - b.4) > 0.5 { return a.4 > b.4 }
            return a.0 < b.0
        }?.0
    }
}

/// One line between tiles that the user can move.
struct Divider: Equatable {
    let ratioIndex: Int
    /// True for a vertical line (tiles side by side).
    let vertical: Bool
    /// Start and length of the split frame along the moving axis.
    let start: CGFloat
    let length: CGFloat
    /// Space that is not shared by the ratio (the gap, plus gaps inside the second part for equal columns).
    let reserved: CGFloat
    let first: [Int]
    let second: [Int]
    /// Where the line sits (the middle of the gap).
    let position: CGFloat
    func ratio(forPosition value: CGFloat, gap: CGFloat) -> Double {
        let share = max(1, length - reserved)
        return TileLayout.clampRatio(Double((value - gap / 2 - start) / share))
    }
}

struct TilePlan: Equatable {
    var frames: [CGRect]
    var dividers: [Divider]
}

struct TileLayout {
    static let ratioRange = 0.05...0.95
    static let ratioStep = 0.05
    /// Narrowest useful column, as in the reference: three on a MacBook, four on a large monitor.
    static let minColumnWidth: CGFloat = 440
    /// Smallest tile considered usable when growing a neighbour.
    static let usableSize = CGSize(width: 480, height: 320)

    static func clampRatio(_ value: Double) -> Double { min(ratioRange.upperBound, max(ratioRange.lowerBound, value)) }

    static func style(_ kind: LayoutKind, bounds: CGRect) -> LayoutStyle {
        bounds.height > bounds.width ? .rows : (kind == .columns ? .columns : .fold)
    }
    static func maxColumns(in bounds: CGRect, gap: CGFloat) -> Int {
        let area = bounds.insetBy(dx: gap, dy: gap)
        return max(1, Int(floor((area.width - gap) / (minColumnWidth + gap))))
    }
    /// How many tiles this screen really holds with these settings.
    static func capacity(_ settings: DisplaySettings, bounds: CGRect, gap: CGFloat) -> Int {
        let n = min(4, max(1, settings.capacity))
        switch style(settings.kind, bounds: bounds) {
        case .rows: return min(n, 3)
        case .columns: return min(n, maxColumns(in: bounds, gap: gap))
        case .fold: return n
        }
    }
    static func ratio(_ settings: DisplaySettings, _ style: LayoutStyle, index: Int, count: Int) -> Double {
        if settings.ratios.indices.contains(index) { return clampRatio(settings.ratios[index]) }
        return style == .fold ? 0.5 : 1 / Double(count - index)
    }
    /// Ratios with every default filled in, for editing.
    static func fullRatios(_ settings: DisplaySettings, _ style: LayoutStyle, count: Int) -> [Double] {
        let splits = style == .fold ? (count == 4 ? 3 : max(0, count - 1)) : max(0, count - 1)
        return (0..<splits).map { ratio(settings, style, index: $0, count: count) }
    }

    static func frames(in bounds: CGRect, count: Int, kind: LayoutKind, gap: CGFloat) -> [CGRect] {
        plan(in: bounds, minimums: Array(repeating: .zero, count: max(0, min(count, 4))), settings: DisplaySettings(kind: kind), gap: gap)?.frames ?? []
    }

    private indirect enum Node {
        case leaf(Int, CGSize)
        /// `innerGaps` counts the gaps inside `b` that the ratio leaves out, so equal columns stay equal.
        case split(vertical: Bool, index: Int, ratio: Double, innerGaps: Int, Node, Node)

        var leaves: [Int] {
            switch self { case let .leaf(i, _): return [i]; case let .split(_, _, _, _, a, b): return a.leaves + b.leaves }
        }
        func minimum(gap: CGFloat) -> CGSize {
            switch self {
            case let .leaf(_, size): return size
            case let .split(vertical, _, _, _, a, b):
                let x = a.minimum(gap: gap), y = b.minimum(gap: gap)
                return vertical ? CGSize(width: x.width + gap + y.width, height: max(x.height, y.height))
                    : CGSize(width: max(x.width, y.width), height: x.height + gap + y.height)
            }
        }
        func place(in frame: CGRect, gap: CGFloat, frames: inout [CGRect], dividers: inout [Divider]) {
            switch self {
            case let .leaf(index, _): frames[index] = frame
            case let .split(vertical, index, ratio, innerGaps, a, b):
                let span = vertical ? frame.width : frame.height
                let origin = vertical ? frame.minX : frame.minY
                let available = span - gap
                let reserved = gap + CGFloat(innerGaps) * gap
                let aMin = a.minimum(gap: gap), bMin = b.minimum(gap: gap)
                let low = vertical ? aMin.width : aMin.height
                let high = available - (vertical ? bMin.width : bMin.height)
                let wanted = ((span - reserved) * CGFloat(ratio)).rounded()
                let first = max(low, min(high, wanted))
                var x = frame, y = frame
                if vertical { x.size.width = first; y.origin.x += first + gap; y.size.width = available - first }
                else { x.size.height = first; y.origin.y += first + gap; y.size.height = available - first }
                dividers.append(Divider(ratioIndex: index, vertical: vertical, start: origin, length: span, reserved: reserved,
                                        first: a.leaves, second: b.leaves, position: origin + first + gap / 2))
                a.place(in: x, gap: gap, frames: &frames, dividers: &dividers)
                b.place(in: y, gap: gap, frames: &frames, dividers: &dividers)
            }
        }
    }

    /// Frames for `minimums.count` tiles, moving split lines just enough to respect the minimums.
    /// Returns nil when they cannot all fit.
    static func plan(in bounds: CGRect, minimums: [CGSize], settings: DisplaySettings, gap: CGFloat) -> TilePlan? {
        let n = minimums.count
        guard n > 0, n <= 4, bounds.width > 0, bounds.height > 0 else { return nil }
        let g = max(0, min(gap, min(bounds.width, bounds.height) / 20))
        let area = bounds.insetBy(dx: g, dy: g)
        let leaves = minimums.enumerated().map { Node.leaf($0.offset, CGSize(width: max(1, $0.element.width), height: max(1, $0.element.height))) }
        let style = style(settings.kind, bounds: bounds)
        let tree: Node
        if n == 1 { tree = leaves[0] }
        else if style != .fold {
            var tail = leaves[n - 1]
            for i in stride(from: n - 2, through: 0, by: -1) {
                tail = .split(vertical: style == .columns, index: i, ratio: ratio(settings, style, index: i, count: n), innerGaps: n - i - 2, leaves[i], tail)
            }
            tree = tail
        } else {
            // The fold: halve the newest space, alternating vertical and horizontal. Four windows split the primary's column.
            let left: Node = n == 4 ? .split(vertical: false, index: 2, ratio: ratio(settings, style, index: 2, count: n), innerGaps: 0, leaves[0], leaves[3]) : leaves[0]
            let right: Node = n >= 3 ? .split(vertical: false, index: 1, ratio: ratio(settings, style, index: 1, count: n), innerGaps: 0, leaves[1], leaves[2]) : leaves[1]
            tree = .split(vertical: true, index: 0, ratio: ratio(settings, style, index: 0, count: n), innerGaps: 0, left, right)
        }
        let minimum = tree.minimum(gap: g)
        guard minimum.width <= area.width + 0.01, minimum.height <= area.height + 0.01 else { return nil }
        var frames = Array(repeating: CGRect.zero, count: n), dividers: [Divider] = []
        tree.place(in: area, gap: g, frames: &frames, dividers: &dividers)
        return TilePlan(frames: frames, dividers: dividers)
    }

    static func constrained(in bounds: CGRect, minimums: [CGSize], settings: DisplaySettings, gap: CGFloat) -> [CGRect]? {
        plan(in: bounds, minimums: minimums, settings: settings, gap: gap)?.frames
    }

    /// The reference grow rule, applied with `step` (+0.05 grows, -0.05 shrinks).
    static func grow(_ settings: DisplaySettings, tile: Int, count: Int, bounds: CGRect, step: Double) -> [Double] {
        let style = style(settings.kind, bounds: bounds)
        var r = fullRatios(settings, style, count: count)
        guard !r.isEmpty, tile < count else { return r }
        func add(_ i: Int, _ v: Double) { if r.indices.contains(i) { r[i] = clampRatio(r[i] + v) } }
        if style == .fold && count == 4 {
            let groups: [(Int, [Int], [Int])] = [(0, [0, 3], [1, 2]), (1, [1], [2]), (2, [0], [3])]
            for (index, first, second) in groups {
                if first.contains(tile) { add(index, step) } else if second.contains(tile) { add(index, -step) }
            }
        } else if tile < count - 1 {
            add(tile, step); add(tile - 1, -step)
        } else if style == .fold {
            add(tile - 1, -step); add(tile - 2, -step)
        } else {
            add(tile - 1, -step)
        }
        return r
    }

    /// Largest move from `old` toward `new` ratios that keeps every tile at least `minimum` (20-step bisection).
    static func bisect(old: [Double], new: [Double], fits: ([Double]) -> Bool) -> [Double] {
        if fits(new) { return new }
        var low = 0.0, high = 1.0
        func mix(_ t: Double) -> [Double] { zip(old, new).map { $0 + ($1 - $0) * t } }
        for _ in 0..<20 { let mid = (low + high) / 2; if fits(mix(mid)) { low = mid } else { high = mid } }
        return mix(low)
    }

    static func screenIndex(for frame: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        return screens.indices.max { a, b in
            func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
            let x = area(frame.intersection(screens[a])), y = area(frame.intersection(screens[b]))
            if x == y {
                return hypot(frame.midX - screens[a].midX, frame.midY - screens[a].midY)
                    > hypot(frame.midX - screens[b].midX, frame.midY - screens[b].midY)
            }
            return x < y
        }
    }
}

/// Which windows share each tile. Within a tile the last id is the one showing; earlier ids are in
/// least-recently-used order, so closing the showing window brings back the one used just before.
struct StackLayout {
    var groups: [[Int]] = []
    private(set) var rememberedTile: [Int: Int] = [:]
    /// Windows added to a stack on purpose stay stacked until the set of windows or the count changes.
    private var pinned: Set<Int> = []
    private var lastIDs: Set<Int> = []
    private var lastLimit = 0

    mutating func reconcile(ids: [Int], capacity: Int, preferred: Int?, stack: Bool) {
        let valid = Set(ids), limit = max(1, min(4, capacity))
        if valid != lastIDs || limit != lastLimit { pinned.removeAll() }
        lastIDs = valid; lastLimit = limit
        groups = groups.map { $0.filter { valid.contains($0) } }.filter { !$0.isEmpty }
        // A lower count merges the last tiles into the tile before them.
        while groups.count > limit {
            // The tile that stays keeps its showing window; the merged ones wait behind it.
            let last = groups.removeLast()
            groups[groups.count - 1].insert(contentsOf: last, at: 0)
        }
        // A free tile goes to a waiting window: the most recently used one of the largest stack.
        while groups.count < min(limit, ids.count) {
            guard let index = groups.indices.filter({ groups[$0].count > 1 && !groups[$0].contains(where: pinned.contains) })
                    .max(by: { groups[$0].count < groups[$1].count || (groups[$0].count == groups[$1].count && $0 > $1) }) else { break }
            let id = groups[index].remove(at: groups[index].count - 2)
            groups.append([id])
        }
        let existing = Set(groups.flatMap { $0 })
        for id in ids where !existing.contains(id) {
            if groups.count < limit { groups.append([id]) }
            else if stack {
                let tile = rememberedTile[id].flatMap { $0 < groups.count ? $0 : nil }
                    ?? groups.firstIndex(where: { preferred.map($0.contains) ?? false }) ?? max(0, groups.count - 1)
                groups[tile].append(id)
            }
        }
        if !stack {
            groups = groups.map { [$0.last!] }
            for id in ids where !groups.flatMap({ $0 }).contains(id) && groups.count < limit { groups.append([id]) }
        }
        for (tile, group) in groups.enumerated() { for id in group { rememberedTile[id] = tile } }
    }

    mutating func activate(_ id: Int) {
        guard let tile = groups.firstIndex(where: { $0.contains(id) }) else { return }
        groups[tile].removeAll { $0 == id }
        groups[tile].append(id)
    }

    /// Swaps the showing windows of two tiles; each stack stays with its tile.
    mutating func swap(_ first: Int, _ second: Int) {
        guard first != second,
              let a = groups.firstIndex(where: { $0.contains(first) }), let ai = groups[a].firstIndex(of: first),
              let b = groups.firstIndex(where: { $0.contains(second) }), let bi = groups[b].firstIndex(of: second), a != b else { return }
        groups[a][ai] = second; groups[b][bi] = first
    }

    /// Puts a window on top of another tile's stack.
    mutating func move(_ id: Int, to tile: Int) {
        guard groups.indices.contains(tile), let source = groups.firstIndex(where: { $0.contains(id) }), source != tile else { return }
        groups[source].removeAll { $0 == id }; groups[tile].append(id)
        pinned.insert(id)
        let target = groups[tile]
        groups.removeAll { $0.isEmpty }
        if let index = groups.firstIndex(of: target) { for member in target { rememberedTile[member] = index } }
    }

    /// Adds a window that is not tracked here yet on top of a tile (used when it arrives from another screen).
    mutating func insert(_ id: Int, onTile tile: Int) {
        guard groups.indices.contains(tile) else { groups.append([id]); return }
        groups[tile].append(id); pinned.insert(id); rememberedTile[id] = tile; lastIDs.insert(id)
    }
    /// Puts `new` exactly where `old` was (used when two screens trade windows).
    mutating func replace(_ old: Int, with new: Int) {
        guard let tile = tile(of: old), let index = groups[tile].firstIndex(of: old) else { return }
        groups[tile][index] = new; rememberedTile[new] = tile
        lastIDs.remove(old); lastIDs.insert(new)
    }
    mutating func remove(_ id: Int) {
        groups = groups.map { $0.filter { $0 != id } }.filter { !$0.isEmpty }
        lastIDs.remove(id)
    }
    func tile(of id: Int) -> Int? { groups.firstIndex(where: { $0.contains(id) }) }
}

enum Easing {
    /// The reference window spring: bounce 0.16 over 0.62 s, i.e. damping ratio 0.84 and response 0.45 s.
    static let springDuration: TimeInterval = 0.62
    static func windowMove(_ seconds: Double) -> CGFloat {
        let zeta = 0.84, omega = 2 * Double.pi / 0.45
        let damped = omega * (1 - zeta * zeta).squareRoot()
        let t = max(0, seconds)
        let value = 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        return CGFloat(seconds >= springDuration ? 1 : value)
    }
    /// Panels such as the stack bar and notices.
    static func panel(_ t: Double) -> CGFloat { CGFloat(cubicBezier(t, 0.25, 0.1, 0.25, 1)) }

    /// CSS-style cubic-bezier(x1, y1, x2, y2) solved for x = t.
    static func cubicBezier(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        func sample(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let a = 1 - 3 * p2 + 3 * p1, b = 3 * p2 - 6 * p1, c = 3 * p1
            return ((a * s + b) * s + c) * s
        }
        func slope(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let a = 1 - 3 * p2 + 3 * p1, b = 3 * p2 - 6 * p1, c = 3 * p1
            return (3 * a * s + 2 * b) * s + c
        }
        var s = t
        for _ in 0..<8 {
            let error = sample(s, x1, x2) - t
            if abs(error) < 1e-5 { break }
            let d = slope(s, x1, x2)
            if abs(d) < 1e-6 { break }
            s -= error / d
        }
        // Bisection fallback keeps the result monotonic for steep curves.
        if abs(sample(s, x1, x2) - t) > 1e-4 {
            var low = 0.0, high = 1.0
            s = t
            for _ in 0..<30 {
                let x = sample(s, x1, x2)
                if abs(x - t) < 1e-5 { break }
                if x < t { low = s } else { high = s }
                s = (low + high) / 2
            }
        }
        return sample(s, y1, y2)
    }
}
