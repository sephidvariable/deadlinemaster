import SwiftUI
import AppKit
import DeadlineCore

struct CoverArtworkView: View {
    let model: StudioModel
    let cover: CoverArtwork?
    let symbol: String
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.10))
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(2)
                    .accessibilityLabel("Cover artwork")
            } else {
                Image(systemName: symbol).font(.system(size: 52, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: cover?.id) {
            image = nil
            guard let cover else { return }
            let url = model.repository.coverThumbnailURL(cover)
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            guard !Task.isCancelled, let data else { return }
            image = NSImage(data: data)
        }
    }
}
