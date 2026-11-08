import Foundation
import AVFoundation
import Testing
import DeadlineCore
@testable import DeadlineAudio

private func fixture(at url: URL) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 11025))
    buffer.frameLength = 11025
    for channel in 0..<2 {
        for frame in 0..<11025 { buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44100) * 0.25) }
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}
@Test func exportResamplesAndPreservesMetadata() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.wav")
    try fixture(at: source)
    for bits in [16, 24] {
        for channels in [1, 2] {
            for rate in [44100.0, 48000.0, 96000.0] {
                var spec = DeliverySpec(); spec.bitDepth = bits; spec.channels = channels; spec.sampleRate = rate
                spec.artist = "Luna Park"; spec.title = "Night Drive"
                let output = root.appendingPathComponent("\(bits)-\(channels)-\(rate).wav")
                try AudioExporter.export(source: source, destination: output, spec: spec)
                let file = try AVAudioFile(forReading: output)
                #expect(file.fileFormat.sampleRate == rate)
                #expect(file.fileFormat.channelCount == channels)
                #expect(abs(Double(file.length) / rate - 0.25) < 0.003)
                let bytes = try Data(contentsOf: output)
                #expect(bytes[34] == bits)
                #expect(bytes.range(of: Data("Luna Park".utf8)) != nil)
                #expect(bytes.range(of: Data("Night Drive".utf8)) != nil)
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
                try file.read(into: buffer)
                let samples = try #require(buffer.floatChannelData)
                let peak = (0..<Int(buffer.frameLength)).map { abs(samples[0][$0]) }.max() ?? 0
                #expect(peak > 0.2 && peak < 0.3)
            }
        }
    }
}
@Test func failedExportLeavesExistingDestinationIntact() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("invalid.wav"), output = root.appendingPathComponent("existing.wav")
    try Data("invalid".utf8).write(to: source); try Data("keep me".utf8).write(to: output)
    #expect(throws: (any Error).self) { try AudioExporter.export(source: source, destination: output, spec: DeliverySpec()) }
    #expect(try Data(contentsOf: output) == Data("keep me".utf8))
}
@Test func rejectsSourceOverwrite() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("same.wav")
    #expect(throws: (any Error).self) { try AudioExporter.export(source: url, destination: url, spec: DeliverySpec()) }
}

@Test func exportRefusesExistingOutput() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.wav"), output = root.appendingPathComponent("existing.wav")
    try fixture(at: source)
    try Data("old output".utf8).write(to: output)
    #expect(throws: (any Error).self) { try AudioExporter.export(source: source, destination: output, spec: DeliverySpec()) }
    #expect(try Data(contentsOf: output) == Data("old output".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".deadline-") })
}

@Test func oddPCMDataIsPaddedBeforeMetadata() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    var spec = DeliverySpec(); spec.channels = 1; spec.bitDepth = 24; spec.artist = "AB"
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
    buffer.frameLength = 1; buffer.floatChannelData![0][0] = -1
    let writer = try WAVWriter(url: url, spec: spec)
    try writer.append(buffer); try writer.finish()
    let bytes = try Data(contentsOf: url)
    #expect(Array(bytes[44..<47]) == [0, 0, 128])
    #expect(bytes[47] == 0)
    #expect(String(data: bytes[48..<52], encoding: .utf8) == "LIST")
    #expect(bytes[40] == 3)
}

@Test func bundledFFmpegConvertsVorbisAndPreservesOriginal() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let wav = root.appendingPathComponent("original.wav")
    try fixture(at: wav)
    let ogg = root.appendingPathComponent("master with spaces.ogg")
    _ = try FFmpegRuntime.run("ffmpeg", arguments: ["-nostdin", "-n", "-i", wav.path, "-c:a", "libvorbis", ogg.path])
    let original = try Data(contentsOf: ogg)
    let output = root.appendingPathComponent("deliverable.wav")
    try AudioExporter.export(source: ogg, destination: output, spec: DeliverySpec())
    #expect(try AVAudioFile(forReading: output).length > 0)
    #expect(try Data(contentsOf: ogg) == original)
}

@Test func highRateFloatAndTPDFReduction() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("silence-float.wav")
    _ = try FFmpegRuntime.run("ffmpeg", arguments: ["-nostdin", "-n", "-f", "lavfi", "-i", "anullsrc=r=192000:cl=stereo", "-t", "0.1", "-c:a", "pcm_f32le", source.path])
    let original = try Data(contentsOf: source)
    for rate in [44100.0, 48000.0, 96000.0, 192000.0] {
        for bits in [16, 24, 32] {
            var spec = DeliverySpec(); spec.sampleRate = rate; spec.bitDepth = bits
            let output = root.appendingPathComponent("\(rate)-\(bits).wav")
            try AudioExporter.export(source: source, destination: output, spec: spec)
            let file = try AVAudioFile(forReading: output)
            #expect(file.fileFormat.sampleRate == rate)
            #expect(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == bits)
            #expect(file.fileFormat.settings[AVLinearPCMIsFloatKey] as? Bool == (bits == 32))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let samples = try #require(buffer.floatChannelData)
            let values = (0..<Int(buffer.frameLength)).map { samples[0][$0] }
            if bits == 32 { #expect(values.allSatisfy { $0 == 0 }) }
            else {
                #expect(values.contains { $0 != 0 })
                let lsb = Float(pow(2.0, Double(1 - bits)))
                #expect(values.allSatisfy { abs($0) <= lsb * 2 })
            }
        }
    }
    #expect(try Data(contentsOf: source) == original)
}

@Test func matchingWAVPreservesPCMExactly() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for codec in ["pcm_s16le", "pcm_s24le", "pcm_f32le"] {
        let source = root.appendingPathComponent(codec + ".wav")
        _ = try FFmpegRuntime.run("ffmpeg", arguments: ["-nostdin", "-n", "-f", "lavfi", "-i", "sine=frequency=997:sample_rate=48000:duration=0.1", "-ac", "2", "-c:a", codec, source.path])
        var spec = DeliverySpec()
        spec.bitDepth = codec == "pcm_s16le" ? 16 : (codec == "pcm_s24le" ? 24 : 32)
        let output = root.appendingPathComponent(codec + "-out.wav")
        try AudioExporter.export(source: source, destination: output, spec: spec)
        func checksum(_ url: URL) throws -> Data {
            try FFmpegRuntime.run("ffmpeg", arguments: ["-v", "error", "-i", url.path, "-map", "0:a:0", "-c:a", "copy", "-f", "hash", "-hash", "sha256", "-"])
        }
        #expect(try checksum(source) == checksum(output))
    }
}

@Test func integerResamplingOnlyDithersWhenSourceDepthIsReduced() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for sourceBits in [16, 24] {
        let source = root.appendingPathComponent("silence-\(sourceBits).wav")
        _ = try FFmpegRuntime.run("ffmpeg", arguments: ["-nostdin", "-n", "-f", "lavfi", "-i", "anullsrc=r=96000:cl=stereo", "-t", "0.1", "-c:a", "pcm_s\(sourceBits)le", source.path])
        for targetBits in [16, 24] {
            for channels in [1, 2] {
                var spec = DeliverySpec(); spec.sampleRate = 48000; spec.bitDepth = targetBits; spec.channels = channels
                let output = root.appendingPathComponent("\(sourceBits)-\(targetBits)-\(channels).wav")
                try AudioExporter.export(source: source, destination: output, spec: spec)
                let file = try AVAudioFile(forReading: output)
                #expect(file.fileFormat.sampleRate == 48000)
                #expect(file.fileFormat.channelCount == AVAudioChannelCount(channels))
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
                try file.read(into: buffer)
                let samples = try #require(buffer.floatChannelData)
                let values = (0..<Int(buffer.frameLength)).map { samples[0][$0] }
                #expect(!values.isEmpty)
                if sourceBits > targetBits { #expect(values.contains { $0 != 0 }) }
                else { #expect(values.allSatisfy { $0 == 0 }) }
            }
        }
    }
}

@Test func batchFolderAndZIPContainEveryVersionAndPreserveSources() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("master.wav")
    try fixture(at: source)
    let original = try Data(contentsOf: source)
    var cd = DeliverySpec(); cd.sampleRate = 44100; cd.bitDepth = 16
    var high = DeliverySpec(); high.sampleRate = 192000; high.bitDepth = 32
    let items = [BatchExportItem(source: source, spec: cd), BatchExportItem(source: source, spec: high), BatchExportItem(source: source, spec: cd)]
    for zip in [false, true] {
        let destination = root.appendingPathComponent(zip ? "delivery.zip" : "delivery")
        try BatchExporter.export(items, destination: destination, zip: zip)
        var folder = destination
        if zip {
            folder = root.appendingPathComponent("unpacked")
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", destination.path, folder.path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count == 3)
        for (url, item) in Swift.zip(files, items) {
            let audio = try AVAudioFile(forReading: url)
            #expect(audio.fileFormat.sampleRate == item.spec.sampleRate)
            #expect(audio.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == item.spec.bitDepth)
        }
        #expect(throws: (any Error).self) { try BatchExporter.export(items, destination: destination, zip: zip) }
    }
    #expect(try Data(contentsOf: source) == original)
}

@Test func failedBatchCommitsNothingAndCleansStaging() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.wav"); try fixture(at: source)
    let output = root.appendingPathComponent("delivery.zip")
    let items = [BatchExportItem(source: source, spec: DeliverySpec()), BatchExportItem(source: root.appendingPathComponent("missing.wav"), spec: DeliverySpec())]
    #expect(throws: (any Error).self) { try BatchExporter.export(items, destination: output, zip: true) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source.wav"])
}
