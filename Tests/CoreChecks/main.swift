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
