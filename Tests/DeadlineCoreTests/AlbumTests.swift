import Foundation
import Testing
@testable import DeadlineCore

@Test func albumMembershipSurvivesProjectEditsAndDeletion() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = ProjectRepository(root: root)
    var first = MusicProject(name: "Single one")
    let second = MusicProject(name: "Single two")
    try await repository.save([first, second])
    var album = MusicAlbum(name: "Debut", projectIDs: [first.id, second.id])
    let compilation = MusicAlbum(name: "Compilation", projectIDs: [first.id])
    try await repository.saveAlbums([album, compilation])
    first.notes = "Edited after album creation"
    try await repository.save([first, second])
    let reopened = ProjectRepository(root: root)
    #expect(try await reopened.loadAlbums() == [album, compilation])
    // Removing one membership leaves the shared track and other album intact.
    album.projectIDs.removeAll { $0 == first.id }
    try await reopened.saveAlbums([album, compilation])
    #expect(try await reopened.load().count == 2)
    #expect(try await reopened.loadAlbums().last?.projectIDs == [first.id])
    // Album deletion does not remove any project.
    try await reopened.saveAlbums([compilation])
    #expect(try await reopened.load().count == 2)
    _ = try await reopened.deleteProject(first.id, existing: [first, second])
    #expect(try await reopened.loadAlbums().first?.projectIDs.isEmpty == true)
    #expect(try await reopened.load().map(\.id) == [second.id])
}

@Test func albumsValidateReferencesAndLoadOlderLibraries() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let index = root.appendingPathComponent("library.json")
    try Data(#"{"schemaVersion":3,"projects":[]}"#.utf8).write(to: index)
    let repository = ProjectRepository(root: root)
    #expect(try await repository.loadAlbums().isEmpty)
    try await repository.saveAlbums([MusicAlbum(name: "Empty album")])
    let saved = try Data(contentsOf: index)
    do {
        try await repository.saveAlbums([MusicAlbum(name: "Bad reference", projectIDs: [UUID()])])
        Issue.record("Unknown project should be rejected")
    } catch {}
    #expect(try Data(contentsOf: index) == saved)
    try Data("broken library".utf8).write(to: index)
    do { try await repository.saveAlbums([]); Issue.record("Corrupt library should be retained") } catch {}
    #expect(try Data(contentsOf: index) == Data("broken library".utf8))
}
