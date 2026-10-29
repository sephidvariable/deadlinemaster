import Foundation

/// Structural recognition, not an ALS parser. Never follows symbolic links.
public struct AbletonFolderScan: Sendable {
    public var projectPaths: Set<String> = []
    public var setCount = 0
    public var resemblesProject: Bool { !projectPaths.isEmpty }
    public static func scan(_ root: URL) throws -> Self {
        var result = Self()
        func visit(_ directory: URL) throws {
            try Task.checkCancellation()
            let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
            var folders: [URL] = []
            var sets = 0
            for child in children {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true { folders.append(child) }
                else if values.isRegularFile == true && child.pathExtension.lowercased() == "als" { sets += 1 }
            }
            result.setCount += sets
            let names = Set(folders.map { $0.lastPathComponent.lowercased() })
            if sets > 0 && (names.contains("ableton project info") || names.contains("samples")) {
                result.projectPaths.insert(directory.standardizedFileURL.path)
            }
            for folder in folders { try visit(folder) }
        }
        try visit(root)
        return result
    }
    public func excludes(_ url: URL, parent: URL, isDirectory: Bool) -> Bool {
        if isDirectory {
            if projectPaths.contains(url.standardizedFileURL.path) { return true }
            return projectPaths.contains(parent.standardizedFileURL.path)
                && ["samples", "backup", "ableton project info"].contains(url.lastPathComponent.lowercased())
        }
        return ["als", "asd"].contains(url.pathExtension.lowercased())
    }
}
