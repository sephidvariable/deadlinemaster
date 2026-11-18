import Foundation

public struct ProjectFolderChoice: Identifiable, Equatable, Sendable {
    public var folder: URL
    public var name: String
    public var id: String { folder.path }
    public init(folder: URL, name: String? = nil) {
        self.folder = folder.resolvingSymlinksInPath().standardizedFileURL
        self.name = name ?? folder.lastPathComponent
    }
}

public struct FolderImportIssue: Equatable, Sendable {
    public var folder: URL
    public var message: String
    public init(folder: URL, message: String) { self.folder = folder; self.message = message }
}

public struct ProjectFolderDiscovery: Sendable {
    public var projects: [ProjectFolderChoice] = []
    public var issues: [FolderImportIssue] = []

    /// Finds actual Live project roots, not every ancestor that contains a set.
    /// Walk iteratively; do not enter links, packages, hidden folders or a project's production assets.
    public static func scan(_ root: URL, excluding excluded: [URL] = []) throws -> Self {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let excluded = excluded.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        func isExcluded(_ url: URL) -> Bool {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            return excluded.contains { path == $0.path || path.hasPrefix($0.path + "/") }
        }
        guard !isExcluded(root), try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw StudioError.message("Choose a music folder outside the Deadline Master library.")
        }
        var result = Self()
        var pending = [root]
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
        while let directory = pending.popLast() {
            try Task.checkCancellation()
            do {
                let children = try FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                var folders: [URL] = []
                var sets = 0
                for child in children {
                    try Task.checkCancellation()
                    do {
                        let values = try child.resourceValues(forKeys: keys)
                        guard values.isSymbolicLink != true else { continue }
                        if values.isDirectory == true {
                            if values.isPackage != true && !ImportFileTypes.isDocumentPackage(child) && !isExcluded(child) {
                                folders.append(child.resolvingSymlinksInPath().standardizedFileURL)
                            }
                        } else if values.isRegularFile == true && child.pathExtension.lowercased() == "als" {
                            sets += 1
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch { result.issues.append(.init(folder: child, message: error.localizedDescription)) }
                }
                let recognized = AbletonFolderScan.isProjectDirectory(setCount: sets,
                    folderNames: Set(folders.map { $0.lastPathComponent.lowercased() }))
                if recognized { result.projects.append(ProjectFolderChoice(folder: directory)) }
                pending += folders.filter {
                    !recognized || !AbletonFolderScan.productionFolders.contains($0.lastPathComponent.lowercased())
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                if directory == root { throw error }
                result.issues.append(.init(folder: directory, message: error.localizedDescription))
            }
        }
        result.projects.sort { $0.folder.path < $1.folder.path }
        result.issues.sort { $0.folder.path < $1.folder.path }
        return result
    }
}

public struct BatchProjectImportResult: Sendable {
    public var added: [MusicProject] = []
    public var skipped: [FolderImportIssue] = []
    public var failed: [FolderImportIssue] = []
}
