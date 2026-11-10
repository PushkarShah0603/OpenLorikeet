import Foundation
import ConversionCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
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
