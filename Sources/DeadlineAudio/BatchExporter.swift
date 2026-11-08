import Foundation
import DeadlineCore

public struct BatchExportItem: Sendable {
    public let source: URL
    public let spec: DeliverySpec
    public init(source: URL, spec: DeliverySpec) { self.source = source; self.spec = spec }
}

public enum BatchExporter {
    /// Stages the entire batch beside the destination, then commits without replacing anything.
    /// Folder output is always a new folder, never a merge into an existing directory.
    public static func export(_ items: [BatchExportItem], destination: URL, zip: Bool) throws {
        guard !items.isEmpty else { throw StudioError.message("Add at least one delivery version.") }
        for item in items { try item.spec.validate() }
        guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else {
            throw StudioError.message("This destination already exists. Choose a new name; existing files are never replaced.")
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".deadline-batch-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let payload = staging.appendingPathComponent("Deliverables", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: false)
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            let stem = item.source.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            // Prefix makes duplicate versions and case-insensitive filenames unambiguous.
            let filename = String(format: "%03d", index + 1) + "_" + String(stem.prefix(80)) + "_\(Int(item.spec.sampleRate))Hz_\(item.spec.bitDepth)\(item.spec.bitDepth == 32 ? "float" : "bit")_\(item.spec.channels == 1 ? "mono" : "stereo").wav"
            try AudioExporter.export(source: item.source, destination: payload.appendingPathComponent(filename), spec: item.spec)
        }
        var result = payload
        if zip {
            result = staging.appendingPathComponent("Deliverables.zip")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--norsrc", "--noextattr", payload.path, result.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw StudioError.message("Could not create the ZIP archive. No delivery was saved.") }
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: result, to: destination)
    }
}
