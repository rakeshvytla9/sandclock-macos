import AppKit
import ImageIO
import UniformTypeIdentifiers

// A local, menu-bar-only countdown. No network, permissions, or third-party libraries.
struct Remaining {
    let total: Int
    var days: Int { total / 86_400 }
    var hours: Int { (total % 86_400) / 3_600 }
    var minutes: Int { (total % 3_600) / 60 }
    var seconds: Int { total % 60 }
    init(target: Date, now: Date = Date()) {
        total = max(0, Int(ceil(target.timeIntervalSince(now))))
    }
    var menuTitle: String {
        String(format: "%dd %02dh %02dm %02ds", days, hours, minutes, seconds)
    }
}

// Logical grains are scheduled across the whole deadline. Even a multi-year
// timer only draws a small sliding window of grains, never millions of objects.
struct SandSchedule {
    let duration: Double
    let elapsed: Double
    var count: Double { max(1, ceil(duration * 4)) }
    var interval: Double { duration / count }
    var landed: Double { min(count, max(0, floor(elapsed / interval + 0.000001))) }
    var fill: Double { min(1, max(0, landed / count)) }
    var flight: Double { min(1.8, duration) }
    init(duration: Double, elapsed: Double) {
        self.duration = max(0.001, duration)
        self.elapsed = min(max(0.001, duration), max(0, elapsed))
    }
    func arrival(_ index: Double) -> Double { (index + 1) * interval }
    func progress(_ index: Double) -> Double {
        let arrival = arrival(index)
        let departure = max(0, arrival - flight)
        return min(1, max(0, (elapsed - departure) / max(0.001, arrival - departure)))
    }
}

// A shallow, projected height field. Deposits conserve volume; neighbouring
// columns exchange sand when their height difference exceeds the visual slope.
// There are around 80 columns, independent of the number of logical grains.
struct SandPile {
    private(set) var heights: [Double]
    let ceiling: Double
    let columnLimits: [Double]
    let depositionOrder: [Int]
    let slopeDivisor: Double
    private(set) var fill = 0.0
    var slopeLimit: Double { ceiling / (Double(heights.count) * slopeDivisor) }
    var volume: Double { heights.reduce(0, +) }
    var capacity: Double { columnLimits.reduce(0, +) }
    init(columns: Int, height: Double) {
        heights = Array(repeating: 0, count: max(3, columns))
        ceiling = max(1, height)
        columnLimits = Array(repeating: ceiling, count: heights.count)
        depositionOrder = Array((0..<heights.count).reversed())
        slopeDivisor = 1.5
    }
    init(capacities: [Double], feedColumn: Int, slopeDivisor: Double = 3) {
        columnLimits = capacities.map { max(0, $0) }
        heights = Array(repeating: 0, count: capacities.count)
        ceiling = max(1, columnLimits.max() ?? 1)
        depositionOrder = capacities.indices.sorted {
            abs($0 - feedColumn) == abs($1 - feedColumn) ? $0 < $1 : abs($0 - feedColumn) < abs($1 - feedColumn)
        }
        self.slopeDivisor = slopeDivisor
    }
    var landingColumn: Int {
        depositionOrder.first(where: { heights[$0] < columnLimits[$0] - 0.000001 }) ?? depositionOrder[0]
    }
    mutating func advance(to requested: Double) {
        let target = min(1, max(0, requested))
        if target < fill {
            heights = Array(repeating: 0, count: heights.count)
        }
        fill = target
        if target >= 1 { heights = columnLimits; return }
        let capacity = self.capacity
        guard capacity > 0 else { return }
        var added = max(0, capacity * target - volume)
        // Large jumps (launching the app or waking) are reconstructed in at most
        // 200 batches instead of replaying months of individual grain arrivals.
        let batch = capacity / 200
        while added > 0.000000001 {
            var deposit = min(batch, added)
            added -= deposit
            for column in depositionOrder {
                let portion = min(deposit, columnLimits[column] - heights[column])
                heights[column] += portion
                deposit -= portion
                if deposit < 0.000000001 { break }
            }
            settle(passes: 8)
        }
        settle(passes: 4)
    }
    mutating func settle(passes: Int) {
        for pass in 0..<passes {
            var moved = false
            for position in 0..<(heights.count - 1) {
                let left = pass % 2 == 0 ? position : heights.count - 2 - position
                let right = left + 1
                let difference = heights[right] - heights[left]
                let excess = abs(difference) - slopeLimit
                if excess > 0.000001 {
                    let receiver = difference > 0 ? left : right
                    let transfer = min(excess * 0.38, max(0, columnLimits[receiver] - heights[receiver]))
                    guard transfer > 0.000000001 else { continue }
                    if difference > 0 {
                        heights[right] -= transfer; heights[left] += transfer
                    } else {
                        heights[left] -= transfer; heights[right] += transfer
                    }
                    moved = true
                }
            }
            if !moved { break }
        }
    }
}

enum CountdownPhase {
    case calm, focused, urgent, complete
    init(fraction: Double, finished: Bool) {
        if finished { self = .complete }
        else if fraction <= 0.10 { self = .urgent }
        else if fraction <= 0.25 { self = .focused }
        else { self = .calm }
    }
}

func combineDeadline(day: Date, time: Date, zone: TimeZone) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    var pieces = calendar.dateComponents([.year, .month, .day], from: day)
    let clock = calendar.dateComponents([.hour, .minute, .second], from: time)
    pieces.hour = clock.hour; pieces.minute = clock.minute; pieces.second = clock.second
    guard let result = calendar.date(from: pieces) else { return nil }
    let check = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result)
    guard check == pieces else { return nil } // Reject nonexistent daylight-saving times.
    return result
}

enum Palette {
    static let background = NSColor(srgbRed: 0.055, green: 0.063, blue: 0.078, alpha: 1)
    static let card = NSColor(srgbRed: 0.095, green: 0.105, blue: 0.12, alpha: 1)
    static let text = NSColor(srgbRed: 0.95, green: 0.93, blue: 0.88, alpha: 1)
    static let muted = NSColor(srgbRed: 0.59, green: 0.61, blue: 0.63, alpha: 1)
    static let gold = NSColor(srgbRed: 0.94, green: 0.72, blue: 0.39, alpha: 1)
    static let amber = NSColor(srgbRed: 1, green: 0.56, blue: 0.24, alpha: 1)
    static let red = NSColor(srgbRed: 1, green: 0.35, blue: 0.31, alpha: 1)
}

final class Deadline {
    private let defaults = UserDefaults.standard
    private let persist: Bool
    var target: Date? {
        didSet {
            guard persist else { return }
            if let target { defaults.set(target.timeIntervalSince1970, forKey: "target") }
            else { defaults.removeObject(forKey: "target") }
        }
    }
    var started: Date { didSet { if persist { defaults.set(started.timeIntervalSince1970, forKey: "started") } } }
    var title: String { didSet { if persist { defaults.set(title, forKey: "title") } } }
    var timeZoneID: String { didSet { if persist { defaults.set(timeZoneID, forKey: "timeZone") } } }
    init(persist: Bool = true) {
        self.persist = persist
        let stamp = defaults.double(forKey: "target")
        target = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        let start = defaults.double(forKey: "started")
        started = start > 0 ? Date(timeIntervalSince1970: start) : Date()
        let storedTitle = defaults.string(forKey: "title") ?? ""
        let seededTitle = ["Make it happen", "Make it happen."].contains(storedTitle)
        title = seededTitle ? "" : storedTitle
        if persist && seededTitle { defaults.set("", forKey: "title") }
        timeZoneID = defaults.string(forKey: "timeZone") ?? "Asia/Kolkata"
    }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var fractionLeft: Double {
        guard let target else { return 0.72 }
        let span = target.timeIntervalSince(started)
        guard span > 0 else { return 0 }
        return min(1, max(0, target.timeIntervalSinceNow / span))
    }
    var remaining: Remaining? { target.map { Remaining(target: $0) } }
    var phase: CountdownPhase {
        CountdownPhase(fraction: fractionLeft, finished: target.map { $0 <= Date() } ?? false)
    }
    var accent: NSColor {
        switch phase {
        case .urgent: return Palette.red
        case .focused: return Palette.amber
        case .calm, .complete: return Palette.gold
        }
    }
    var dateDescription: String {
        guard let target else { return "Choose a moment worth working toward." }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy · h:mm:ss a z"
        return formatter.string(from: target)
    }
    var message: String {
        guard target != nil else { return "A little urgency. A lot of possibility." }
        switch phase {
        case .complete: return "Hope you made it."
        case .urgent: return "This is your moment. Make the next move."
        case .focused: return "The final stretch. Keep moving."
        case .calm: return "One grain at a time. One step closer."
        }
    }
}

final class Backdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Palette.background.setFill()
        bounds.fill()
        let glow = NSGradient(colors: [Palette.gold.withAlphaComponent(0.085), .clear])!
        glow.draw(fromCenter: NSPoint(x: bounds.midX, y: bounds.maxY - 185), radius: 1,
                  toCenter: NSPoint(x: bounds.midX, y: bounds.maxY - 185), radius: 245,
                  options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
    }
}

// Vector geometry and a handful of particles; no video, images, or physics engine.
final class HourglassView: NSView {
    var fraction: Double = 0.72 { didSet { needsDisplay = true } }
    var accent: NSColor = Palette.gold { didSet { needsDisplay = true } }
    var flowing = true
    var animationTimer: Timer?
    let epoch = ProcessInfo.processInfo.systemUptime
    private var lowerPile: SandPile?
    override var isOpaque: Bool { false }

    func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }
    func stopAnimation() { animationTimer?.invalidate(); animationTimer = nil }
    deinit { animationTimer?.invalidate() }

    private func grain(_ point: NSPoint, radius: CGFloat, opacity: CGFloat) {
        accent.withAlphaComponent(opacity).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius,
                                 width: radius * 2, height: radius * 2)).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let size = min(bounds.width / 220, bounds.height / 220)
        let transform = NSAffineTransform()
        transform.translateX(by: (bounds.width - 220 * size) / 2, yBy: (bounds.height - 220 * size) / 2)
        transform.scale(by: size)
        transform.concat()
        defer { NSGraphicsContext.restoreGraphicsState() }

        // A faint halo behind the glass.
        NSGradient(colors: [accent.withAlphaComponent(0.11), .clear])!.draw(
            fromCenter: NSPoint(x: 110, y: 105), radius: 3,
            toCenter: NSPoint(x: 110, y: 105), radius: 106,
            options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])

        let glass = NSBezierPath()
        glass.move(to: NSPoint(x: 61, y: 193))
        glass.curve(to: NSPoint(x: 105, y: 110), controlPoint1: NSPoint(x: 61, y: 150),
                    controlPoint2: NSPoint(x: 75, y: 133))
        glass.curve(to: NSPoint(x: 105, y: 100), controlPoint1: NSPoint(x: 111, y: 106),
                    controlPoint2: NSPoint(x: 111, y: 104))
        glass.curve(to: NSPoint(x: 61, y: 27), controlPoint1: NSPoint(x: 75, y: 80),
                    controlPoint2: NSPoint(x: 61, y: 66))
        glass.line(to: NSPoint(x: 159, y: 27))
        glass.curve(to: NSPoint(x: 115, y: 100), controlPoint1: NSPoint(x: 159, y: 66),
                    controlPoint2: NSPoint(x: 145, y: 80))
        glass.curve(to: NSPoint(x: 115, y: 110), controlPoint1: NSPoint(x: 109, y: 104),
                    controlPoint2: NSPoint(x: 109, y: 106))
        glass.curve(to: NSPoint(x: 159, y: 193), controlPoint1: NSPoint(x: 145, y: 133),
                    controlPoint2: NSPoint(x: 159, y: 150))
        glass.close()
        NSColor.white.withAlphaComponent(0.025).setFill()
        glass.fill()

        // Both chambers use volume-aware height, clipped to the glass silhouette.
        NSGraphicsContext.saveGraphicsState()
        glass.addClip()
        let topLevel = 109 + 78 * pow(max(0, fraction), 0.42)
        let topSand = NSBezierPath()
        topSand.move(to: NSPoint(x: 50, y: topLevel))
        topSand.curve(to: NSPoint(x: 170, y: topLevel),
                      controlPoint1: NSPoint(x: 87, y: topLevel + 3),
                      controlPoint2: NSPoint(x: 132, y: topLevel - 4))
        topSand.line(to: NSPoint(x: 170, y: 108))
        topSand.line(to: NSPoint(x: 50, y: 108))
        topSand.close()
        if fraction > 0 {
            NSGradient(starting: accent.withAlphaComponent(0.95),
                       ending: accent.withAlphaComponent(0.58))!.draw(in: topSand, angle: -90)
        }
        let accumulated = min(1, max(0, 1 - fraction))
        let lowerCount = 49
        let lowerWidth = 98.0 / Double(lowerCount)
        if lowerPile == nil {
            // Sample the lower chamber once. Each column stops at the curved
            // glass wall rather than using a rectangular container ceiling.
            let capacities = (0..<lowerCount).map { column -> Double in
                let x = 61 + (Double(column) + 0.5) * lowerWidth
                var bottom = 27.0
                var top = 100.0
                for _ in 0..<14 {
                    let middle = (bottom + top) / 2
                    if glass.contains(NSPoint(x: x, y: middle)) { bottom = middle }
                    else { top = middle }
                }
                return bottom - 27
            }
            lowerPile = SandPile(capacities: capacities, feedColumn: lowerCount / 2)
        }
        lowerPile!.advance(to: accumulated)
        let lowerProfile = lowerPile!.heights
        let pile = NSBezierPath()
        pile.move(to: NSPoint(x: 61, y: 27))
        for column in 0..<lowerCount {
            pile.line(to: NSPoint(x: 61 + (Double(column) + 0.5) * lowerWidth,
                                 y: 27 + lowerProfile[column]))
        }
        pile.line(to: NSPoint(x: 159, y: 27))
        pile.close()
        NSGradient(starting: accent.withAlphaComponent(0.88),
                   ending: accent.withAlphaComponent(0.48))!.draw(in: pile, angle: -90)

        if flowing && fraction > 0 {
            let time = ProcessInfo.processInfo.systemUptime - epoch
            let landing = min(100, 27 + lowerProfile[lowerCount / 2] + 0.5)
            // Falling grains accelerate through the neck.
            for index in 0..<15 {
                let phase = (time * 0.68 + Double(index) / 15).truncatingRemainder(dividingBy: 1)
                let y = 108 - (108 - landing) * phase * phase
                let x = 110 + sin(Double(index) * 11.3 + time * 2.5) * (0.5 + 1.2 * phase)
                grain(NSPoint(x: x, y: y), radius: index % 3 == 0 ? 1.15 : 0.7,
                      opacity: 0.5 + 0.4 * phase)
            }
            // Tiny ballistic arcs give the landing sand a light, flying scatter.
            for index in 0..<12 {
                let phase = (time * 1.1 + Double(index) / 12).truncatingRemainder(dividingBy: 1)
                let direction: Double = index % 2 == 0 ? -1 : 1
                let spread = 10 + Double(index % 5) * 3
                let x = 110 + direction * phase * spread
                let y = landing + 9 * sin(phase * .pi) - phase * spread * 0.30
                grain(NSPoint(x: x, y: y), radius: 0.75, opacity: (1 - phase) * 0.8)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // Glass highlights and brushed metal frame.
        NSColor.white.withAlphaComponent(0.22).setStroke()
        glass.lineWidth = 1.1
        glass.stroke()
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: 68, y: 184))
        highlight.curve(to: NSPoint(x: 92, y: 127),
                        controlPoint1: NSPoint(x: 69, y: 155),
                        controlPoint2: NSPoint(x: 79, y: 139))
        NSColor.white.withAlphaComponent(0.13).setStroke()
        highlight.lineWidth = 2
        highlight.stroke()
        for x: CGFloat in [49, 171] {
            let rail = NSBezierPath(roundedRect: NSRect(x: x - 1.5, y: 24, width: 3, height: 172),
                                    xRadius: 1.5, yRadius: 1.5)
            NSColor.white.withAlphaComponent(0.14).setFill(); rail.fill()
        }
        for y: CGFloat in [19, 193] {
            let cap = NSBezierPath(roundedRect: NSRect(x: 39, y: y, width: 142, height: 8),
                                   xRadius: 4, yRadius: 4)
            NSGradient(starting: NSColor(srgbRed: 0.40, green: 0.37, blue: 0.31, alpha: 1),
                       ending: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.21, alpha: 1))!.draw(in: cap, angle: 0)
        }
    }
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
           color: NSColor = Palette.text, alignment: NSTextAlignment = .left) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = NSFont.systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.alignment = alignment
    field.lineBreakMode = .byTruncatingTail
    return field
}

final class TimeTile: NSView {
    let number = label("00", size: 30, weight: .medium, alignment: .center)
    init(unit: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Palette.card.cgColor
        layer?.cornerRadius = 13
        layer?.borderColor = NSColor.white.withAlphaComponent(0.055).cgColor
        layer?.borderWidth = 1
        number.font = NSFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium)
        let caption = label(unit, size: 9, weight: .semibold, color: Palette.muted, alignment: .center)
        for child in [number, caption] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        NSLayoutConstraint.activate([
            number.centerXAnchor.constraint(equalTo: centerXAnchor),
            number.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            number.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 3),
            caption.centerXAnchor.constraint(equalTo: centerXAnchor),
            caption.topAnchor.constraint(equalTo: number.bottomAnchor, constant: 5),
            heightAnchor.constraint(equalToConstant: 85)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ value: Int, accent: NSColor) {
        number.stringValue = String(format: "%02d", value)
        number.font = NSFont.monospacedDigitSystemFont(ofSize: value > 999 ? 21 : 30, weight: .medium)
        number.textColor = accent
    }
}

final class ProgressView: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var accent = Palette.gold { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
        accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height),
                     xRadius: 2, yRadius: 2).fill()
    }
}

// Grains travel from left to right BEHIND the digits and accumulate on the right.
// This occupies exactly the countdown's width, with no separate side graphic.
func rasterImage(size: NSSize, scale: CGFloat = 2, drawing: () -> Void) -> NSImage {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: max(1, Int(ceil(size.width * scale))), pixelsHigh: max(1, Int(ceil(size.height * scale))),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    context.cgContext.clear(NSRect(origin: .zero, size: size))
    drawing()
    NSGraphicsContext.restoreGraphicsState()
    return NSImage(cgImage: bitmap.cgImage!, size: size)
}

final class SandDigitsView: NSView {
    var deadline: Deadline!
    var previewTime: Double?
    var previewBackground = false
    var text = "Set a deadline"
    let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    private var pile: SandPile?
    private var pileStart: Date?
    private var textImage: NSImage?
    private var textImageKey = ""
    func snapshot(scale: CGFloat = 2) -> NSImage {
        rasterImage(size: bounds.size, scale: scale) {
            effectiveAppearance.performAsCurrentDrawingAppearance { draw(bounds) }
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let deadline else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if previewBackground { Palette.background.setFill(); bounds.fill() }
        let accent: NSColor
        if dark { accent = deadline.accent }
        else {
            switch deadline.phase {
            case .urgent: accent = NSColor(srgbRed: 0.75, green: 0.14, blue: 0.12, alpha: 1)
            case .focused: accent = NSColor(srgbRed: 0.72, green: 0.34, blue: 0.08, alpha: 1)
            case .calm, .complete: accent = NSColor(srgbRed: 0.63, green: 0.38, blue: 0.12, alpha: 1)
            }
        }
        let channel = bounds.insetBy(dx: 2, dy: 4)
        let outline = NSBezierPath(roundedRect: channel, xRadius: 5, yRadius: 5)
        accent.withAlphaComponent(dark ? 0.08 : 0.065).setFill()
        outline.fill()
        let span = deadline.target?.timeIntervalSince(deadline.started) ?? 1
        let elapsed = Date().timeIntervalSince(deadline.started) + (previewTime ?? 0)
        let schedule = SandSchedule(duration: span, elapsed: elapsed)
        let accumulated = deadline.target == nil ? 0 : schedule.fill
        let columnCount = max(3, Int(channel.width / 2))
        if pile == nil || pile!.heights.count != columnCount || pile!.ceiling != channel.height || pileStart != deadline.started {
            pile = SandPile(columns: columnCount, height: channel.height)
            pileStart = deadline.started
        }
        pile!.advance(to: accumulated)
        let profile = pile!.heights
        let columnWidth = channel.width / Double(columnCount)
        func surface(_ x: Double) -> Double {
            let column = min(columnCount - 1, max(0, Int((x - channel.minX) / columnWidth)))
            return channel.minY + profile[column]
        }
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let bed = NSBezierPath()
        bed.move(to: NSPoint(x: channel.minX, y: channel.minY))
        bed.line(to: NSPoint(x: channel.minX, y: channel.minY + profile[0]))
        for column in 0..<columnCount {
            bed.line(to: NSPoint(x: channel.minX + (Double(column) + 0.5) * columnWidth,
                                 y: channel.minY + profile[column]))
        }
        bed.line(to: NSPoint(x: channel.maxX, y: channel.minY + profile[columnCount - 1]))
        bed.line(to: NSPoint(x: channel.maxX, y: channel.minY)); bed.close()
        accent.withAlphaComponent(dark ? 0.44 : 0.27).setFill()
        if accumulated > 0 { bed.fill() }
        for index in 0..<45 {
            let x = channel.minX + CGFloat((index * 37) % 149) / 149 * channel.width
            let y = channel.minY + 0.5 + CGFloat((index * 19) % 15) / 15 * (channel.height - 1)
            if y <= surface(x) {
                accent.withAlphaComponent(0.48).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 0.7, height: 0.7)).fill()
            }
        }
        // Recently landed grains ride the local surface as columns spill;
        // their accumulated volume lives in the column heights.
        func landing(_ index: Double) -> NSPoint {
            let column = max(0, pile!.landingColumn - Int(index.truncatingRemainder(dividingBy: 3)))
            let x = channel.minX + (Double(column) + 0.5) * columnWidth
            let y = min(channel.maxY - 0.5, surface(x) + 0.3)
            return NSPoint(x: x, y: y)
        }
        if deadline.target != nil {
            let count = Int(min(24, schedule.landed))
            for offset in 0..<count {
                let point = landing(schedule.landed - 1 - Double(offset))
                accent.withAlphaComponent(0.6).setFill()
                NSBezierPath(ovalIn: NSRect(x: point.x, y: point.y, width: 0.8, height: 0.8)).fill()
            }
        }
        if deadline.target != nil && schedule.elapsed < schedule.duration {
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let upcoming = min(16, Int(ceil(schedule.flight / schedule.interval)) + 1)
            if !reduce {
                for offset in 0..<upcoming {
                    let index = schedule.landed + Double(offset)
                    guard index < schedule.count else { break }
                    let arrival = schedule.arrival(index)
                    guard schedule.elapsed >= max(0, arrival - schedule.flight) else { continue }
                    let phase = schedule.progress(index)
                    let destination = landing(index)
                    let x = channel.minX + CGFloat(phase) * (destination.x - channel.minX)
                    let wave = sin(phase * .pi * 2 + index * 1.8) * 1.1 * (1 - phase)
                    let y = destination.y + (channel.maxY - 1 - destination.y) * (1 - phase * phase) + wave
                    accent.withAlphaComponent(0.40 + 0.24 * phase).setFill()
                    let radius: CGFloat = Int(index) % 3 == 0 ? 1.05 : 0.7
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: radius, height: radius)).fill()
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        // Text is always drawn LAST, above every grain, with a contrasting halo.
        let key = "\(text)|\(dark)|\(bounds.width)|\(bounds.height)"
        if textImage == nil || textImageKey != key {
            textImageKey = key
            textImage = rasterImage(size: bounds.size) {
                let shadow = NSShadow()
                shadow.shadowColor = (dark ? NSColor.black : NSColor.white).withAlphaComponent(0.9)
                shadow.shadowBlurRadius = 1.8
                shadow.shadowOffset = .zero
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: NSColor.labelColor, .shadow: shadow
                ]
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: NSPoint(x: round((bounds.width - size.width) / 2),
                                                  y: round((bounds.height - size.height) / 2)),
                                       withAttributes: attributes)
            }
        }
        textImage?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

final class CountdownController: NSViewController {
    let deadline: Deadline
    var saveAction: ((String, Date, String) -> Void)?
    var quitAction: (() -> Void)?
    var closeAction: (() -> Void)?
    var isEditing = false
    var hourglass: HourglassView?
    var titleLabel: NSTextField?
    var dateLabel: NSTextField?
    var messageLabel: NSTextField?
    var badgeLabel: NSTextField?
    var progressLabel: NSTextField?
    var progress: ProgressView?
    var tiles: [TimeTile] = []
    var nameField: NSTextField?
    var datePicker: NSDatePicker?
    var timePicker: NSDatePicker?
    var chosenDayLabel: NSTextField?
    var chosenWeekdayLabel: NSTextField?
    var chosenMonthLabel: NSTextField?
    var zonePicker: NSPopUpButton?
    var errorLabel: NSTextField?
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var zoneIDs: [String] = []

    init(deadline: Deadline) { self.deadline = deadline; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() { rebuild(editing: deadline.target == nil) }
    override func viewDidAppear() {
        super.viewDidAppear()
        if !reduceMotion && view.window?.isVisible == true { hourglass?.startAnimation() }
        update()
    }
    override func viewDidDisappear() { super.viewDidDisappear(); hourglass?.stopAnimation() }

    func rebuild(editing: Bool) {
        hourglass?.stopAnimation()
        hourglass = nil; tiles = []; progress = nil
        titleLabel = nil; dateLabel = nil; messageLabel = nil; badgeLabel = nil; progressLabel = nil
        nameField = nil; datePicker = nil; timePicker = nil; zonePicker = nil; errorLabel = nil
        chosenDayLabel = nil; chosenWeekdayLabel = nil; chosenMonthLabel = nil
        isEditing = editing
        let root = Backdrop(frame: NSRect(x: 0, y: 0, width: 400, height: editing ? 640 : 620))
        root.autoresizingMask = [.width, .height]
        root.appearance = NSAppearance(named: .darkAqua)
        view = root
        preferredContentSize = root.frame.size

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 26)
        ])
        func add(_ child: NSView, gap: CGFloat = 0, fullWidth: Bool = true) {
            stack.addArrangedSubview(child)
            if fullWidth { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
            stack.setCustomSpacing(gap, after: child)
        }

        let top = NSStackView()
        top.orientation = .horizontal
        top.distribution = .fill
        let brand = label("S A N D C L O C K", size: 10, weight: .bold, color: Palette.gold)
        let spacer = NSView()
        let status = label(editing ? "SET YOUR INTENTION" : "TIME IS MOVING", size: 8, weight: .semibold, color: Palette.muted)
        top.addArrangedSubview(brand); top.addArrangedSubview(spacer); top.addArrangedSubview(status)
        badgeLabel = status
        add(top, gap: 20)

        if editing {
            add(label("Give your time\na destination.", size: 31, weight: .semibold), gap: 8)
            // Multiline headings keep the form compact and readable.
            (stack.arrangedSubviews.last as? NSTextField)?.maximumNumberOfLines = 2
            let intro = label("Choose a deadline. Make every grain count.", size: 12, color: Palette.muted)
            add(intro, gap: 20)
            add(label("WHAT ARE YOU WORKING TOWARD?", size: 9, weight: .semibold, color: Palette.muted), gap: 8)
            let name = NSTextField(string: deadline.title)
            name.placeholderString = ""
            name.font = NSFont.systemFont(ofSize: 14)
            name.bezelStyle = .roundedBezel
            name.heightAnchor.constraint(equalToConstant: 30).isActive = true
            nameField = name
            add(name, gap: 18)

            add(label("PICK A DATE", size: 9, weight: .semibold, color: Palette.muted), gap: 8)
            let picker = NSDatePicker()
            picker.datePickerStyle = .clockAndCalendar
            picker.datePickerElements = [.yearMonthDay]
            picker.datePickerMode = .single
            picker.isBezeled = false
            picker.drawsBackground = true
            picker.font = NSFont.systemFont(ofSize: 14)
            picker.timeZone = deadline.timeZone
            picker.dateValue = deadline.target.flatMap { $0 > Date() ? $0 : nil } ?? Date().addingTimeInterval(86_400)
            picker.target = self; picker.action = #selector(updateDateSelection)
            datePicker = picker
            let calendarCard = NSView()
            calendarCard.wantsLayer = true
            calendarCard.layer?.backgroundColor = Palette.card.cgColor
            calendarCard.layer?.cornerRadius = 13
            calendarCard.heightAnchor.constraint(equalToConstant: 180).isActive = true
            picker.translatesAutoresizingMaskIntoConstraints = false
            calendarCard.addSubview(picker)
            let selected = NSStackView()
            selected.orientation = .vertical
            selected.alignment = .centerX
            selected.spacing = 5
            let weekday = label("", size: 9, weight: .semibold, color: Palette.muted, alignment: .center)
            let day = label("", size: 50, weight: .medium, color: Palette.gold, alignment: .center)
            let month = label("", size: 9, weight: .medium, color: Palette.muted, alignment: .center)
            chosenDayLabel = day; chosenWeekdayLabel = weekday; chosenMonthLabel = month
            for field in [weekday, day, month] { selected.addArrangedSubview(field) }
            selected.translatesAutoresizingMaskIntoConstraints = false
            calendarCard.addSubview(selected)
            NSLayoutConstraint.activate([
                picker.leadingAnchor.constraint(equalTo: calendarCard.leadingAnchor, constant: 10),
                picker.centerYAnchor.constraint(equalTo: calendarCard.centerYAnchor),
                picker.widthAnchor.constraint(equalToConstant: 150),
                picker.heightAnchor.constraint(equalToConstant: 160),
                selected.leadingAnchor.constraint(equalTo: picker.trailingAnchor, constant: 12),
                selected.trailingAnchor.constraint(equalTo: calendarCard.trailingAnchor, constant: -10),
                selected.centerYAnchor.constraint(equalTo: calendarCard.centerYAnchor)
            ])
            updateDateSelection()
            add(calendarCard, gap: 14)

            add(label("SET A TIME", size: 9, weight: .semibold, color: Palette.muted), gap: 8)
            let clock = NSDatePicker()
            clock.datePickerStyle = .textFieldAndStepper
            clock.datePickerElements = [.hourMinuteSecond]
            clock.isBezeled = true
            clock.drawsBackground = true
            clock.font = NSFont.systemFont(ofSize: 15)
            clock.timeZone = deadline.timeZone
            clock.dateValue = picker.dateValue
            clock.heightAnchor.constraint(equalToConstant: 30).isActive = true
            timePicker = clock
            add(clock, gap: 10)

            let zones = NSPopUpButton()
            zoneIDs = ["Asia/Kolkata", "UTC"]
            if !zoneIDs.contains(TimeZone.current.identifier) { zoneIDs.append(TimeZone.current.identifier) }
            if !zoneIDs.contains(deadline.timeZoneID) { zoneIDs.append(deadline.timeZoneID) }
            for identifier in zoneIDs {
                zones.addItem(withTitle: identifier == "Asia/Kolkata" ? "India · IST (UTC +05:30)" :
                              identifier == "UTC" ? "UTC (UTC +00:00)" : identifier.replacingOccurrences(of: "_", with: " "))
            }
            zones.selectItem(at: zoneIDs.firstIndex(of: deadline.timeZoneID) ?? 0)
            zones.target = self; zones.action = #selector(changeZone)
            zonePicker = zones
            add(zones, gap: 8)
            let error = label("", size: 11, color: Palette.red)
            errorLabel = error
            add(error, gap: 14)

            let actions = NSStackView()
            actions.orientation = .horizontal
            actions.distribution = .fillEqually
            let cancel = makeButton(deadline.target == nil ? "Close" : "Cancel", action: #selector(cancelEdit), primary: false)
            let save = makeButton(deadline.target == nil ? "Start the clock →" : "Save deadline →", action: #selector(save), primary: true)
            save.keyEquivalent = "\r"
            cancel.keyEquivalent = "\u{1b}"
            actions.addArrangedSubview(cancel); actions.addArrangedSubview(save)
            add(actions)
        } else {
            let title = label(deadline.title, size: 26, weight: .semibold)
            title.maximumNumberOfLines = 2
            title.lineBreakMode = .byWordWrapping
            titleLabel = title
            add(title, gap: 6)
            let date = label(deadline.dateDescription, size: 11, color: Palette.muted)
            dateLabel = date
            add(date, gap: 5)

            let glass = HourglassView(frame: .zero)
            glass.heightAnchor.constraint(equalToConstant: 222).isActive = true
            hourglass = glass
            add(glass, gap: 6)

            let row = NSStackView()
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 8
            for unit in ["DAYS", "HOURS", "MINUTES", "SECONDS"] {
                let tile = TimeTile(unit: unit)
                tiles.append(tile); row.addArrangedSubview(tile)
            }
            add(row, gap: 22)
            let bar = ProgressView()
            bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
            progress = bar
            add(bar, gap: 8)
            let used = label("", size: 9, weight: .medium, color: Palette.muted)
            progressLabel = used
            add(used, gap: 17)
            let message = label(deadline.message, size: 12, weight: .medium)
            messageLabel = message
            add(message, gap: 20)

            let footer = NSStackView()
            footer.orientation = .horizontal
            let edit = makeButton("Edit deadline", action: #selector(editDeadline), primary: false)
            let spacer = NSView()
            let quit = NSButton(title: "Quit", target: self, action: #selector(quit))
            quit.isBordered = false
            quit.contentTintColor = Palette.muted
            quit.font = .systemFont(ofSize: 11)
            footer.addArrangedSubview(edit); footer.addArrangedSubview(spacer); footer.addArrangedSubview(quit)
            add(footer)
        }
        update()
        if !reduceMotion && view.window?.isVisible == true { hourglass?.startAnimation() }
    }

    private func makeButton(_ title: String, action: Selector, primary: Bool) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        if primary { button.bezelColor = Palette.gold; button.contentTintColor = Palette.background }
        return button
    }
    func update() {
        guard !isEditing, let remaining = deadline.remaining else { return }
        hourglass?.fraction = deadline.fractionLeft
        hourglass?.accent = deadline.accent
        hourglass?.flowing = remaining.total > 0
        if remaining.total == 0 { hourglass?.stopAnimation() }
        for (tile, value) in zip(tiles, [remaining.days, remaining.hours, remaining.minutes, remaining.seconds]) {
            tile.update(value, accent: deadline.accent)
        }
        progress?.fraction = 1 - deadline.fractionLeft
        progress?.accent = deadline.accent
        let percent = Int((1 - deadline.fractionLeft) * 100)
        progressLabel?.stringValue = "\(percent)% USED · \(100 - percent)% REMAINING"
        messageLabel?.stringValue = deadline.message
        switch deadline.phase {
        case .complete: badgeLabel?.stringValue = "THE MOMENT IS HERE"
        case .urgent: badgeLabel?.stringValue = "MAKE YOUR MOVE"
        case .focused: badgeLabel?.stringValue = "THE FINAL STRETCH"
        case .calm: badgeLabel?.stringValue = "TIME IS MOVING"
        }
        badgeLabel?.textColor = deadline.phase == .calm ? Palette.muted : deadline.accent
    }
    @objc private func changeZone() {
        guard let zonePicker, zoneIDs.indices.contains(zonePicker.indexOfSelectedItem) else { return }
        datePicker?.timeZone = TimeZone(identifier: zoneIDs[zonePicker.indexOfSelectedItem])
        timePicker?.timeZone = datePicker?.timeZone
        updateDateSelection()
    }
    @objc private func updateDateSelection() {
        guard let picker = datePicker else { return }
        let formatter = DateFormatter()
        formatter.timeZone = picker.timeZone
        formatter.dateFormat = "dd"; chosenDayLabel?.stringValue = formatter.string(from: picker.dateValue)
        formatter.dateFormat = "EEEE"; chosenWeekdayLabel?.stringValue = formatter.string(from: picker.dateValue).uppercased()
        formatter.dateFormat = "MMMM yyyy"; chosenMonthLabel?.stringValue = formatter.string(from: picker.dateValue).uppercased()
    }
    @objc private func save() {
        guard let picker = datePicker, let clock = timePicker, let zones = zonePicker,
              zoneIDs.indices.contains(zones.indexOfSelectedItem) else { return }
        let zoneID = zoneIDs[zones.indexOfSelectedItem]
        guard let zone = TimeZone(identifier: zoneID),
              let target = combineDeadline(day: picker.dateValue, time: clock.dateValue, zone: zone) else {
            errorLabel?.stringValue = "Choose a valid time in this timezone."
            return
        }
        guard target.timeIntervalSinceNow >= 1 else {
            errorLabel?.stringValue = "Choose a time in the future."
            NSSound.beep()
            return
        }
        let name = (nameField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        saveAction?(String(name.prefix(70)), target, zoneID)
        rebuild(editing: false)
    }
    @objc private func cancelEdit() {
        if deadline.target != nil { rebuild(editing: false) }
        else { closeAction?() }
    }
    @objc private func editDeadline() { rebuild(editing: true) }
    @objc private func quit() { quitAction?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let deadline = Deadline()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var controller: CountdownController!
    var timer: Timer?
    var sandDigits: SandDigitsView?
    var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            let digits = SandDigitsView(frame: .zero)
            digits.deadline = deadline
            // Keep the standard status button. An animated custom subview makes
            // macOS repeatedly snapshot its view tree for menu bar replicants.
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            sandDigits = digits
            button.target = self; button.action = #selector(togglePopup)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Sandclock countdown. Click to view or edit your deadline.")
        }
        controller = CountdownController(deadline: deadline)
        controller.saveAction = { [weak self] title, date, zone in
            guard let self else { return }
            // Editing a deadline starts a new interval for the sand and progress display.
            self.deadline.started = Date()
            self.deadline.title = title
            self.deadline.timeZoneID = zone
            self.deadline.target = date
            self.update()
        }
        controller.quitAction = { NSApp.terminate(nil) }
        controller.closeAction = { [weak self] in self?.popover.performClose(nil) }
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        tick.fireDate = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 1)
        tick.tolerance = 0.03
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.update() }
        update()
        if deadline.target == nil || CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showPopup() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopup(); return true
    }
    private func update() {
        let text: String
        if let remaining = deadline.remaining {
            text = remaining.menuTitle
            statusItem.button?.toolTip = (deadline.title.isEmpty ? "" : deadline.title + "\n") + deadline.dateDescription
        } else {
            text = "Set a deadline"
            statusItem.button?.toolTip = "Sandclock · choose your target date and time"
        }
        sandDigits?.text = text
        let width = (text as NSString).size(withAttributes: [.font: sandDigits!.font]).width
        let length = ceil(width) + 4
        if statusItem.length != length { statusItem.length = length }
        statusItem.button?.setAccessibilityLabel("\(deadline.title.isEmpty ? "Countdown" : deadline.title). \(text). Click to view or edit deadline.")
        renderStatusFrame()
        if popover.isShown { controller.update() }
    }
    private func renderStatusFrame() {
        guard let button = statusItem.button, let digits = sandDigits else { return }
        digits.appearance = button.effectiveAppearance
        digits.frame = NSRect(x: 0, y: 0, width: statusItem.length, height: NSStatusBar.system.thickness)
        let scale = button.window?.backingScaleFactor ?? 2
        button.image = digits.snapshot(scale: scale)
    }
    @objc private func togglePopup() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let edit = NSMenuItem(title: "Set deadline…", action: #selector(editDeadline), keyEquivalent: "")
            edit.target = self
            menu.addItem(edit); menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit Sandclock", action: #selector(quit), keyEquivalent: "q")
            quit.target = self; menu.addItem(quit)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopup() }
    }
    private func showPopup() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func editDeadline() { _ = controller.view; controller.rebuild(editing: true); showPopup() }
    @objc private func quit() { NSApp.terminate(nil) }
    func popoverDidClose(_ notification: Notification) { controller.hourglass?.stopAnimation() }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); controller?.hourglass?.stopAnimation()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}

// Small, deterministic checks exercise boundary math without opening a UI.
if let previewIndex = CommandLine.arguments.firstIndex(where: { ["--render-preview", "--render-setup", "--render-menubar", "--render-complete"].contains($0) }), CommandLine.arguments.count > previewIndex + 1 {
    // Export the same native view offscreen; never overwrite the user's deadline.
    let app = NSApplication.shared
    app.appearance = NSAppearance(named: .darkAqua)
    let model = Deadline(persist: false)
    model.title = ""
    model.target = Date().addingTimeInterval(7 * 86_400 + 8 * 3_600 + 18 * 60 + 44)
    model.started = Date().addingTimeInterval(-4 * 86_400)
    if CommandLine.arguments[previewIndex] == "--render-complete" {
        model.started = Date().addingTimeInterval(-1_000)
        model.target = Date().addingTimeInterval(-1)
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[previewIndex + 1])
    if CommandLine.arguments[previewIndex] == "--render-menubar" {
        let view = SandDigitsView(frame: .zero)
        view.deadline = model
        view.previewBackground = true
        view.text = model.remaining!.menuTitle
        view.appearance = NSAppearance(named: .darkAqua)
        let textWidth = (view.text as NSString).size(withAttributes: [.font: view.font]).width
        view.frame = NSRect(x: 0, y: 0, width: ceil(textWidth) + 4, height: 24)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, 8, nil)!
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<8 {
            view.previewTime = Double(index)
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            CGImageDestinationAddImage(destination, bitmap.cgImage!, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0]
            ] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
        print("Exported native menu bar animation: grains enter left and settle right.")
    } else {
    if CommandLine.arguments[previewIndex] == "--render-setup" { model.target = nil }
    let controller = CountdownController(deadline: model)
    _ = controller.view
    controller.hourglass?.stopAnimation()
    let window = NSWindow(contentRect: controller.view.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.view.layoutSubtreeIfNeeded()
    let rectangle = controller.view.bounds
    let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: rectangle)!
    controller.view.cacheDisplay(in: rectangle, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(
        to: output)
    print("Exported native popup preview without changing the saved deadline.")
    }
} else if CommandLine.arguments.contains("--self-test") {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func check(_ seconds: Double, _ expected: String) {
        let result = Remaining(target: now.addingTimeInterval(seconds), now: now).menuTitle
        precondition(result == expected, "Expected \(expected), got \(result)")
    }
    check(90_061, "1d 01h 01m 01s")
    check(86_400, "1d 00h 00m 00s")
    check(3_600, "0d 01h 00m 00s")
    check(60, "0d 00h 01m 00s")
    check(0.1, "0d 00h 00m 01s")
    check(0, "0d 00h 00m 00s")
    check(-100, "0d 00h 00m 00s")
    let model = Deadline(persist: false)
    model.started = Date().addingTimeInterval(-1_000)
    model.target = Date().addingTimeInterval(1_000)
    precondition((0.49...0.51).contains(model.fractionLeft))
    model.target = Date().addingTimeInterval(-1)
    precondition(model.fractionLeft == 0 && model.remaining?.total == 0)
    model.started = Date().addingTimeInterval(1_000)
    precondition(model.fractionLeft == 0)
    for duration in [1.0, 60.0, 86_400.0, 365.0 * 86_400] {
        let start = SandSchedule(duration: duration, elapsed: 0)
        let middle = SandSchedule(duration: duration, elapsed: duration / 2)
        let end = SandSchedule(duration: duration, elapsed: duration)
        precondition(start.fill == 0)
        precondition(abs(middle.fill - 0.5) <= 1 / middle.count)
        precondition(end.fill == 1 && end.landed == end.count)
        precondition(abs(end.arrival(end.count - 1) - duration) < 0.0001)
        precondition(end.progress(end.count - 1) == 1)
    }
    var pile = SandPile(columns: 80, height: 16)
    for fill in [0.001, 0.05, 0.35, 0.75, 0.99, 1] {
        pile.advance(to: fill)
        let expected = 80.0 * 16 * fill
        precondition(abs(pile.volume - expected) < 0.00001, "Settling lost sand volume")
        precondition(pile.heights.allSatisfy { $0 >= -0.000001 && $0 <= 16.000001 })
    }
    precondition(pile.heights.allSatisfy { $0 == 16 })
    pile.advance(to: 0.1)
    precondition(abs(pile.volume - 128) < 0.00001)
    precondition(pile.heights.filter { $0 > 0.001 }.count > 3, "Sand did not spread sideways")
    let preserved = pile.volume
    pile.settle(passes: 200)
    precondition(abs(pile.volume - preserved) < 0.00001)
    precondition(CountdownPhase(fraction: 0.25001, finished: false) == .calm)
    precondition(CountdownPhase(fraction: 0.25, finished: false) == .focused)
    precondition(CountdownPhase(fraction: 0.10001, finished: false) == .focused)
    precondition(CountdownPhase(fraction: 0.10, finished: false) == .urgent)
    precondition(CountdownPhase(fraction: 0, finished: true) == .complete)
    model.started = Date().addingTimeInterval(-1_000)
    model.target = Date().addingTimeInterval(-1)
    precondition(model.message == "Hope you made it.")
    var shaped = SandPile(capacities: [2, 6, 10, 14, 18, 14, 10, 6, 2], feedColumn: 4)
    for fraction in [0.01, 0.2, 0.6, 0.9, 1] {
        shaped.advance(to: fraction)
        precondition(abs(shaped.volume - shaped.capacity * fraction) < 0.00001)
        precondition(zip(shaped.heights, shaped.columnLimits).allSatisfy { $0 >= -0.000001 && $0 <= $1 + 0.000001 })
    }
    let iso = ISO8601DateFormatter()
    let day = iso.date(from: "2032-02-29T00:00:00Z")!
    let clock = iso.date(from: "2029-06-01T08:09:10Z")!
    let combined = combineDeadline(day: day, time: clock, zone: TimeZone(identifier: "Asia/Kolkata")!)
    precondition(combined == iso.date(from: "2032-02-29T08:09:10Z"))
    let dstDay = iso.date(from: "2027-03-14T16:00:00Z")!
    let dstClock = iso.date(from: "2027-03-13T07:30:00Z")!
    precondition(combineDeadline(day: dstDay, time: dstClock, zone: TimeZone(identifier: "America/New_York")!) == nil)
    print("PASS: timer/grain schedules, rectangular and curved sand volumes/bounds, percentage phases, completion text, calendar/time merging, and DST validation.")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
