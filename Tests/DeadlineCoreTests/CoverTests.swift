import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import DeadlineCore

private func coverFixture(_ url: URL, width: Int, height: Int, orientation: Int = 1) throws {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
}

@Test func coversRespectInclusiveRatioLimitsAndOrientation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for (width, height, orientation, accepted) in [(1, 1, 1, true), (9, 16, 1, true), (239, 100, 1, true), (8, 16, 1, false), (240, 100, 1, false), (100, 239, 6, true), (239, 100, 6, false), (4096, 4096, 1, true)] {
        let source = root.appendingPathComponent("image.tiff")
        try coverFixture(source, width: width, height: height, orientation: orientation)
        if accepted {
            let size = try CoverImage.dimensions(at: source)
            #expect(size.width == (orientation == 6 ? height : width))
            let thumbnail = root.appendingPathComponent("preview.png")
            try CoverImage.writeThumbnail(from: source, to: thumbnail)
            let decoded = try #require(CGImageSourceCreateWithURL(thumbnail as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
            #expect(max(image.width, image.height) <= 1200)
        } else { #expect(throws: (any Error).self) { try CoverImage.dimensions(at: source) } }
    }
}

@Test func coversPersistReplaceSafelyAndNeverDeleteOriginals() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("original.tiff")
    try coverFixture(source, width: 9, height: 16)
    let original = try Data(contentsOf: source)
    let repository = ProjectRepository(root: root.appendingPathComponent("library"))
    let project = MusicProject(name: "Single")
    let album = MusicAlbum(name: "Album", projectIDs: [project.id])
    try await repository.save([project]); try await repository.saveAlbums([album])
    try await repository.setCover(from: source, for: .project(project.id))
    try await repository.setCover(from: source, for: .album(album.id))
    let stored = try #require(try await repository.load().first?.cover)
    let albumCover = try #require(try await repository.loadAlbums().first?.cover)
    #expect(stored.id != albumCover.id)
    #expect(FileManager.default.fileExists(atPath: repository.coverThumbnailURL(stored).path))
    let bad = root.appendingPathComponent("wide.tiff"); try coverFixture(bad, width: 300, height: 100)
    do { try await repository.setCover(from: bad, for: .project(project.id)); Issue.record("Invalid ratio accepted") } catch {}
    #expect(try await repository.load().first?.cover == stored)
    // Successful replacement removes only the old owned artwork.
    try await repository.setCover(from: source, for: .project(project.id))
    #expect(!FileManager.default.fileExists(atPath: repository.coverThumbnailURL(stored).path))
    let replacement = try #require(try await repository.load().first?.cover)
    let reopened = ProjectRepository(root: root.appendingPathComponent("library"))
    #expect(try await reopened.load().first?.cover == replacement)
    try await reopened.setCover(from: nil, for: .project(project.id))
    #expect(try await reopened.load().first?.cover == nil)
    #expect(!FileManager.default.fileExists(atPath: repository.coverThumbnailURL(replacement).path))
    #expect(FileManager.default.fileExists(atPath: repository.coverThumbnailURL(albumCover).path))
    try await reopened.saveAlbums([])
    #expect(!FileManager.default.fileExists(atPath: repository.coverThumbnailURL(albumCover).path))
    #expect(try Data(contentsOf: source) == original)
}
