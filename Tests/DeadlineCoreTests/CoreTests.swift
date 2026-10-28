import Foundation
import Testing
@testable import DeadlineCore

@Test func parsesExplicitBrief() {
    let result = BriefParser.parse("Stereo WAV, 16-bit, 44.1 kHz\nArtist: Luna Park\nTitle: Night Drive")
    #expect(result.spec.bitDepth == 16)
    #expect(result.spec.sampleRate == 44100)
    #expect(result.spec.channels == 2)
    #expect(result.spec.artist == "Luna Park")
    #expect(result.spec.title == "Night Drive")
}
@Test func ambiguousBriefPreservesSettingsAndWarns() {
    let result = BriefParser.parse("16-bit and 24-bit; 44.1 kHz and 96 kHz; mono and stereo; MP3 at -14 LUFS")
    #expect(result.spec.bitDepth == 24)
    #expect(result.spec.sampleRate == 48000)
    #expect(result.warnings.count >= 5)
}
@Test func unspecifiedValuesArePreserved() {
    var base = DeliverySpec(); base.title = "My song"; base.channels = 1
    let result = BriefParser.parse("Please send by Friday", base: base)
    #expect(result.spec == base)
    #expect(result.detected.isEmpty)
}
@Test func rejectsInvalidExportSettings() {
    var spec = DeliverySpec(); spec.bitDepth = 32
    #expect(throws: (any Error).self) { try spec.validate() }
}
@Test func libraryRoundTripAndIndependentCopy() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = ProjectRepository(root: root.appendingPathComponent("Library"))
    #expect(try await repository.load().isEmpty)
    let source = root.appendingPathComponent("mix.wav")
    try Data([1, 2, 3]).write(to: source)
    var project = MusicProject(name: "Night Drive", artist: "Luna")
    let asset = try await repository.importFile(source, projectID: project.id)
    project.assets.append(asset); project.notes = "Ready to master"
    try await repository.save([project])
    try FileManager.default.removeItem(at: source)
    let reopened = ProjectRepository(root: root.appendingPathComponent("Library"))
    #expect(try await reopened.load() == [project])
    #expect(try Data(contentsOf: reopened.fileURL(asset, projectID: project.id)) == Data([1, 2, 3]))
}
@Test func corruptLibraryIsNotSilentlyReset() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let index = root.appendingPathComponent("library.json")
    let original = Data("not valid json".utf8); try original.write(to: index)
    do { _ = try await ProjectRepository(root: root).load(); Issue.record("Expected invalid JSON to fail") } catch {}
    #expect(try Data(contentsOf: index) == original)
}
