import Foundation
import Testing
@testable import DeadlineCore

private func liveProject(_ folder: URL) throws {
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Ableton Project Info"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Samples"), withIntermediateDirectories: true)
    for name in ["song.als", "revision.ALS", "master.wav", "2mix.wav", "brief.txt", "ignored.zip", "Samples/take.wav"] {
        try Data(name.utf8).write(to: folder.appendingPathComponent(name))
    }
}

@Test func discoveryFindsEachProjectOnceAtAnyDepth() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("Album A/First Song")
    let second = root.appendingPathComponent("Other/Albums/Second Song")
    let nested = first.appendingPathComponent("Side Project")
    for path in [first, second, nested] { try liveProject(path) }
    let result = try ProjectFolderDiscovery.scan(root)
    #expect(result.issues.isEmpty)
    #expect(Set(result.projects.map { $0.folder.path }) == Set([first, second, nested].map { $0.resolvingSymlinksInPath().standardizedFileURL.path }))
    #expect(result.projects.map(\.name).sorted() == ["First Song", "Second Song", "Side Project"])
    #expect(try ProjectFolderDiscovery.scan(second).projects.map { $0.folder.path } == [second.resolvingSymlinksInPath().standardizedFileURL.path])
}

@Test func discoverySkipsProductionAssetsLinksPackagesAndLibrary() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let song = root.appendingPathComponent("Song")
    let library = root.appendingPathComponent("Library")
    for path in [song, song.appendingPathComponent("Samples/Other Set"), song.appendingPathComponent("Backup/Old Set"),
                 root.appendingPathComponent(".hidden/Song"), root.appendingPathComponent("Brief.pages/Song"), library] {
        try liveProject(path)
    }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Loop"), withDestinationURL: root)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias"), withDestinationURL: song)
    let result = try ProjectFolderDiscovery.scan(root, excluding: [library])
    #expect(result.projects.map { $0.folder.path } == [song.resolvingSymlinksInPath().standardizedFileURL.path])
    #expect(result.issues.isEmpty)
}

@Test func discoveryDoesNotTurnAudioFoldersOrContainersIntoProjects() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Samples"), withIntermediateDirectories: true)
    try Data([1]).write(to: root.appendingPathComponent("master.wav"))
    #expect(try ProjectFolderDiscovery.scan(root).projects.isEmpty)
    try liveProject(root.appendingPathComponent("Real Project"))
    #expect(try ProjectFolderDiscovery.scan(root).projects.map(\.name) == ["Real Project"])
}

@Test func batchUsesFolderNamesSharedArtistFiltersAndSpotlights() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("Songs/First")
    let second = root.appendingPathComponent("Songs/Second")
    for path in [first, second] { try liveProject(path) }
    let repository = ProjectRepository(root: root.appendingPathComponent("Library"))
    let report = try await repository.createBatchFromFolders([
        .init(folder: first), .init(folder: second, name: "  My custom title  ")
    ], artist: "The Same Artist")
    #expect(report.added.map(\.name) == ["First", "My custom title"])
    #expect(report.added.allSatisfy { $0.artist == "The Same Artist" })
    #expect(report.failed.isEmpty && report.skipped.isEmpty)
    for project in report.added {
        #expect(Set(project.assets.map(\.name)) == ["master.wav", "2mix.wav", "brief.txt"])
        #expect(project.assets.first { $0.id == project.spotlightAssetID }?.name == "master.wav")
        #expect(project.assets.first { $0.id == project.premasterAssetID }?.name == "2mix.wav")
        let source = URL(fileURLWithPath: try #require(project.sourceFolderPath))
        for asset in project.assets {
            #expect(repository.fileURL(asset, projectID: project.id).standardizedFileURL.path == source.appendingPathComponent(asset.name).standardizedFileURL.path)
            #expect(try Data(contentsOf: source.appendingPathComponent(asset.name)) == Data(asset.name.utf8))
        }
        #expect(try Data(contentsOf: source.appendingPathComponent("Samples/take.wav")) == Data("Samples/take.wav".utf8))
    }
    #expect(try await repository.load() == report.added)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Library/Files").path))
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Library/References").path))
}

@Test func batchRechecksDuplicatesAndPreservesAlbumsAndSameNamedProjects() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("A/Song"), second = root.appendingPathComponent("B/Song")
    for path in [first, second] { try liveProject(path) }
    let repository = ProjectRepository(root: root.appendingPathComponent("Library"))
    let existing = try await repository.createFromFolder(first, project: .init(name: "Keep my name", artist: "Keep my artist"), existing: [])
    let album = MusicAlbum(name: "Album", projectIDs: [existing.id])
    try await repository.saveAlbums([album])
    let alias = root.appendingPathComponent("Alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
    let report = try await repository.createBatchFromFolders([.init(folder: first), .init(folder: alias), .init(folder: second), .init(folder: second)], artist: "New artist")
    #expect(report.added.count == 1 && report.skipped.count == 3 && report.failed.isEmpty)
    #expect(report.added.first?.name == "Song")
    #expect(try await repository.load() == report.added + [existing])
    #expect(try await repository.loadAlbums() == [album])
}

@Test func batchReportsFailuresAndKeepsSuccessfulProjects() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let good = root.appendingPathComponent("Good"), bad = root.appendingPathComponent("Bad")
    for path in [good, bad] { try liveProject(path) }
    try FileManager.default.createSymbolicLink(at: bad.appendingPathComponent("loop"), withDestinationURL: bad)
    let library = root.appendingPathComponent("Library")
    let repository = ProjectRepository(root: library)
    let report = try await repository.createBatchFromFolders([
        .init(folder: good), .init(folder: bad), .init(folder: root.appendingPathComponent("Missing")),
        .init(folder: library), .init(folder: bad, name: "  ")
    ], artist: "Artist")
    #expect(report.added.count == 1 && report.failed.count == 4)
    #expect(try await repository.load() == report.added)
    #expect(try Data(contentsOf: bad.appendingPathComponent("master.wav")) == Data("master.wav".utf8))
}

@Test func cancelledBatchDoesNotChangeLibrary() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let song = root.appendingPathComponent("Song")
    try liveProject(song)
    let repository = ProjectRepository(root: root.appendingPathComponent("Library"))
    let keep = MusicProject(name: "Existing")
    try await repository.save([keep])
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await repository.createBatchFromFolders([.init(folder: song)], artist: "Artist")
    }
    do { _ = try await task.value; Issue.record("Cancelled import should throw") }
    catch is CancellationError { }
    #expect(try await repository.load() == [keep])
}

@Test func cancelledDiscoveryStopsWithoutReturningCandidates() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try liveProject(root)
    let task = Task.detached {
        withUnsafeCurrentTask { $0?.cancel() }
        return try ProjectFolderDiscovery.scan(root)
    }
    do { _ = try await task.value; Issue.record("Cancelled discovery should throw") }
    catch is CancellationError { }
}
