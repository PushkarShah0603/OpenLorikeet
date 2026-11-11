import AppKit
import SceneKit

@MainActor
final class LorikeetView: NSView {
    enum Pose { case ready, working, happy, failed }

    private(set) var pose: Pose = .ready
    var look = NSPoint.zero {
        didSet {
            if timer == nil { updatePose(at: 0, animated: false) }
        }
    }

    private let renderer = SCNView(frame: .zero)
    private let bird = SCNNode()
    private let head = SCNNode()
    private let wings = [SCNNode(), SCNNode()]
    private var eyes: [SCNNode] = []
    private var feathers: [SCNNode] = []
    private var timer: Timer?
    private var began: TimeInterval = 0
    private var celebrates = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let scene = SCNScene()
        renderer.scene = scene
        renderer.backgroundColor = .clear
        renderer.antialiasingMode = .multisampling4X
        renderer.preferredFramesPerSecond = 30
        renderer.frame = bounds
        renderer.autoresizingMask = [.width, .height]
        addSubview(renderer)
        setAccessibilityElement(false)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 3.9
        let viewpoint = SCNNode()
        viewpoint.camera = camera
        viewpoint.position = SCNVector3(0, 0.26, 9)
        scene.rootNode.addChildNode(viewpoint)
        renderer.pointOfView = viewpoint
        light(.ambient, color: NSColor(srgbRed: 0.76, green: 0.85, blue: 1, alpha: 1), intensity: 530,
              at: SCNVector3Zero, in: scene)
        light(.omni, color: NSColor(srgbRed: 1, green: 0.92, blue: 0.79, alpha: 1), intensity: 1_050,
              at: SCNVector3(-3, 4, 5), in: scene)
        light(.omni, color: NSColor(srgbRed: 0.66, green: 0.88, blue: 1, alpha: 1), intensity: 500,
              at: SCNVector3(3, 2, -2), in: scene)
        scene.rootNode.addChildNode(bird)
        buildBird()
        let colors: [UInt32] = [0x6dd044, 0xffbc36, 0x4785ef, 0xff7651]
        for index in 0..<8 {
            let feather = shape(color: colors[index % colors.count], size: SCNVector3(0.07, 0.20, 0.025), in: scene.rootNode)
            feather.isHidden = true
            feathers.append(feather)
        }
        updatePose(at: 0, animated: false)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func animate(_ pose: Pose) {
        stop()
        self.pose = pose
        look = .zero
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        celebrates = animated && pose == .happy && UserDefaults.standard.object(forKey: "FeatherCelebrations") as? Bool != false
        updatePose(at: 0, animated: animated)
        guard animated else { return }
        began = ProcessInfo.processInfo.systemUptime
        renderer.isPlaying = true
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        feathers.forEach { $0.isHidden = true }
        renderer.isPlaying = false
    }

    private func advance() {
        let time = ProcessInfo.processInfo.systemUptime - began
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || (pose == .happy && time >= 1.8) {
            updatePose(at: 0, animated: false)
            stop()
            return
        }
        updatePose(at: time, animated: true)
    }

    private func updatePose(at time: Double, animated: Bool) {
        let direction = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? NSPoint.zero : look
        let idle = animated ? sin(time * 4.0) * 0.055 : 0
        let hop = pose == .happy && animated ? max(0, sin(time * 12)) * max(0, 1 - time) * 0.48 : 0
        let peek = pose == .ready && animated ? max(0, 1 - time / 0.26) * 0.35 : 0
        bird.position.y = idle + hop - peek
        bird.eulerAngles.y = -0.31 + direction.x * 0.2 + (animated ? sin(time * 2) * 0.07 : 0)
        let tilt: Double = pose == .failed ? -0.27 : direction.x * -0.16
        let nod = pose == .working && animated ? sin(time * 6) * 0.09 : 0
        head.eulerAngles = SCNVector3(-direction.y * 0.23 + nod, direction.x * 0.34, tilt)
        let flap = pose == .happy && animated ? max(0, sin(time * 22)) * max(0, 1 - time / 1.2) : 0
        for (index, wing) in wings.enumerated() {
            let side = index == 0 ? -1.0 : 1.0
            wing.eulerAngles.z = side * (0.14 + flap * 0.95)
            wing.eulerAngles.y = side * (0.11 + flap * 0.55)
        }
        let blink = animated && time.truncatingRemainder(dividingBy: 3.2) > 3.04
        eyes.forEach { $0.scale.y = blink ? 0.12 : 1 }
        for (index, feather) in feathers.enumerated() {
            let age = time - Double(index) * 0.075
            feather.isHidden = !celebrates || !animated || age <= 0 || age >= 1.2
            if !feather.isHidden {
                let offset = Double(index) / Double(feathers.count - 1)
                feather.position = SCNVector3((offset - 0.5) * 3.3 + sin(age * 6 + offset * 8) * 0.18,
                                              1.76 - age * 2.8, 1.5)
                feather.eulerAngles = SCNVector3(age * 4, age * 8, age * 5 + offset * 3)
                feather.opacity = min(1, (1.2 - age) * 3)
            }
        }
        renderer.needsDisplay = true
    }

    private func buildBird() {
        // The bird faces the camera. The head and shoulder pivots move independently.
        shape(color: 0x207947, size: SCNVector3(0.69, 0.85, 0.56), at: SCNVector3(0, -0.27, 0), in: bird)
        shape(color: 0xfa8026, size: SCNVector3(0.52, 0.67, 0.28), at: SCNVector3(0, -0.22, 0.40), in: bird)
        shape(color: 0xfec243, size: SCNVector3(0.40, 0.39, 0.19), at: SCNVector3(0, -0.02, 0.57), in: bird)
        for index in 0..<5 {
            let x = Double(index - 2) * 0.14
            let tail = shape(color: index.isMultiple(of: 2) ? 0x216853 : 0x2b985b, size: SCNVector3(0.13, 0.71, 0.10),
                             at: SCNVector3(x, -0.99, -0.34), in: bird)
            tail.eulerAngles = SCNVector3(0.35, 0, x * 0.7)
        }
        for (index, wing) in wings.enumerated() {
            let side = index == 0 ? -1.0 : 1.0
            wing.position = SCNVector3(side * 0.54, 0.08, 0.03)
            bird.addChildNode(wing)
            for plume in 0..<5 {
                let feather = shape(color: [0x247a45, 0x30984f, 0x39ac55, 0x51bb58, 0x69c75b][plume],
                                    size: SCNVector3(0.16, 0.54 - Double(plume) * 0.032, 0.14),
                                    at: SCNVector3(side * (0.28 - Double(plume) * 0.040), -0.48 + Double(plume) * 0.065,
                                                  0.11 + Double(plume) * 0.025), in: wing)
                feather.eulerAngles.z = side * (0.37 - Double(plume) * 0.06)
            }
            shape(color: 0x58ba50, size: SCNVector3(0.22, 0.36, 0.23),
                  at: SCNVector3(side * 0.10, -0.12, 0.10), in: wing)
            for toe in -1...1 {
                shape(color: 0x625162, size: SCNVector3(0.075, 0.072, 0.19),
                      at: SCNVector3(side * 0.25 + Double(toe) * 0.084, -1.08, 0.34), in: bird)
            }
        }
        head.position = SCNVector3(0, 0.53, 0.10)
        bird.addChildNode(head)
        shape(color: 0x1d4dc0, size: SCNVector3(0.66, 0.61, 0.54), at: SCNVector3(0, 0.24, 0), in: head)
        shape(color: 0x376adc, size: SCNVector3(0.49, 0.32, 0.46), at: SCNVector3(0, 0.49, 0.04), in: head)
        for side in [-1.0, 1.0] {
            shape(color: 0x384bd2, size: SCNVector3(0.26, 0.28, 0.20),
                  at: SCNVector3(side * 0.40, 0.09, 0.31), in: head)
            let eye = SCNNode()
            eye.position = SCNVector3(side * 0.34, 0.30, 0.42)
            eye.eulerAngles.y = side * 0.38
            head.addChildNode(eye)
            eyes.append(eye)
            shape(color: 0x2c2544, size: SCNVector3(0.164, 0.187, 0.105), in: eye)
            shape(color: 0xf79b39, size: SCNVector3(0.122, 0.136, 0.077), at: SCNVector3(0, 0, 0.053), in: eye)
            shape(color: 0x151220, size: SCNVector3(0.084, 0.100, 0.050), at: SCNVector3(0, 0, 0.103), in: eye)
            shape(color: 0xffffff, size: SCNVector3(0.028, 0.028, 0.015), at: SCNVector3(-0.026, 0.045, 0.145), in: eye)
        }
        shape(color: 0xd94e18, size: SCNVector3(0.17, 0.11, 0.22), at: SCNVector3(0, -0.07, 0.58), in: head)
        shape(color: 0xff9b23, size: SCNVector3(0.21, 0.15, 0.28), at: SCNVector3(0, 0.05, 0.57), in: head)
        let tip = shape(color: 0xf4731d, size: SCNVector3(0.11, 0.15, 0.13), at: SCNVector3(0, -0.025, 0.76), in: head)
        tip.eulerAngles.x = -0.40
    }

    @discardableResult
    private func shape(color: UInt32, size: SCNVector3, at position: SCNVector3 = SCNVector3Zero, in parent: SCNNode) -> SCNNode {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 20
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.47
        material.diffuse.contents = NSColor(srgbRed: CGFloat((color >> 16) & 255) / 255,
                                            green: CGFloat((color >> 8) & 255) / 255,
                                            blue: CGFloat(color & 255) / 255, alpha: 1)
        sphere.firstMaterial = material
        let node = SCNNode(geometry: sphere)
        node.position = position
        node.scale = size
        parent.addChildNode(node)
        return node
    }

    private func light(_ type: SCNLight.LightType, color: NSColor, intensity: CGFloat, at position: SCNVector3, in scene: SCNScene) {
        let light = SCNLight()
        light.type = type
        light.color = color
        light.intensity = intensity
        let node = SCNNode()
        node.light = light
        node.position = position
        scene.rootNode.addChildNode(node)
    }
}
