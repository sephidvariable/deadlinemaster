import Foundation
import AVFoundation
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
        let input = try AVAudioFile(forReading: source)
        guard input.length > 0 else { throw StudioError.message("The source contains no audio frames.") }
        guard input.processingFormat.channelCount <= 2 else { throw StudioError.message("This prototype accepts mono or stereo sources, not surround audio.") }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: spec.sampleRate, channels: AVAudioChannelCount(spec.channels)),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
            throw StudioError.message("Cannot convert this audio format.")
        }
        converter.downmix = true
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".deadline-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let writer = try WAVWriter(url: temporary, spec: spec)
        var readingError: Error?
        while true {
            try Task.checkCancellation()
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { requested, state in
                guard input.framePosition < input.length else { state.pointee = .endOfStream; return nil }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: requested) else {
                    readingError = StudioError.message("Could not allocate an audio buffer."); state.pointee = .endOfStream; return nil
                }
                do {
                    try input.read(into: buffer, frameCount: requested)
                    state.pointee = buffer.frameLength > 0 ? .haveData : .endOfStream
                    return buffer.frameLength > 0 ? buffer : nil
                } catch { readingError = error; state.pointee = .endOfStream; return nil }
            }
            if let readingError { throw readingError }
            if let conversionError { throw conversionError }
            if output.frameLength > 0 { try writer.append(output) }
            switch status {
            case .endOfStream:
                try writer.finish()
                try Task.checkCancellation()
                // Move fails if another file appears at the destination during conversion.
                try FileManager.default.moveItem(at: temporary, to: destination)
                return
            case .error: throw StudioError.message("Audio conversion failed.")
            case .haveData, .inputRanDry: continue
            @unknown default: throw StudioError.message("Unknown audio converter result.")
            }
        }
    }
}
