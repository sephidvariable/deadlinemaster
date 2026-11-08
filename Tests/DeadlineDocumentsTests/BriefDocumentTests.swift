import AppKit
import CoreText
import PDFKit
import Testing
@testable import DeadlineDocuments

private let briefText = "master.wav; 24-bit; 48 kHz; Stereo"
private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

@Test func importsWordAndRichTextWithoutChangingOriginals() throws {
    let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
    let text = NSAttributedString(string: briefText)
    let formats: [(String, NSAttributedString.DocumentType)] = [("doc", .docFormat), ("docx", .officeOpenXML), ("rtf", .rtf), ("odt", .openDocument)]
    for (ext, type) in formats {
        let url = root.appendingPathComponent("brief." + ext)
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: type])
        try data.write(to: url)
        let result = try BriefDocumentReader.read(url)
        #expect(result.text.contains(briefText))
        #expect(try Data(contentsOf: url) == data)
    }
}

@Test func importsUTF16AndRejectsUnreadableDocuments() throws {
    let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("brief.txt")
    try briefText.write(to: url, atomically: true, encoding: .utf16)
    #expect(try BriefDocumentReader.read(url).text == briefText)
    let broken = root.appendingPathComponent("broken.pdf")
    try Data("not a PDF".utf8).write(to: broken)
    #expect(throws: (any Error).self) { try BriefDocumentReader.read(broken) }
    try "  \n ".write(to: url, atomically: true, encoding: .utf8)
    #expect(throws: (any Error).self) { try BriefDocumentReader.read(url) }
}

private func drawBrief(in context: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("Helvetica" as CFString, 22, nil)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: briefText, attributes: attributes))
    context.textPosition = CGPoint(x: 30, y: 700)
    CTLineDraw(line, context)
}
private func writePDF(_ url: URL, scanned: Bool) throws {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    if scanned {
        let bitmap = try #require(CGContext(data: nil, width: 1224, height: 1584, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 1224, height: 1584))
        bitmap.scaleBy(x: 2, y: 2); drawBrief(in: bitmap)
        context.draw(try #require(bitmap.makeImage()), in: box)
    } else { drawBrief(in: context) }
    context.endPDFPage(); context.closePDF()
}

@Test func readsDigitalAndScannedPDFsLocally() throws {
    let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
    for scanned in [false, true] {
        let url = root.appendingPathComponent("brief-\(scanned).pdf")
        try writePDF(url, scanned: scanned)
        let original = try Data(contentsOf: url)
        let result = try BriefDocumentReader.read(url)
        #expect(result.text.contains("24-bit"))
        #expect(result.text.contains("48 kHz"))
        #expect(result.notes.contains(scanned ? "1 used offline OCR" : "0 used offline OCR"))
        #expect(try Data(contentsOf: url) == original)
    }
}

@Test func lockedPDFRequiresCorrectPassword() throws {
    let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.pdf"); try writePDF(source, scanned: false)
    let document = try #require(PDFDocument(url: source))
    let locked = root.appendingPathComponent("locked.pdf")
    #expect(document.write(to: locked, withOptions: [.userPasswordOption: "test-password", .ownerPasswordOption: "owner-password"]))
    #expect(throws: (any Error).self) { try BriefDocumentReader.read(locked) }
    #expect(throws: (any Error).self) { try BriefDocumentReader.read(locked, password: "wrong") }
    #expect(try BriefDocumentReader.read(locked, password: "test-password").text.contains("24-bit"))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["DEADLINE_TEST_PAGES"] == "1"))
func importsCurrentAndLegacyPagesFromDisposableCopies() throws {
    let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
    let current = root.appendingPathComponent("current.pages")
    let legacy = root.appendingPathComponent("legacy.pages")
    let script = """
    on run argv
        tell application id "com.apple.iWork.Pages"
            set d to make new document
            try
                set body text of d to "master.wav; 24-bit; 48 kHz; Stereo"
                save d in POSIX file (item 1 of argv)
                export d to POSIX file (item 2 of argv) as Pages 09
                close d saving no
            on error messageText number errorNumber
                close d saving no
                error messageText number errorNumber
            end try
        end tell
    end run
    """
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script, current.path, legacy.path]
    try process.run(); process.waitUntilExit()
    try #require(process.terminationStatus == 0)
    for source in [current, legacy] {
        let backup = root.appendingPathComponent("backup-" + source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: backup)
        #expect(try BriefDocumentReader.read(source).text.contains("24-bit"))
        #expect(FileManager.default.contentsEqual(atPath: source.path, andPath: backup.path))
    }
}
