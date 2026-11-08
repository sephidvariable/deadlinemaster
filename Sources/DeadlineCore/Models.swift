import Foundation

public enum ImportFileTypes {
    public static let audio = ["wav", "wave", "aif", "aiff", "aifc", "flac", "mp3", "ogg", "oga", "opus", "m4a", "aac", "caf", "wma"]
    public static let documents = ["txt", "text", "md", "markdown", "rtf", "rtfd", "doc", "docx", "pdf", "pages", "odt"]
    public static func supports(_ url: URL) -> Bool {
        (audio + documents).contains(url.pathExtension.lowercased())
    }
    public static func isDocumentPackage(_ url: URL) -> Bool {
        ["pages", "rtfd"].contains(url.pathExtension.lowercased())
    }
}

public struct ProjectAsset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var storedName: String
    public var byteCount: Int64
    public var importedAt: Date
    public var isDirectory: Bool?
    public var isReference: Bool?
    public var originalPath: String?
    public var sourceRelativePath: String?
    public var sourceIdentity: String?
    public var isAudio: Bool {
        if isDirectory == true { return false }
        return ImportFileTypes.audio.contains(URL(fileURLWithPath: name).pathExtension.lowercased())
    }
    public init(id: UUID = UUID(), name: String, storedName: String, byteCount: Int64) {
        self.id = id; self.name = name; self.storedName = storedName
        self.byteCount = byteCount; self.importedAt = Date()
    }
}

public struct MusicProject: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var artist: String
    public var notes: String
    public var createdAt: Date
    public var spotlightAssetID: UUID?
    public var premasterAssetID: UUID?
    public var sourceFolderPath: String?
    public var assets: [ProjectAsset]
    /// Use the filename, not its parent folders, when choosing a final master.
    public mutating func selectAutomaticMaster() {
        if spotlightAssetID == nil { spotlightAssetID = automaticAudio(containing: "master") }
        selectAutomaticPremaster()
    }
    public mutating func selectAutomaticPremaster() {
        if premasterAssetID == nil { premasterAssetID = automaticAudio(containing: "mix") }
    }
    private func automaticAudio(containing keyword: String) -> UUID? {
        assets.filter {
            $0.isAudio && URL(fileURLWithPath: $0.name).lastPathComponent.range(of: keyword, options: .caseInsensitive) != nil
        }.sorted {
            let left = URL(fileURLWithPath: $0.name).lastPathComponent
            let right = URL(fileURLWithPath: $1.name).lastPathComponent
            if left.count != right.count { return left.count < right.count }
            if left.lowercased() != right.lowercased() { return left.lowercased() < right.lowercased() }
            return $0.name < $1.name
        }.first?.id
    }
    public init(id: UUID = UUID(), name: String, artist: String = "") {
        self.id = id; self.name = name; self.artist = artist
        notes = ""; createdAt = Date(); assets = []
    }
}

public struct DeliverySpec: Equatable, Sendable {
    public var sampleRate: Double = 48_000
    public var bitDepth: Int = 24
    public var channels: Int = 2
    public var artist: String = ""
    public var title: String = ""
    public init() {}
    public func validate() throws {
        guard [44_100.0, 48_000, 96_000, 192_000].contains(sampleRate),
              [16, 24, 32].contains(bitDepth), [1, 2].contains(channels) else {
            throw StudioError.message("Choose 44.1, 48, 96, or 192 kHz; 16/24-bit integer or 32-bit float; and mono or stereo.")
        }
    }
}

public enum StudioError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
