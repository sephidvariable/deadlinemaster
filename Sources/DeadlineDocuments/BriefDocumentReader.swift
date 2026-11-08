import AppKit
import PDFKit
import Vision

public struct BriefDocumentText: Sendable {
    public let text: String
    public let notes: String
}

public enum BriefDocumentError: LocalizedError {
    case passwordRequired
    case unreadable(String)
    public var errorDescription: String? {
        switch self {
        case .passwordRequired: "This PDF is locked. Enter its password to read it."
        case .unreadable(let reason): reason
        }
    }
}

/// Local-only extraction. Call off the main actor; imported text must be reviewed.
public enum BriefDocumentReader {
    public static let extensions = ["txt", "doc", "docx", "docm", "dot", "dotx", "dotm", "rtf", "rtfd", "odt", "pages", "template", "pdf"]

    public static func read(_ url: URL, password: String? = nil) throws -> BriefDocumentText {
        let ext = url.pathExtension.lowercased()
        let result: BriefDocumentText
        switch ext {
        case "txt":
            var encoding = String.Encoding.utf8
            result = BriefDocumentText(text: try String(contentsOf: url, usedEncoding: &encoding), notes: "Text imported.")
        case "pdf": result = try pdf(url, password: password)
        case "pages", "template": result = try pages(url)
        case "doc", "dot", "docx", "docm", "dotx", "dotm", "rtf", "rtfd", "odt":
            let type: NSAttributedString.DocumentType
            switch ext {
            case "doc", "dot": type = .docFormat
            case "docx", "docm", "dotx", "dotm": type = .officeOpenXML
            case "rtf": type = .rtf
            case "rtfd": type = .rtfd
            default: type = .openDocument
            }
            do {
                let text = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil).string
                result = BriefDocumentText(text: text, notes: "Document text imported. Macros are not executed. Check tables, headers and line breaks.")
            } catch {
                throw BriefDocumentError.unreadable("Could not read this Word/RTF document. It may be damaged, encrypted or unsupported by macOS. Export an unlocked DOCX or PDF and try again.")
            }
        default: throw BriefDocumentError.unreadable("Choose a TXT, Word, RTF, ODT, Pages or PDF brief.")
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw BriefDocumentError.unreadable("No readable text was found. Try exporting the brief as text or a clearer PDF.") }
        return BriefDocumentText(text: text, notes: result.notes + " Review the text and arrange one delivery version per line before adding versions.")
    }

    private static func pdf(_ url: URL, password: String?) throws -> BriefDocumentText {
        guard let document = PDFDocument(url: url) else { throw BriefDocumentError.unreadable("This PDF could not be opened. It may be damaged or unsupported.") }
        if document.isLocked {
            guard let password, document.unlock(withPassword: password) else { throw BriefDocumentError.passwordRequired }
        }
        guard document.allowsCopying else { throw BriefDocumentError.unreadable("This PDF does not allow text extraction. Ask for an unrestricted copy.") }
        guard document.pageCount > 0, document.pageCount <= 300 else { throw BriefDocumentError.unreadable("Choose a PDF brief with 1–300 pages.") }
        var chunks: [String] = []
        var ocrPages = 0
        var emptyPages = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw BriefDocumentError.unreadable("Could not read PDF page \(index + 1).") }
            let embedded = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !embedded.isEmpty { chunks.append(embedded); continue }
            let text = try autoreleasepool { try recognize(page) }
            ocrPages += 1
            if text.isEmpty { emptyPages += 1 }
            chunks.append(text)
        }
        let notes = "Read \(document.pageCount) PDF pages; \(ocrPages) used offline OCR.\(emptyPages > 0 ? " No text found on \(emptyPages) pages." : "") Check reading order and OCR numbers carefully. Embedded attachments are not imported."
        return BriefDocumentText(text: chunks.joined(separator: "\n\n"), notes: notes)
    }

    private static func recognize(_ page: PDFPage) throws -> String {
        // Bound memory while rendering enough detail for ordinary scanned briefs.
        let image = page.thumbnail(of: NSSize(width: 2400, height: 2400), for: .mediaBox)
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw BriefDocumentError.unreadable("Could not render a scanned PDF page.")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = false // Preserve filenames and technical numbers.
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func pages(_ url: URL) throws -> BriefDocumentText {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") != nil else {
            throw BriefDocumentError.unreadable("Reading Pages briefs requires Apple Pages on this Mac. Alternatively, export the brief as DOCX or PDF.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeadlineBrief-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        // Pages may update a document on opening. Only ever give it a disposable copy.
        let copy = root.appendingPathComponent("Brief." + url.pathExtension)
        try FileManager.default.copyItem(at: url, to: copy)
        let output = root.appendingPathComponent("Brief.pdf")
        let script = """
        on run argv
            set inputFile to POSIX file (item 1 of argv)
            set outputFile to POSIX file (item 2 of argv)
            set openedDocument to missing value
            with timeout of 120 seconds
                tell application id "com.apple.iWork.Pages"
                    try
                        set openedDocument to open inputFile
                        export openedDocument to outputFile as PDF
                        close openedDocument saving no
                    on error messageText number errorNumber
                        if openedDocument is not missing value then
                            try
                                close openedDocument saving no
                            end try
                        end if
                        error messageText number errorNumber
                    end try
                end tell
            end timeout
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, copy.path, output.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BriefDocumentError.unreadable("Pages could not read this brief. Allow Deadline Master to control Pages in System Settings → Privacy & Security → Automation, unlock password-protected documents in Pages, or export an unlocked PDF/DOCX. The original was not modified.")
        }
        let result = try pdf(output, password: nil)
        return BriefDocumentText(text: result.text, notes: "Read a temporary copy using Apple Pages. " + result.notes)
    }
}
