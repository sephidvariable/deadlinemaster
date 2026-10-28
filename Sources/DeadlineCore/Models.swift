import Foundation

public struct ProjectAsset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var storedName: String
    public var byteCount: Int64
    public var importedAt: Date
    public var isAudio: Bool {
        ["wav", "wave", "aif", "aiff", "mp3", "m4a", "aac", "caf", "flac"].contains(URL(fileURLWithPath: name).pathExtension.lowercased())
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
    public var assets: [ProjectAsset]
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
        guard [44_100.0, 48_000, 96_000].contains(sampleRate),
              [16, 24].contains(bitDepth), [1, 2].contains(channels) else {
            throw StudioError.message("Choose 44.1, 48, or 96 kHz; 16 or 24-bit; and mono or stereo.")
        }
    }
}

public enum StudioError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
