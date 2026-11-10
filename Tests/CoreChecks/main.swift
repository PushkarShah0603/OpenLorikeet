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
