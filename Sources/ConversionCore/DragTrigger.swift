/// Pure gesture state; stale drag-pasteboard contents must never trigger a new gesture.
public struct DragTrigger: Sendable {
    public private(set) var isVisible = false
    private var wasPressed = false
    private var idleGeneration: Int?
    private var hasFreshFiles = false
    private var suppressed = false

    public init() {}

    @discardableResult
    public mutating func update(pressed: Bool, shift: Bool, generation: Int, hasFiles: Bool) -> Bool {
        if !pressed {
            idleGeneration = generation
            wasPressed = false
            hasFreshFiles = false
            suppressed = false
            isVisible = false
            return false
        }
        if !wasPressed {
            // Starting while a button is already held is deliberately ignored.
            suppressed = idleGeneration == nil
            wasPressed = true
        }
        if generation != idleGeneration {
            hasFreshFiles = hasFiles
        }
        isVisible = !suppressed && hasFreshFiles && hasFiles && shift
        return isVisible
    }

    public mutating func cancel() {
        suppressed = true
        isVisible = false
    }
}
