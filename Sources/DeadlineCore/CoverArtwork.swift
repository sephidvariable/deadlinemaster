import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct CoverArtwork: Codable, Equatable, Sendable {
    public var id: UUID
    public var width: Int
    public var height: Int
}

public enum CoverOwner: Sendable { case project(UUID), album(UUID) }

public enum CoverImage {
    /// Uses displayed orientation. No minimum/maximum pixel dimensions or file-size policy.
    public static func dimensions(at url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int,
              let h = properties[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else {
            throw StudioError.message("Choose a readable image file.")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let width = (5...8).contains(orientation) ? h : w
        let height = (5...8).contains(orientation) ? w : h
        let ratio = Double(width) / Double(height)
        guard ratio >= 9.0 / 16.0, ratio <= 2.39 else {
            throw StudioError.message("Cover aspect ratio must be between 9:16 and 2.39:1. This image is \(width) × \(height). There is no resolution limit.")
        }
        return (width, height)
    }
    public static func writeThumbnail(from url: URL, to destination: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw StudioError.message("This image could not be decoded as a cover. Try another image format.")
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw StudioError.message("Could not save the cover preview.") }
    }
}
