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
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
        guard ImportFileTypes.supports(source), values.isRegularFile == true || (values.isDirectory == true && ImportFileTypes.isDocumentPackage(source)) else { throw StudioError.message("Choose an audio or document file.") }
        let folder = root.appendingPathComponent("Files").appendingPathComponent(projectID.uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let storedName = UUID().uuidString + "_" + source.lastPathComponent
        try fm.copyItem(at: source, to: folder.appendingPathComponent(storedName))
        return ProjectAsset(name: source.lastPathComponent, storedName: storedName, byteCount: Int64(values.fileSize ?? 0))
    }

    /// Prepare a complete folder copy before committing the library entry.
    public func createFromFolder(_ source: URL, project: MusicProject, existing: [MusicProject]) throws -> MusicProject {
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let library = root.resolvingSymlinksInPath().standardizedFileURL
        guard source.path != library.path,
              !library.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(library.path + "/") else {
            throw StudioError.message("Choose a source folder outside the Deadline Master library.")
        }
        let destination = root.appendingPathComponent("Files").appendingPathComponent(project.id.uuidString)
        guard !fm.fileExists(atPath: destination.path) else { throw StudioError.message("This project folder already exists.") }
        let scan = try AbletonFolderScan.scan(source)
        var result = project
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            func visit(_ folder: URL, relative: String) throws {
                let children = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                    if scan.excludes(child, parent: folder, isDirectory: values.isDirectory == true) { continue }
                    guard values.isSymbolicLink != true else {
                        throw StudioError.message("The folder contains a symbolic link: \(child.lastPathComponent). Choose a folder containing regular files and folders.")
                    }
                    let path = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                    let target = destination.appendingPathComponent(path)
                    var asset = ProjectAsset(name: path, storedName: path, byteCount: Int64(values.fileSize ?? 0))
                    if values.isDirectory == true && ImportFileTypes.isDocumentPackage(child) {
                        try fm.copyItem(at: child, to: target)
                        result.assets.append(asset)
                    } else if values.isDirectory == true {
                        asset.isDirectory = true
                        asset.byteCount = 0
                        try fm.createDirectory(at: target, withIntermediateDirectories: true)
                        let start = result.assets.count
                        result.assets.append(asset)
                        try visit(child, relative: path)
                        if result.assets.count == start + 1 {
                            result.assets.removeLast()
                            try fm.removeItem(at: target)
                        }
                    } else if values.isRegularFile == true {
                        guard ImportFileTypes.supports(child) else { continue }
                        try fm.copyItem(at: child, to: target)
                        result.assets.append(asset)
                    } else {
                        throw StudioError.message("Unsupported file: \(path)")
                    }
                }
            }
            try visit(source, relative: "")
            result.selectAutomaticMaster()
            try save([result] + existing)
            return result
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }
    public nonisolated func fileURL(_ asset: ProjectAsset, projectID: UUID) -> URL {
        root.appendingPathComponent("Files").appendingPathComponent(projectID.uuidString).appendingPathComponent(asset.storedName)
    }
}
