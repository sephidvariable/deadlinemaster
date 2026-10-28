import Foundation

/// Actor serializes disk access. JSON is committed atomically; imported originals are copied.
public actor ProjectRepository {
    public let root: URL
    private let fm = FileManager.default
    public init(root: URL) { self.root = root }
    private var index: URL { root.appendingPathComponent("library.json") }
    private struct Library: Codable { var schemaVersion = 1; var projects: [MusicProject] }

    public func load() throws -> [MusicProject] {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard fm.fileExists(atPath: index.path) else { return [] }
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: index))
        guard library.schemaVersion == 1 else { throw StudioError.message("This library was created by a newer app. It has not been changed.") }
        return library.projects
    }
    public func save(_ projects: [MusicProject]) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Library(projects: projects)).write(to: index, options: .atomic)
    }
    public func importFile(_ source: URL, projectID: UUID) throws -> ProjectAsset {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw StudioError.message("Import regular files. Package-based DAW sessions should be zipped first.") }
        let folder = root.appendingPathComponent("Files").appendingPathComponent(projectID.uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let storedName = UUID().uuidString + "_" + source.lastPathComponent
        try fm.copyItem(at: source, to: folder.appendingPathComponent(storedName))
        return ProjectAsset(name: source.lastPathComponent, storedName: storedName, byteCount: Int64(values.fileSize ?? 0))
    }
    public nonisolated func fileURL(_ asset: ProjectAsset, projectID: UUID) -> URL {
        root.appendingPathComponent("Files").appendingPathComponent(projectID.uuidString).appendingPathComponent(asset.storedName)
    }
}
