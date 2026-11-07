import Foundation
import DeadlineCore

public enum AudioExporter {
    /// Run off the main actor. A temporary sibling is committed only after a complete export.
    public static func export(source: URL, destination: URL, spec: DeliverySpec) throws {
        try spec.validate()
        guard source.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else {
            throw StudioError.message("Choose a destination different from the source audio.")
        }
        guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else {
            throw StudioError.message("A file already exists at this destination. Choose a new filename; originals are never overwritten.")
        }
        let probe = try FFmpegRuntime.run("ffprobe", arguments: [
            "-v", "error", "-protocol_whitelist", "file", "-select_streams", "a:0",
            "-show_entries", "stream=channels", "-of", "json", source.path
        ])
        struct Probe: Decodable { struct Stream: Decodable { let channels: Int; let duration_ts: Int64? }; let streams: [Stream] }
        let info = try JSONDecoder().decode(Probe.self, from: probe)
        guard let stream = info.streams.first, (1...2).contains(stream.channels) else {
            throw StudioError.message("Choose a mono or stereo audio source.")
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".deadline-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try FFmpegRuntime.run("ffmpeg", arguments: [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-protocol_whitelist", "file",
            "-i", source.path, "-map", "0:a:0", "-vn", "-sn", "-dn", "-map_metadata", "-1",
            "-af", "aresample=resampler=soxr:precision=28:dither_method=none",
            "-ar", String(Int(spec.sampleRate)), "-ac", String(spec.channels),
            "-c:a", spec.bitDepth == 16 ? "pcm_s16le" : "pcm_s24le",
            "-metadata", "artist=" + spec.artist, "-metadata", "title=" + spec.title,
            "-f", "wav", temporary.path
        ])
        let rendered = try FFmpegRuntime.run("ffprobe", arguments: [
            "-v", "error", "-protocol_whitelist", "file", "-select_streams", "a:0",
            "-show_entries", "stream=channels,duration_ts", "-of", "json", temporary.path
        ])
        let renderedInfo = try JSONDecoder().decode(Probe.self, from: rendered)
        guard (renderedInfo.streams.first?.duration_ts ?? 0) > 0 else {
            throw StudioError.message("The source contains no audio frames.")
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
