import Foundation

/// Actor serializes disk access. JSON is committed atomically; original files are read only; only the library index is written.
public actor ProjectRepository {
    public let root: URL
    private let fm = FileManager.default
    public init(root: URL) { self.root = root }
    private var index: URL { root.appendingPathComponent("library.json") }
    private struct Library: Codable { var schemaVersion = 3; var projects: [MusicProject] }

    public func load() throws -> [MusicProject] {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard fm.fileExists(atPath: index.path) else { return [] }
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: index))
        guard [1, 2, 3].contains(library.schemaVersion) else { throw StudioError.message("This library was created by a newer app. It has not been changed.") }
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
        var asset = ProjectAsset(name: source.lastPathComponent, storedName: source.lastPathComponent, byteCount: Int64(values.fileSize ?? 0))
        asset.originalPath = source.resolvingSymlinksInPath().path
        return asset
    }

    /// Read a source inventory before committing the library entry.
    public func createFromFolder(_ source: URL, project: MusicProject, existing: [MusicProject]) throws -> MusicProject {
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let library = root.resolvingSymlinksInPath().standardizedFileURL
        guard source.path != library.path,
              !library.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(library.path + "/") else {
            throw StudioError.message("Choose a source folder outside the Deadline Master library.")
        }
        var result = project
        result.sourceFolderPath = source.path
        result.assets = try folderAssets(source, previous: [])
        result.selectAutomaticMaster()
        try save([result] + existing)
        return result
    }

    /// Called once at launch. A failed scan leaves the stored project untouched.
    public func refreshProject(_ id: UUID, existing: [MusicProject]) throws -> [MusicProject] {
        guard let index = existing.firstIndex(where: { $0.id == id }),
              let path = existing[index].sourceFolderPath else { return existing }
        let old = existing[index]
        var updated = old
        updated.assets = try folderAssets(URL(fileURLWithPath: path), previous: old.assets)
            + old.assets.filter { $0.sourceRelativePath == nil }
        if !updated.assets.contains(where: { $0.id == updated.spotlightAssetID && $0.isAudio }) {
            updated.spotlightAssetID = nil
        }
        if updated.assets != old.assets { updated.selectAutomaticMaster() }
        guard updated != old else { return existing }
        try Task.checkCancellation()
        var next = existing
        next[index] = updated
        try save(next)
        return next
    }

    private func folderAssets(_ source: URL, previous: [ProjectAsset]) throws -> [ProjectAsset] {
        let scan = try AbletonFolderScan.scan(source)
        var assets: [ProjectAsset] = []
        var reused = Set<UUID>()
        func visit(_ folder: URL, relative: String) throws {
            try Task.checkCancellation()
            let children = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                if scan.excludes(child, parent: folder, isDirectory: values.isDirectory == true) { continue }
                guard values.isSymbolicLink != true else {
                    throw StudioError.message("Source folder contains a symbolic link: " + child.lastPathComponent + ". Refresh was left unchanged.")
                }
                let directory = values.isDirectory == true && !ImportFileTypes.isDocumentPackage(child)
                guard directory || ImportFileTypes.supports(child) else { continue }
                guard directory || values.isRegularFile == true || ImportFileTypes.isDocumentPackage(child) else { continue }
                let path = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                let attributes = try fm.attributesOfItem(atPath: child.path)
                let identity = "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
                let candidates = previous.filter { $0.sourceRelativePath != nil && !reused.contains($0.id) }
                let match = candidates.first { $0.sourceIdentity == identity && $0.sourceRelativePath == path }
                    ?? candidates.first { $0.sourceIdentity == identity }
                    ?? candidates.first { $0.sourceRelativePath == path }
                var asset = ProjectAsset(name: path, storedName: path, byteCount: directory ? 0 : Int64(values.fileSize ?? 0))
                if let match { asset.id = match.id; asset.importedAt = match.importedAt; reused.insert(match.id) }
                asset.originalPath = child.path
                asset.isDirectory = directory ? true : nil
                asset.sourceRelativePath = path
                asset.sourceIdentity = identity
                let start = assets.count
                assets.append(asset)
                if directory {
                    try visit(child, relative: path)
                    if assets.count == start + 1 { assets.removeLast() }
                }
            }
        }
        try visit(source, relative: "")
        // A missing root/read failure must never be interpreted as an empty project.
        guard fm.fileExists(atPath: source.path) else { throw StudioError.message("Source folder is unavailable. Reconnect its drive or restore its location.") }
        return assets
    }

    /// Removing a project only changes library metadata. Never remove source files.
    public func deleteProject(_ id: UUID, existing: [MusicProject]) throws -> String? {
        try save(existing.filter { $0.id != id })
        return nil
    }

    public nonisolated func availableFileURL(_ asset: ProjectAsset, projectID: UUID) throws -> URL {
        let url = fileURL(asset, projectID: projectID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StudioError.message("File unavailable: " + asset.name + ". Restore the original location or reconnect its drive, or add the file again.")
        }
        return url
    }

    public nonisolated func fileURL(_ asset: ProjectAsset, projectID: UUID) -> URL {
        if let path = asset.originalPath { return URL(fileURLWithPath: path) }
        return root.appendingPathComponent(asset.isReference == true ? "References" : "Files").appendingPathComponent(projectID.uuidString).appendingPathComponent(asset.storedName).resolvingSymlinksInPath()
    }
}
