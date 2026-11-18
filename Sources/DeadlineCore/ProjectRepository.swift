import Foundation

/// Actor serializes disk access. JSON is committed atomically; original files are read only; library metadata and imported cover artwork are stored separately from original project files.
public actor ProjectRepository {
    public let root: URL
    private let fm = FileManager.default
    public init(root: URL) { self.root = root }
    private var index: URL { root.appendingPathComponent("library.json") }
    private struct Library: Codable { var schemaVersion = 4; var projects: [MusicProject]; var albums: [MusicAlbum]? = nil }

    private func readLibrary() throws -> Library {
        guard fm.fileExists(atPath: index.path) else { return Library(projects: []) }
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: index))
        guard [1, 2, 3, 4].contains(library.schemaVersion) else { throw StudioError.message("This library was created by a newer app. It has not been changed.") }
        return library
    }
    public func load() throws -> [MusicProject] {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return try readLibrary().projects
    }
    public func loadAlbums() throws -> [MusicAlbum] { try readLibrary().albums ?? [] }

    private func writeLibrary(_ library: Library) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let old = try readLibrary()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: index, options: .atomic)
        let retained = Set(library.projects.compactMap { $0.cover?.id } + (library.albums ?? []).compactMap { $0.cover?.id })
        let previous = Set(old.projects.compactMap { $0.cover?.id } + (old.albums ?? []).compactMap { $0.cover?.id })
        for id in previous.subtracting(retained) { try? fm.removeItem(at: coverDirectory(id)) }
    }
    public func save(_ projects: [MusicProject]) throws {
        var library = try readLibrary()
        library.schemaVersion = 4
        library.projects = projects
        let valid = Set(projects.map(\.id))
        library.albums = library.albums?.map { album in
            var updated = album; updated.projectIDs.removeAll { !valid.contains($0) }; return updated
        }
        try writeLibrary(library)
    }
    public func saveAlbums(_ albums: [MusicAlbum]) throws {
        var library = try readLibrary()
        let valid = Set(library.projects.map(\.id))
        guard Set(albums.map(\.id)).count == albums.count else { throw StudioError.message("Duplicate album identifiers.") }
        for album in albums {
            guard !album.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(album.projectIDs).count == album.projectIDs.count,
                  album.projectIDs.allSatisfy({ valid.contains($0) }) else {
                throw StudioError.message("Choose an album name and existing projects, without duplicate tracks.")
            }
        }
        library.schemaVersion = 4; library.albums = albums
        try writeLibrary(library)
    }
    private func coverDirectory(_ id: UUID) -> URL { root.appendingPathComponent("Covers", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true) }
    public nonisolated func coverThumbnailURL(_ cover: CoverArtwork) -> URL {
        root.appendingPathComponent("Covers").appendingPathComponent(cover.id.uuidString).appendingPathComponent("preview.png")
    }
    public func setCover(from source: URL?, for owner: CoverOwner) throws {
        var library = try readLibrary()
        switch owner {
        case .project(let id): guard library.projects.contains(where: { $0.id == id }) else { throw StudioError.message("Project no longer exists.") }
        case .album(let id): guard (library.albums ?? []).contains(where: { $0.id == id }) else { throw StudioError.message("Album no longer exists.") }
        }
        var cover: CoverArtwork?
        var created: URL?
        do {
            if let source {
                let id = UUID(); let directory = coverDirectory(id)
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                created = directory
                let original = directory.appendingPathComponent("original").appendingPathExtension(source.pathExtension)
                try fm.copyItem(at: source, to: original)
                let size = try CoverImage.dimensions(at: original)
                try CoverImage.writeThumbnail(from: original, to: directory.appendingPathComponent("preview.png"))
                cover = CoverArtwork(id: id, width: size.width, height: size.height)
            }
            switch owner {
            case .project(let id): library.projects[library.projects.firstIndex { $0.id == id }!].cover = cover
            case .album(let id):
                if let index = library.albums?.firstIndex(where: { $0.id == id }) { library.albums?[index].cover = cover }
            }
            try writeLibrary(library)
        } catch {
            if let created { try? fm.removeItem(at: created) }
            throw error
        }
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
        let source = try validatedSource(source)
        let result = try projectFromFolder(source, project: project)
        try save([result] + existing)
        return result
    }

    private func validatedSource(_ source: URL) throws -> URL {
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let library = root.resolvingSymlinksInPath().standardizedFileURL
        guard source.path != library.path,
              !library.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(library.path + "/") else {
            throw StudioError.message("Choose a source folder outside the Deadline Master library.")
        }
        guard try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw StudioError.message("Choose a project folder.")
        }
        return source
    }

    private func projectFromFolder(_ source: URL, project: MusicProject) throws -> MusicProject {
        var result = project
        result.sourceFolderPath = source.path
        result.assets = try folderAssets(source, previous: [])
        result.selectAutomaticMaster()
        return result
    }

    /// Stage every successful inventory, then commit once. Cancellation saves nothing.
    /// Recheck duplicates against the on-disk library, including projects added since discovery.
    public func createBatchFromFolders(_ choices: [ProjectFolderChoice], artist: String) throws -> BatchProjectImportResult {
        var library = try readLibrary()
        var known = Set(library.projects.compactMap { project -> String? in
            project.sourceFolderPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }
        })
        var result = BatchProjectImportResult()
        for choice in choices {
            try Task.checkCancellation()
            do {
                let source = try validatedSource(choice.folder)
                guard !known.contains(source.path) else {
                    result.skipped.append(.init(folder: choice.folder, message: "Already in your library.")); continue
                }
                let name = choice.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw StudioError.message("Enter a project name.") }
                let project = try projectFromFolder(source, project: MusicProject(name: name, artist: artist))
                result.added.append(project)
                known.insert(source.path)
            } catch is CancellationError { throw CancellationError() }
            catch { result.failed.append(.init(folder: choice.folder, message: error.localizedDescription)) }
        }
        try Task.checkCancellation()
        if !result.added.isEmpty {
            library.schemaVersion = 4
            library.projects = result.added + library.projects
            try writeLibrary(library)
        }
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
        if !updated.assets.contains(where: { $0.id == updated.premasterAssetID && $0.isAudio }) { updated.premasterAssetID = nil }
        if updated.assets != old.assets { updated.selectAutomaticMaster() }
        else if old.premasterAssetID == nil { updated.selectAutomaticPremaster() }
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
