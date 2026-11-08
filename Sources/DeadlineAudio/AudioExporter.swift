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
            "-show_entries", "stream=channels,sample_rate,codec_name,sample_fmt,bits_per_raw_sample,bits_per_sample", "-of", "json", source.path
        ])
        struct Probe: Decodable { struct Stream: Decodable { let channels: Int; let duration_ts: Int64?; let sample_rate: String?; let codec_name: String?; let sample_fmt: String?; let bits_per_raw_sample: String?; let bits_per_sample: Int? }; let streams: [Stream] }
        let info = try JSONDecoder().decode(Probe.self, from: probe)
        guard let stream = info.streams.first, (1...2).contains(stream.channels) else {
            throw StudioError.message("Choose a mono or stereo audio source.")
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".deadline-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let codec = spec.bitDepth == 32 ? "pcm_f32le" : (spec.bitDepth == 16 ? "pcm_s16le" : "pcm_s24le")
        let resample = Double(stream.sample_rate ?? "") != spec.sampleRate
        let remix = stream.channels != spec.channels
        let floating = ["flt", "fltp", "dbl", "dblp"].contains(stream.sample_fmt ?? "")
        let sourceBits = max(Int(stream.bits_per_raw_sample ?? "") ?? 0, stream.bits_per_sample ?? 0)
        // Dither depends on source precision, not the intermediate processing format.
        let needsDither = spec.bitDepth != 32 && (floating || sourceBits == 0 || sourceBits > spec.bitDepth)
        var filters: [String] = []
        if resample || remix {
            // Perform all rate/channel processing in double precision before quantization.
            var first = "aresample=osf=dbl:dither_method=none:rematrix_maxval=1"
            if resample { first += ":osr=\(Int(spec.sampleRate)):resampler=soxr:precision=28" }
            if remix { first += ":ochl=" + (spec.channels == 1 ? "mono" : "stereo") }
            filters.append(first)
        }
        if spec.bitDepth != 32 && (needsDither || resample || remix) {
            // Explicitly disable dither for unchanged/increased integer source depth.
            let dither = needsDither ? "triangular" : "none"
            filters.append("aresample=osf=\(spec.bitDepth == 16 ? "s16" : "s32"):output_sample_bits=\(spec.bitDepth):dither_method=\(dither)")
        }
        var arguments = [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-protocol_whitelist", "file",
            "-i", source.path, "-map", "0:a:0", "-vn", "-sn", "-dn", "-map_metadata", "-1"
        ]
        if !resample && !remix && stream.codec_name == codec {
            arguments += ["-c:a", "copy"]
        } else {
            if !filters.isEmpty { arguments += ["-af", filters.joined(separator: ",")] }
            arguments += ["-c:a", codec]
        }
        arguments += [
            "-metadata", "artist=" + spec.artist, "-metadata", "title=" + spec.title,
            "-f", "wav", temporary.path
        ]
        _ = try FFmpegRuntime.run("ffmpeg", arguments: arguments)
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
