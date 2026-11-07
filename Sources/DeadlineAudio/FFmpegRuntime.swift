import Foundation
import DeadlineCore

/// Executes bundled command-line tools without a shell or runtime installation.
public enum FFmpegRuntime {
    public static func executable(_ name: String) throws -> URL {
        let root: URL
        if Bundle.main.bundleURL.pathExtension == "app", let resources = Bundle.main.resourceURL {
            root = resources.appendingPathComponent("FFmpegFull")
        } else if let development = ProcessInfo.processInfo.environment["DEADLINE_FFMPEG_ROOT"] {
            root = URL(fileURLWithPath: development)
        } else {
            throw StudioError.message("Bundled FFmpeg is missing. Build the app with scripts/package.sh, or use scripts/dev.sh for development.")
        }
        let url = root.appendingPathComponent("bin").appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw StudioError.message("Bundled \(name) is missing. Rebuild the app.")
        }
        return url
    }

    public static func run(_ name: String, arguments: [String]) throws -> Data {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadline-ffmpeg-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("stdout")
        let errors = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let output = try FileHandle(forWritingTo: log), errorOutput = try FileHandle(forWritingTo: errors)
        defer { try? output.close(); try? errorOutput.close() }
        let process = Process()
        process.executableURL = try executable(name)
        process.arguments = arguments
        let runtime = process.executableURL!.deletingLastPathComponent().deletingLastPathComponent()
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "C", "FREI0R_PATH": runtime.appendingPathComponent("plugins").path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errorOutput
        try process.run()
        while process.isRunning {
            if Task.isCancelled { process.terminate(); process.waitUntilExit(); throw CancellationError() }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: (try? Data(contentsOf: errors)) ?? Data(), encoding: .utf8) ?? ""
            throw StudioError.message("\(name) failed: \(detail.suffix(3000))")
        }
        return try Data(contentsOf: log)
    }
}
