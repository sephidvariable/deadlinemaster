import Foundation

/// Actor serializes disk access. JSON is committed atomically; new imports are symbolic links to originals.
public actor ProjectRepository {
    public let root: URL
    private let fm = FileManager.default
    public init(root: URL) { self.root = root }
    private var index: URL { root.appendingPathComponent("library.json") }
    private struct Library: Codable { var schemaVersion = 2; var projects: [MusicProject] }

    public func load() throws -> [MusicProject] {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard fm.fileExists(atPath: index.path) else { return [] }
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: index))
        guard [1, 2].contains(library.schemaVersion) else { throw StudioError.message("This library was created by a newer app. It has not been changed.") }
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
        let folder = try referenceFolder(projectID)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let storedName = UUID().uuidString + "_" + source.lastPathComponent
        try fm.createSymbolicLink(at: folder.appendingPathComponent(storedName), withDestinationURL: source.resolvingSymlinksInPath())
        var asset = ProjectAsset(name: source.lastPathComponent, storedName: storedName, byteCount: Int64(values.fileSize ?? 0))
        asset.isReference = true
        return asset
    }

    /// Prepare a complete shortcut tree before committing the library entry.
    public func createFromFolder(_ source: URL, project: MusicProject, existing: [MusicProject]) throws -> MusicProject {
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let library = root.resolvingSymlinksInPath().standardizedFileURL
        guard source.path != library.path,
              !library.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(library.path + "/") else {
            throw StudioError.message("Choose a source folder outside the Deadline Master library.")
        }
        let destination = try referenceFolder(project.id)
        guard !fm.fileExists(atPath: destination.path) else { throw StudioError.message("This project folder already exists.") }
        var result = project
        result.sourceFolderPath = source.path
        result.assets = try folderAssets(source, previous: [])
        result.selectAutomaticMaster()
        do {
            try writeShortcutTree(result.assets, source: source, destination: destination)
            try save([result] + existing)
            return result
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    /// Reconcile a complete successful scan, leaving the old tree intact on failure.
    public func refreshProject(_ id: UUID, existing: [MusicProject]) throws -> [MusicProject] {
        guard let index = existing.firstIndex(where: { $0.id == id }),
              let path = existing[index].sourceFolderPath else { return existing }
        let old = existing[index]
        let source = URL(fileURLWithPath: path)
        var updated = old
        let scanned = try folderAssets(source, previous: old.assets)
        let manual = old.assets.filter { $0.sourceRelativePath == nil }
        updated.assets = scanned + manual
        if !updated.assets.contains(where: { $0.id == updated.spotlightAssetID && $0.isAudio }) {
            updated.spotlightAssetID = nil
        }
        // Do not repin an intentionally cleared Spotlight on every unchanged scan.
        if updated.assets != old.assets { updated.selectAutomaticMaster() }
        guard updated != old else { return existing }
        try Task.checkCancellation()
        let destination = try referenceFolder(id)
        let exists = fm.fileExists(atPath: destination.path)
        if exists { try validateShortcutTree(destination) }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".refresh-" + UUID().uuidString)
        let backup = destination.deletingLastPathComponent().appendingPathComponent(".previous-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        try writeShortcutTree(scanned, source: source, destination: staging)
        // Manually added links outside the watched folder remain independent.
        for asset in manual where asset.isReference == true {
            let oldLink = destination.appendingPathComponent(asset.storedName)
            let target = staging.appendingPathComponent(asset.storedName)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: oldLink, to: target) // copies the symlink itself, never its target
        }
        if exists { try fm.moveItem(at: destination, to: backup) }
        var next = existing
        next[index] = updated
        do {
            try fm.moveItem(at: staging, to: destination)
            try save(next)
        } catch {
            try? fm.removeItem(at: destination)
            if exists { try fm.moveItem(at: backup, to: destination) }
            throw error
        }
        if exists { try? fm.removeItem(at: backup) }
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
                asset.isReference = true
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

    private func writeShortcutTree(_ assets: [ProjectAsset], source: URL, destination: URL) throws {
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for asset in assets {
            let target = destination.appendingPathComponent(asset.storedName)
            if asset.isDirectory == true { try fm.createDirectory(at: target, withIntermediateDirectories: true) }
            else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.createSymbolicLink(at: target, withDestinationURL: source.appendingPathComponent(asset.name))
            }
        }
    }

    private func validateShortcutTree(_ directory: URL) throws {
        for child in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let type = try fm.attributesOfItem(atPath: child.path)[.type] as? FileAttributeType
            if type == .typeSymbolicLink { continue }
            if type == .typeDirectory { try validateShortcutTree(child) }
            else { throw StudioError.message("Unexpected real files were found in the shortcut folder. No changes were made.") }
        }
    }

    private func referenceFolder(_ id: UUID) throws -> URL {
        let base = root.resolvingSymlinksInPath().appendingPathComponent("References")
        let folder = base.appendingPathComponent(id.uuidString)
        // Never create or remove entries through a replaced management directory.
        for url in [base, folder] {
            if (try? fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                throw StudioError.message("The library reference directory was replaced by a shortcut. No changes were made.")
            }
        }
        return folder
    }

    /// Delete only app-managed links and containers; never traverse link targets.
    /// Legacy copies under Files are deliberately retained.
    public func deleteProject(_ id: UUID, existing: [MusicProject]) throws -> String? {
        let folder = try referenceFolder(id)
        let exists = fm.fileExists(atPath: folder.path)
        if exists { try validateShortcutTree(folder) }
        let staged = folder.deletingLastPathComponent().appendingPathComponent(".deleting-" + UUID().uuidString)
        if exists { try fm.moveItem(at: folder, to: staged) }
        do { try save(existing.filter { $0.id != id }) }
        catch {
            if exists { try fm.moveItem(at: staged, to: folder) }
            throw error
        }
        if exists {
            do { try fm.removeItem(at: staged) }
            catch { return "Project deleted. Some shortcut cleanup remains at " + staged.path }
        }
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
        root.appendingPathComponent(asset.isReference == true ? "References" : "Files").appendingPathComponent(projectID.uuidString).appendingPathComponent(asset.storedName).resolvingSymlinksInPath()
    }
}
