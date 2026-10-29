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
@Test func libraryRoundTripAndLiveReference() async throws {
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
    try Data([4, 5]).write(to: source)
    let reopened = ProjectRepository(root: root.appendingPathComponent("Library"))
    #expect(try await reopened.load() == [project])
    #expect(try Data(contentsOf: reopened.fileURL(asset, projectID: project.id)) == Data([4, 5]))
    try FileManager.default.removeItem(at: source)
    #expect(throws: (any Error).self) { try reopened.availableFileURL(asset, projectID: project.id) }
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

@Test func spotlightPersistsAndOldProjectsDecode() throws {
    var project = MusicProject(name: "Master")
    let asset = ProjectAsset(name: "final.wav", storedName: "final.wav", byteCount: 10)
    project.assets = [asset]
    project.spotlightAssetID = asset.id
    let encoded = try JSONEncoder().encode(project)
    #expect(try JSONDecoder().decode(MusicProject.self, from: encoded).spotlightAssetID == asset.id)
    var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    legacy.removeValue(forKey: "spotlightAssetID")
    let oldData = try JSONSerialization.data(withJSONObject: legacy)
    #expect(try JSONDecoder().decode(MusicProject.self, from: oldData).spotlightAssetID == nil)
}

@Test func removingLibraryEntryRetainsImportedFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = ProjectRepository(root: root)
    _ = try await repository.load()
    let source = root.appendingPathComponent("source.wav")
    try Data([1, 2, 3]).write(to: source)
    var project = MusicProject(name: "Delete me")
    let asset = try await repository.importFile(source, projectID: project.id)
    project.assets = [asset]
    let kept = MusicProject(name: "Keep me")
    try await repository.save([project, kept])
    try await repository.save([kept])
    #expect(try await repository.load() == [kept])
    #expect(FileManager.default.fileExists(atPath: repository.fileURL(asset, projectID: project.id).path))
    #expect(try Data(contentsOf: source) == Data([1, 2, 3]))
}

@Test func folderCreationPreservesHierarchyAndOmitsEmptyFolders() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appendingPathComponent("Song")
    try FileManager.default.createDirectory(at: source.appendingPathComponent("Empty"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: source.appendingPathComponent("Mixes"), withIntermediateDirectories: true)
    try Data([1]).write(to: source.appendingPathComponent("final.wav"))
    try Data([2]).write(to: source.appendingPathComponent("Mixes/final.wav"))
    let repository = ProjectRepository(root: base.appendingPathComponent("Library"))
    let project = try await repository.createFromFolder(source, project: MusicProject(name: "Custom name"), existing: [])
    #expect(project.name == "Custom name")
    #expect(project.assets.count == 3)
    #expect(!project.assets.contains { $0.name == "Empty" })
    for asset in project.assets.filter(\.isAudio) {
        #expect(try Data(contentsOf: repository.fileURL(asset, projectID: project.id)) == Data(contentsOf: source.appendingPathComponent(asset.name)))
    }
    #expect(try await repository.load() == [project])
}

@Test func folderFailureDoesNotCommitPartialProject() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appendingPathComponent("Song")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data([1]).write(to: source.appendingPathComponent("a.wav"))
    try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("z-link").path, withDestinationPath: source.path)
    let root = base.appendingPathComponent("Library")
    let repository = ProjectRepository(root: root)
    let project = MusicProject(name: "Fail")
    do {
        _ = try await repository.createFromFolder(source, project: project, existing: [])
        Issue.record("Expected symbolic link rejection")
    } catch {}
    #expect(try await repository.load().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("References").appendingPathComponent(project.id.uuidString).path))
    #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("a.wav").path))
}

@Test func abletonScanAndImportExcludeProductionMaterial() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appendingPathComponent("Song")
    for path in ["Ableton Project Info", "Samples/Recorded", "Backup", "Exports", "Other Set/Ableton Project Info"] {
        try FileManager.default.createDirectory(at: source.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    for path in ["v1.als", "v2.als", "Samples/Recorded/take.wav", "Backup/old.als", "Exports/master.wav", "Exports/master.wav.asd", "Other Set/song.als", "Other Set/material.wav"] {
        try Data([1]).write(to: source.appendingPathComponent(path))
    }
    let scan = try AbletonFolderScan.scan(source)
    #expect(scan.resemblesProject)
    #expect(scan.projectPaths.count == 2)
    #expect(scan.setCount == 4)
    let repository = ProjectRepository(root: base.appendingPathComponent("Library"))
    let imported = try await repository.createFromFolder(source, project: MusicProject(name: "Song"), existing: [])
    #expect(Set(imported.assets.map(\.name)) == ["Exports", "Exports/master.wav"])
    #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("Samples/Recorded/take.wav").path))
}

@Test func ordinaryAudioFolderIsNotRecognizedAsLiveProject() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Samples"), withIntermediateDirectories: true)
    try Data([1]).write(to: root.appendingPathComponent("master.wav"))
    #expect(try !AbletonFolderScan.scan(root).resemblesProject)
}

@Test func importFiltersUnsupportedFilesAndKeepsDocumentPackages() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appendingPathComponent("Song")
    try FileManager.default.createDirectory(at: source.appendingPathComponent("Brief.pages"), withIntermediateDirectories: true)
    for name in ["MASTER.OGG", "mix.AIFF", "brief.pdf", "notes.docx", "readme.txt", "art.png", "session.zip", "video.mov", "Brief.pages/internal.bin"] {
        try Data([1]).write(to: source.appendingPathComponent(name))
    }
    let repository = ProjectRepository(root: base.appendingPathComponent("Library"))
    let project = try await repository.createFromFolder(source, project: MusicProject(name: "Song"), existing: [])
    #expect(Set(project.assets.map(\.name)) == ["MASTER.OGG", "mix.AIFF", "brief.pdf", "notes.docx", "readme.txt", "Brief.pages"])
    #expect(project.assets.first { $0.name == "MASTER.OGG" }?.isAudio == true)
    let package = try #require(project.assets.first { $0.name == "Brief.pages" })
    #expect(FileManager.default.fileExists(atPath: repository.fileURL(package, projectID: project.id).appendingPathComponent("internal.bin").path))
    do {
        _ = try await repository.importFile(source.appendingPathComponent("art.png"), projectID: project.id)
        Issue.record("Unsupported manual import should fail")
    } catch {}
}

@Test func automaticMasterUsesShortestAudioFilenameAndPreservesManualPin() {
    var project = MusicProject(name: "Song")
    let long = ProjectAsset(name: "song_MASTER_final.wav", storedName: "1", byteCount: 1)
    let short = ProjectAsset(name: "Exports/Approved/MaStEr.wav", storedName: "2", byteCount: 1)
    let document = ProjectAsset(name: "master.txt", storedName: "3", byteCount: 1)
    let folderMatch = ProjectAsset(name: "Masters/mix.wav", storedName: "4", byteCount: 1)
    project.assets = [long, document, folderMatch, short]
    project.selectAutomaticMaster()
    #expect(project.spotlightAssetID == short.id)
    project.spotlightAssetID = long.id
    project.selectAutomaticMaster()
    #expect(project.spotlightAssetID == long.id)
    project.spotlightAssetID = nil
    project.assets = [document, folderMatch]
    project.selectAutomaticMaster()
    #expect(project.spotlightAssetID == nil)
}

@Test func automaticMasterBreaksLengthTiesAlphabetically() {
    var project = MusicProject(name: "Song")
    let b = ProjectAsset(name: "masterB.wav", storedName: "b", byteCount: 1)
    let a = ProjectAsset(name: "masterA.wav", storedName: "a", byteCount: 1)
    project.assets = [b, a]
    project.selectAutomaticMaster()
    #expect(project.spotlightAssetID == a.id)
}

@Test func deletingShortcutsPreservesOriginalsPackagesAndLegacyCopies() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appendingPathComponent("Song")
    try FileManager.default.createDirectory(at: source.appendingPathComponent("Brief.pages"), withIntermediateDirectories: true)
    try Data([1, 2]).write(to: source.appendingPathComponent("master.wav"))
    try Data([3]).write(to: source.appendingPathComponent("Brief.pages/content"))
    let root = base.appendingPathComponent("Library")
    let repository = ProjectRepository(root: root)
    let project = try await repository.createFromFolder(source, project: MusicProject(name: "Song"), existing: [])
    let refs = root.appendingPathComponent("References").appendingPathComponent(project.id.uuidString)
    #expect(try FileManager.default.attributesOfItem(atPath: refs.appendingPathComponent("master.wav").path)[.type] as? FileAttributeType == .typeSymbolicLink)
    #expect(try Data(contentsOf: refs.appendingPathComponent("master.wav")) == Data([1, 2]))
    let legacy = root.appendingPathComponent("Files").appendingPathComponent(project.id.uuidString)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data([9]).write(to: legacy.appendingPathComponent("old.wav"))
    #expect(try await repository.deleteProject(project.id, existing: [project]) == nil)
    #expect(!FileManager.default.fileExists(atPath: refs.path))
    #expect(try Data(contentsOf: source.appendingPathComponent("master.wav")) == Data([1, 2]))
    #expect(try Data(contentsOf: source.appendingPathComponent("Brief.pages/content")) == Data([3]))
    #expect(try Data(contentsOf: legacy.appendingPathComponent("old.wav")) == Data([9]))
    #expect(try await repository.load().isEmpty)
}

@Test func deletionRefusesUnexpectedRealFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = ProjectRepository(root: root)
    let project = MusicProject(name: "Keep")
    try await repository.save([project])
    let refs = root.appendingPathComponent("References").appendingPathComponent(project.id.uuidString)
    try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
    let unexpected = refs.appendingPathComponent("important.wav")
    try Data([42]).write(to: unexpected)
    do {
        _ = try await repository.deleteProject(project.id, existing: [project])
        Issue.record("Expected protection of real files")
    } catch {}
    #expect(try await repository.load() == [project])
    #expect(try Data(contentsOf: unexpected) == Data([42]))
}

@Test func legacyCopiedAssetStillResolves() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = MusicProject(name: "Legacy")
    let asset = ProjectAsset(name: "mix.wav", storedName: "mix.wav", byteCount: 1)
    let folder = root.appendingPathComponent("Files").appendingPathComponent(project.id.uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data([7]).write(to: folder.appendingPathComponent("mix.wav"))
    let repository = ProjectRepository(root: root)
    #expect(try Data(contentsOf: repository.availableFileURL(asset, projectID: project.id)) == Data([7]))
}

@Test func deletionOfBrokenShortcutDoesNotRequireSource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = ProjectRepository(root: root)
    _ = try await repository.load()
    let source = root.appendingPathComponent("source.wav")
    try Data([1]).write(to: source)
    var project = MusicProject(name: "Broken")
    project.assets = [try await repository.importFile(source, projectID: project.id)]
    try await repository.save([project])
    try FileManager.default.removeItem(at: source)
    #expect(try await repository.deleteProject(project.id, existing: [project]) == nil)
    #expect(try await repository.load().isEmpty)
}

@Test func failedDeletionSaveRestoresShortcutTree() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = ProjectRepository(root: root)
    _ = try await repository.load()
    let source = root.appendingPathComponent("source.wav")
    try Data([1]).write(to: source)
    var project = MusicProject(name: "Restore")
    let asset = try await repository.importFile(source, projectID: project.id)
    project.assets = [asset]
    // A directory in place of the index forces atomic save to fail.
    try FileManager.default.createDirectory(at: root.appendingPathComponent("library.json"), withIntermediateDirectories: true)
    do {
        _ = try await repository.deleteProject(project.id, existing: [project])
        Issue.record("Expected save failure")
    } catch {}
    #expect(try Data(contentsOf: repository.availableFileURL(asset, projectID: project.id)) == Data([1]))
    let link = root.appendingPathComponent("References").appendingPathComponent(project.id.uuidString).appendingPathComponent(asset.storedName)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
}

@Test func refreshTracksAddRenameDeleteAndIgnoresZip() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appendingPathComponent("Song")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let original = source.appendingPathComponent("master.wav")
    try Data([1]).write(to: original)
    let root = base.appendingPathComponent("Library")
    let repository = ProjectRepository(root: root)
    let project = try await repository.createFromFolder(source, project: MusicProject(name: "Song"), existing: [])
    let masterID = try #require(project.spotlightAssetID)
    try Data([9]).write(to: source.appendingPathComponent("ignored.zip"))
    let untouched = try await repository.refreshProject(project.id, existing: [project])
    #expect(untouched == [project])

    try FileManager.default.moveItem(at: original, to: source.appendingPathComponent("master-renamed.wav"))
    var next = try await repository.refreshProject(project.id, existing: untouched)
    #expect(next[0].spotlightAssetID == masterID)
    #expect(next[0].assets.first?.id == masterID)
    #expect(next[0].assets.first?.name == "master-renamed.wav")
    let refs = root.appendingPathComponent("References").appendingPathComponent(project.id.uuidString)
    #expect(!FileManager.default.fileExists(atPath: refs.appendingPathComponent("master.wav").path))
    #expect(try Data(contentsOf: refs.appendingPathComponent("master-renamed.wav")) == Data([1]))

    try Data([2]).write(to: source.appendingPathComponent("new master.wav"))
    try FileManager.default.removeItem(at: source.appendingPathComponent("master-renamed.wav"))
    next = try await repository.refreshProject(project.id, existing: next)
    #expect(next[0].assets.map(\.name) == ["new master.wav"])
    #expect(next[0].spotlightAssetID == next[0].assets.first?.id)
    try FileManager.default.removeItem(at: source.appendingPathComponent("new master.wav"))
    next = try await repository.refreshProject(project.id, existing: next)
    #expect(next[0].assets.isEmpty)
    #expect(next[0].spotlightAssetID == nil)
    #expect(try await repository.load() == next)
}

@Test func unavailableFolderPreservesLibraryAndResumesAfterReturn() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appendingPathComponent("Song")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data([1]).write(to: source.appendingPathComponent("mix.wav"))
    let repository = ProjectRepository(root: base.appendingPathComponent("Library"))
    let project = try await repository.createFromFolder(source, project: MusicProject(name: "Song"), existing: [])
    let away = base.appendingPathComponent("Disconnected")
    try FileManager.default.moveItem(at: source, to: away)
    do {
        _ = try await repository.refreshProject(project.id, existing: [project])
        Issue.record("Unavailable folder must not remove assets")
    } catch {}
    #expect(try await repository.load() == [project])
    try FileManager.default.moveItem(at: away, to: source)
    #expect(try await repository.refreshProject(project.id, existing: [project]) == [project])
}

@Test func refreshKeepsExternalManualImportsAndAbletonExclusions() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appendingPathComponent("Song")
    for path in ["Ableton Project Info", "Samples"] {
        try FileManager.default.createDirectory(at: source.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    try Data([1]).write(to: source.appendingPathComponent("song.als"))
    let repository = ProjectRepository(root: base.appendingPathComponent("Library"))
    var project = try await repository.createFromFolder(source, project: MusicProject(name: "Song"), existing: [])
    let external = base.appendingPathComponent("brief.txt")
    try Data([2]).write(to: external)
    let manual = try await repository.importFile(external, projectID: project.id)
    project.assets.append(manual)
    try await repository.save([project])
    try Data([3]).write(to: source.appendingPathComponent("Samples/production.wav"))
    try Data([4]).write(to: source.appendingPathComponent("master.wav"))
    let next = try await repository.refreshProject(project.id, existing: [project])
    #expect(Set(next[0].assets.map(\.name)) == ["master.wav", "brief.txt"])
    #expect(next[0].assets.contains(manual))
    #expect(try Data(contentsOf: repository.availableFileURL(manual, projectID: project.id)) == Data([2]))
}

@Test func refreshFailureRollsBackShortcutTreeAndIndex() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appendingPathComponent("Song")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data([1]).write(to: source.appendingPathComponent("mix.wav"))
    let root = base.appendingPathComponent("Library")
    let repository = ProjectRepository(root: root)
    let project = try await repository.createFromFolder(source, project: MusicProject(name: "Song"), existing: [])
    try Data([2]).write(to: source.appendingPathComponent("new.wav"))
    let index = root.appendingPathComponent("library.json")
    try FileManager.default.removeItem(at: index)
    try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
    do {
        _ = try await repository.refreshProject(project.id, existing: [project])
        Issue.record("Expected failed index save")
    } catch {}
    let refs = root.appendingPathComponent("References").appendingPathComponent(project.id.uuidString)
    #expect(try Data(contentsOf: refs.appendingPathComponent("mix.wav")) == Data([1]))
    #expect(!FileManager.default.fileExists(atPath: refs.appendingPathComponent("new.wav").path))
}
