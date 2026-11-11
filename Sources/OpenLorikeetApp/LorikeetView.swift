import AppKit

/// A painted cartoon character animated from eight consistently framed poses.
/// Frame changes carry the expression; spring motion gives each gesture weight.
@MainActor
final class LorikeetView: NSView {
    enum Pose { case ready, working, happy, failed }
    private(set) var pose: Pose = .ready
    var look = NSPoint.zero { didSet { needsDisplay = true } }

    private var timer: Timer?
    private var began: TimeInterval = 0
    private var elapsed: Double = 0
    private var moving = false
    private var celebrates = false
    private let frames: [NSImage]

    override init(frame: NSRect) {
        let resources = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("OpenLorikeet_OpenLorikeetApp.bundle"))
        } ?? Bundle.module
        let url = resources.url(forResource: "lorikeet-atlas", withExtension: "png", subdirectory: "Assets")!
        let atlas = NSImage(contentsOf: url)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        frames = (0..<8).map { index in
            let cell = CGRect(x: CGFloat(index % 4) * CGFloat(atlas.width) / 4,
                              y: CGFloat(index / 4) * CGFloat(atlas.height) / 2,
                              width: CGFloat(atlas.width) / 4, height: CGFloat(atlas.height) / 2)
            return NSImage(cgImage: atlas.cropping(to: cell)!, size: NSSize(width: 100, height: 100))
        }
        super.init(frame: frame)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func animate(_ pose: Pose) {
        stop()
        self.pose = pose
        elapsed = 0
        look = .zero
        moving = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        celebrates = pose == .happy && UserDefaults.standard.object(forKey: "FeatherCelebrations") as? Bool != false
        needsDisplay = true
        guard moving else { return }
        began = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        moving = false
        needsDisplay = true
    }

    private func advance() {
        elapsed = ProcessInfo.processInfo.systemUptime - began
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || (pose == .happy && elapsed >= 1.8) {
            stop()
        }
        needsDisplay = true
    }

    private var frameIndex: Int {
        switch pose {
        case .ready:
            if moving && elapsed.truncatingRemainder(dividingBy: 3.7) > 3.54 { return 1 }
            return abs(look.x) + abs(look.y) > 0.2 ? 2 : 0
        case .working: return moving && elapsed.truncatingRemainder(dividingBy: 2.4) > 2.15 ? 2 : 3
        case .happy:
            guard moving else { return 6 }
            let sequence = [6, 5, 4, 5, 6, 5, 4, 5, 6]
            return sequence[min(sequence.count - 1, Int(elapsed / 0.14))]
        case .failed: return 7
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let t = moving && !reduced ? elapsed : 0
        let direction = reduced ? NSPoint.zero : look
        let size = min(bounds.width, bounds.height) * 0.91
        let breath = moving && !reduced ? sin(t * 2.7) : 0
        let hop = pose == .happy && moving && !reduced ? abs(sin(min(t, 1.2) * .pi / 0.6)) * max(0, 1 - t / 1.2) * 11 : 0
        let nod = pose == .working ? sin(t * 5) * 0.025 : 0
        context.saveGState()
        context.translateBy(x: bounds.midX + direction.x * 2, y: bounds.minY + 2 + hop)
        context.rotate(by: direction.x * -0.045 + nod)
        context.scaleBy(x: 1 - breath * 0.006, y: 1 + breath * 0.012)
        frames[frameIndex].draw(in: NSRect(x: -size / 2, y: 0, width: size, height: size),
                                from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGState()
        guard celebrates && moving && !reduced else { return }
        let colors: [NSColor] = [.systemGreen, .systemOrange, .systemBlue, .systemYellow]
        for index in 0..<8 {
            let age = t - Double(index) * 0.06
            guard age > 0, age < 1.2 else { continue }
            context.saveGState()
            context.translateBy(x: bounds.midX + CGFloat(index - 4) * 11 + sin(age * 6) * 4,
                                y: bounds.maxY - age * bounds.height * 0.75)
            context.rotate(by: age * 4 + Double(index))
            colors[index % colors.count].withAlphaComponent(min(1, (1.2 - age) * 3)).setFill()
            NSBezierPath(ovalIn: NSRect(x: -1.5, y: -4, width: 3, height: 8)).fill()
            context.restoreGState()
        }
    }
}
