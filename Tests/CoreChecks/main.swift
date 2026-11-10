import Foundation
import CoreGraphics
import ConversionCore

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAIL: \(message)") }
}
func expectError(_ expected: ConversionError, operation: () throws -> Void) {
    do {
        try operation()
        fatalError("FAIL: expected \(expected)")
    } catch {
        check(error as? ConversionError == expected, "Unexpected error: \(error)")
    }
}
check(FileFormat(fileExtension: "JPG") == .jpeg, "Uppercase JPG alias")
check(FileFormat(fileExtension: "JPEG") == .jpeg, "JPEG alias")
check(FileFormat(fileExtension: "Md") == .markdown, "Markdown alias")
check(FileFormat(fileExtension: "tex") == .latex, "LaTeX alias")
for format in FileFormat.allCases {
    check(FileFormat(fileExtension: format.fileExtension) == format, "Extension round trip: \(format)")
}
check(FileFormat(fileExtension: "unknown") == nil, "Unknown extension")
expectError(.inputMustBeLocalFile) {
    _ = try ConversionRequest(source: URL(string: "https://example.com/file.docx")!, targetFormat: .pdf)
}
expectError(.unsupportedInput("file.unknown")) {
    _ = try ConversionRequest(source: URL(fileURLWithPath: "/tmp/file.unknown"), targetFormat: .pdf)
}
let source = URL(fileURLWithPath: "/tmp/પ્રોજેક્ટ notes.DOCX")
let first = try ConversionRequest(source: source, targetFormat: .pdf)
let second = try ConversionRequest(source: source, targetFormat: .pdf)
check(first.source == source.standardizedFileURL, "Unicode/spaces in local filename")
check(first.sourceFormat == .docx && first.targetFormat == .pdf, "Requested formats")
check(first.id != second.id, "Unique job IDs")
print("PASS: aliases, canonical extensions, remote/unknown input rejection, Unicode paths, and unique job IDs")

var gesture = DragTrigger()
check(!gesture.update(pressed: false, shift: false, generation: 10, hasFiles: true), "Idle ignores stale files")
check(!gesture.update(pressed: true, shift: true, generation: 10, hasFiles: true), "Shift-click ignores stale drag pasteboard")
check(gesture.update(pressed: true, shift: true, generation: 11, hasFiles: true), "Fresh file drag plus Shift reveals target")
check(!gesture.update(pressed: true, shift: false, generation: 11, hasFiles: true), "Shift release hides target")
check(gesture.update(pressed: true, shift: true, generation: 11, hasFiles: true), "Shift can reveal same active drag again")
gesture.cancel()
check(!gesture.update(pressed: true, shift: true, generation: 11, hasFiles: true), "Cancelled drag stays suppressed")
check(!gesture.update(pressed: false, shift: true, generation: 11, hasFiles: true), "Mouse release resets drag")
check(!gesture.update(pressed: true, shift: true, generation: 12, hasFiles: false), "Text/internal drag ignored")
check(!gesture.update(pressed: false, shift: false, generation: 12, hasFiles: false), "Release after non-file drag")
check(!gesture.update(pressed: true, shift: false, generation: 13, hasFiles: true), "File drag alone leaves Finder alone")
check(gesture.update(pressed: true, shift: true, generation: 13, hasFiles: true), "Shift added mid-drag reveals target")
check(!gesture.update(pressed: false, shift: true, generation: 13, hasFiles: true), "Dropping outside dismisses target")
var startedDuringDrag = DragTrigger()
check(!startedDuringDrag.update(pressed: true, shift: true, generation: 50, hasFiles: true), "Launch during held drag is ignored")
check(!startedDuringDrag.update(pressed: false, shift: false, generation: 50, hasFiles: true), "Release primes newly launched monitor")
check(startedDuringDrag.update(pressed: true, shift: true, generation: 51, hasFiles: true), "Next fresh gesture works after launch")
print("PASS: stale-pasteboard rejection, Shift transitions, cancellation suppression, mouse release, non-file drags, and launch during drag")

let doc = URL(fileURLWithPath: "/tmp/notes.docx")
let photo = URL(fileURLWithPath: "/tmp/photo.png")
check(PlannedChoices.commonTargets(for: [doc, photo]) == [.pdf], "Mixed selection uses shared planned targets")
check(PlannedChoices.commonTargets(for: []) == [], "Empty selection has no targets")
check(PlannedChoices.commonTargets(for: [doc, URL(fileURLWithPath: "/tmp/a.unknown")]).isEmpty, "Unknown input prevents misleading mixed choices")
var picker = PickerSession(sources: [doc])
check(try picker.select(.png, droppedURLs: [doc]) == nil, "Unlisted target rejected")
check(try picker.select(.pdf, droppedURLs: [photo]) == nil, "Changed drag payload rejected")
let requests = try picker.select(.pdf, droppedURLs: [doc])
check(requests?.count == 1 && requests?.first?.source == doc && requests?.first?.targetFormat == .pdf, "Selection captures source and target")
check(try picker.select(.pdf, droppedURLs: [doc]) == nil, "Repeated drop cannot dispatch twice")
var mixed = PickerSession(sources: [doc, photo])
check(try mixed.select(.pdf, droppedURLs: [photo, doc])?.count == 2, "Mixed selection accepts reordered payload")
let wheel = RadialGeometry(center: .zero, innerRadius: 40, outerRadius: 100, count: 4)
check(wheel.segment(at: CGPoint(x: 0, y: 70)) == 0, "Top segment")
check(wheel.segment(at: CGPoint(x: 70, y: 0)) == 1, "Right segment")
check(wheel.segment(at: CGPoint(x: 0, y: -70)) == 2, "Bottom segment")
check(wheel.segment(at: CGPoint(x: -70, y: 0)) == 3, "Left segment")
check(wheel.segment(at: .zero) == nil, "Center is not a drop target")
check(wheel.segment(at: CGPoint(x: 0, y: 101)) == nil, "Outside ring rejects drop")
check(wheel.segment(at: CGPoint(x: 50, y: 50)) == nil, "Segment gaps reject drop")
let emptyWheel = RadialGeometry(center: .zero, innerRadius: 40, outerRadius: 100, count: 0)
check(emptyWheel.segment(at: CGPoint(x: 0, y: 70)) == nil, "Empty wheel safe")
let singleWheel = RadialGeometry(center: .zero, innerRadius: 40, outerRadius: 100, count: 1)
check(singleWheel.segment(at: CGPoint(x: 70, y: 0)) == 0, "Single segment supported")
for screen in [CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: -900, width: 1440, height: 900), CGRect(x: 0, y: 0, width: 240, height: 200)] {
    for point in [CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.maxX, y: screen.maxY), CGPoint(x: screen.midX, y: screen.midY)] {
        let frame = RadialGeometry.frame(near: point, in: screen)
        check(screen.contains(frame), "Picker stays on selected screen including small/negative-origin displays")
    }
}
print("PASS: contextual choices, exact-once request capture, radial hit testing, center/gap rejection, and display placement")

actor ConcurrencyProbe {
    var current = 0
    var maximum = 0
    func enter() { current += 1; maximum = max(maximum, current) }
    func leave() { current -= 1 }
}
struct FixtureEngine: ConversionEngine {
    let identifier = "fixture-only"
    var availability: EngineAvailability = .ready
    var delay: Duration = .milliseconds(20)
    var empty = false
    var invalid = false
    let probe: ConcurrencyProbe
    func supports(source: FileFormat, target: FileFormat) -> Bool { source == .txt && target == .html }
    func convert(_ request: ConversionRequest, to stagingURL: URL) async throws {
        await probe.enter()
        do {
            try await Task.sleep(for: delay)
            try Task.checkCancellation()
            try Data((empty ? "" : "<html>fixture</html>").utf8).write(to: stagingURL)
            await probe.leave()
        } catch { await probe.leave(); throw error }
    }
    func validate(output: URL, format: FileFormat) throws {
        guard !invalid, try String(contentsOf: output, encoding: .utf8) == "<html>fixture</html>" else { throw WorkerError.invalidOutput }
    }
}
let fm = FileManager.default
let sandbox = fm.temporaryDirectory.appendingPathComponent("lorikeet-checks-\(UUID())", isDirectory: true)
try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: sandbox) }
let input = sandbox.appendingPathComponent("source with spaces.txt")
try Data("original".utf8).write(to: input)
let probe = ConcurrencyProbe()
let fixture = FixtureEngine(probe: probe)
let registry = EngineRegistry(engines: [fixture])
check(registry.targets(for: [input]) == [.html], "Only ready engine-backed routes offered")
check(EngineRegistry().targets(for: [input]).isEmpty, "No engines means no advertised conversions")
let unavailable = EngineRegistry(engines: [FixtureEngine(availability: .unavailable("Missing tool"), probe: probe)])
check(unavailable.targets(for: [input]).isEmpty, "Unavailable engine hidden")
check(unavailable.unavailableReasons(source: .txt, target: .html).count == 1, "Missing engine reason retained")
let existing = sandbox.appendingPathComponent("source with spaces.html")
try Data("existing".utf8).write(to: existing)
let queue = ConversionQueue(registry: registry, concurrency: 2)
let jobs = try (0..<5).map { _ in try ConversionRequest(source: input, targetFormat: .html) }
await queue.submit(jobs + [jobs[0]])
await queue.waitUntilIdle()
var outputs = Set<URL>()
for job in jobs {
    guard case .succeeded(let url) = await queue.state(for: job.id) else { fatalError("Expected fixture success") }
    check(outputs.insert(url).inserted, "Overlapping jobs reserve distinct outputs")
}
let peak = await probe.maximum
check(peak == 2, "Queue runs concurrently within configured bound")
check(try String(contentsOf: input, encoding: .utf8) == "original", "Original preserved")
check(try String(contentsOf: existing, encoding: .utf8) == "existing", "Existing output preserved")
let cancelQueue = ConversionQueue(registry: EngineRegistry(engines: [FixtureEngine(delay: .seconds(5), probe: probe)]), concurrency: 1)
let cancelled = try (0..<2).map { _ in try ConversionRequest(source: input, targetFormat: .html) }
await cancelQueue.submit(cancelled)
for _ in 0..<100 {
    if await probe.current > 0 { break }
    try await Task.sleep(for: .milliseconds(2))
}
check(await probe.current > 0, "Fixture started before running-job cancellation")
await cancelQueue.cancel(cancelled[1].id)
await cancelQueue.cancel(cancelled[0].id)
await cancelQueue.waitUntilIdle()
for job in cancelled { check(await cancelQueue.state(for: job.id) == .cancelled, "Queued and active cancellation") }
for bad in [FixtureEngine(empty: true, probe: probe), FixtureEngine(invalid: true, probe: probe), FixtureEngine(delay: .seconds(5), probe: probe)] {
    let q = ConversionQueue(registry: EngineRegistry(engines: [bad]), timeout: .milliseconds(100))
    let job = try ConversionRequest(source: input, targetFormat: .html)
    await q.submit([job]); await q.waitUntilIdle()
    guard case .failed = await q.state(for: job.id) else { fatalError("Expected validation/timeout failure") }
}
let missing = try ConversionRequest(source: input, targetFormat: .pdf)
let missingInput = try ConversionRequest(source: sandbox.appendingPathComponent("missing.txt"), targetFormat: .html)
await queue.submit([missing, missingInput])
await queue.waitUntilIdle()
guard case .failed = await queue.state(for: missingInput.id) else { fatalError("Missing source must fail") }
guard case .failed = await queue.state(for: missing.id) else { fatalError("Missing route must fail") }
check(try fm.contentsOfDirectory(atPath: sandbox.path).allSatisfy { !$0.hasPrefix(".openlorikeet-") }, "Workspaces cleaned after success/failure/cancellation")
let literal = "spaces ' and $(literal) ; untouched"
let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", literal], directory: sandbox)
check(result.stdout == literal, "Process arguments passed literally without shell expansion")
do {
    _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], directory: sandbox, timeout: .milliseconds(60))
    fatalError("Expected process timeout")
} catch WorkerError.timedOut {}
check(try fm.contentsOfDirectory(atPath: sandbox.path).allSatisfy { !$0.hasPrefix("process-") }, "Process logs cleaned")
print("PASS: engine readiness, bounded queue, exact-once jobs, collision-safe outputs, validation, cancellation, timeout, cleanup, and literal process arguments")

let stopped = ConversionQueue(registry: EngineRegistry(engines: [FixtureEngine(delay: .seconds(5), probe: probe)]), concurrency: 1)
let stopJobs = try (0..<3).map { _ in try ConversionRequest(source: input, targetFormat: .html) }
await stopped.submit(stopJobs); await stopped.cancelAll(); await stopped.waitUntilIdle()
for job in stopJobs { check(await stopped.state(for: job.id) == .cancelled, "Shutdown cancels all jobs") }
let processTask = Task {
    try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], directory: sandbox)
}
try await Task.sleep(for: .milliseconds(50))
processTask.cancel()
do { _ = try await processTask.value; fatalError("Expected cancelled process") } catch is CancellationError {}
do {
    _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], directory: sandbox)
    fatalError("Expected nonzero process failure")
} catch ProcessFailure.failed(let code, _) { check(code != 0, "Nonzero exit retained") }
print("PASS: in-flight cancellation, shutdown drain, process cancellation, and nonzero exit errors")

try await checkDocumentRoutes()
try await checkImageRoutes()
try await checkTableRoutes()
try await checkPDFRoutes()
try await checkTechnicalRoutes()
try await checkCompression()
