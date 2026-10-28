import Foundation
import AVFoundation
import DeadlineCore

/// Streams integer PCM and a RIFF INFO metadata chunk. No whole-song allocation.
final class WAVWriter {
    private let handle: FileHandle
    private let spec: DeliverySpec
    private var bytes: UInt64 = 0
    init(url: URL, spec: DeliverySpec) throws {
        self.spec = spec
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw StudioError.message("Could not create output file.") }
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data(repeating: 0, count: 44))
    }
    deinit { try? handle.close() }
    func append(_ buffer: AVAudioPCMBuffer) throws {
        guard let channels = buffer.floatChannelData else { throw StudioError.message("Expected floating-point audio from the converter.") }
        let count = Int(buffer.frameLength) * spec.channels * (spec.bitDepth / 8)
        guard bytes + UInt64(count) < UInt64(UInt32.max) - 1_048_576 else { throw StudioError.message("Output exceeds the standard WAV 4 GB limit.") }
        var data = Data(); data.reserveCapacity(count)
        for frame in 0..<Int(buffer.frameLength) {
            for channel in 0..<spec.channels {
                let raw = channels[channel][frame]
                let x = raw.isFinite ? max(-1, min(1, Double(raw))) : 0
                let scale = x < 0 ? Double(1 << (spec.bitDepth - 1)) : Double((1 << (spec.bitDepth - 1)) - 1)
                let value = Int32((x * scale).rounded())
                for byte in 0..<(spec.bitDepth / 8) { data.append(UInt8(truncatingIfNeeded: value >> (8 * byte))) }
            }
        }
        try handle.write(contentsOf: data); bytes += UInt64(data.count)
    }
    func finish() throws {
        if bytes % 2 == 1 { try handle.write(contentsOf: Data([0])) }
        var info = Data("INFO".utf8)
        for (key, value) in [("IART", spec.artist), ("INAM", spec.title)] {
            var text = Data(value.replacingOccurrences(of: "\0", with: "").utf8); text.append(0)
            guard text.count < 100_000 else { throw StudioError.message("Metadata is too long.") }
            info.append(contentsOf: key.utf8); info.le(UInt32(text.count)); info.append(text)
            if text.count % 2 == 1 { info.append(0) }
        }
        var list = Data("LIST".utf8); list.le(UInt32(info.count)); list.append(info)
        try handle.write(contentsOf: list)
        let length = try handle.offset()
        var header = Data("RIFF".utf8); header.le(UInt32(length - 8)); header.append(contentsOf: "WAVEfmt ".utf8)
        header.le(UInt32(16)); header.le(UInt16(1)); header.le(UInt16(spec.channels))
        header.le(UInt32(spec.sampleRate)); header.le(UInt32(spec.sampleRate) * UInt32(spec.channels * spec.bitDepth / 8))
        header.le(UInt16(spec.channels * spec.bitDepth / 8)); header.le(UInt16(spec.bitDepth))
        header.append(contentsOf: "data".utf8); header.le(UInt32(bytes))
        try handle.seek(toOffset: 0); try handle.write(contentsOf: header); try handle.synchronize(); try handle.close()
    }
}
private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
