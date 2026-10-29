import SwiftUI
import AppKit
import DeadlineCore

struct SpotlightView: View {
    @Bindable var model: StudioModel
    let project: MusicProject
    @State private var targeted = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Spotlight · Final master", systemImage: "star.fill").font(.headline)
                if let asset = project.assets.first(where: { $0.id == project.spotlightAssetID && $0.isAudio }) {
                    HStack {
                        Image(systemName: "waveform").font(.largeTitle)
                        Text(asset.name).font(.title3.bold()).lineLimit(2)
                        Spacer()
                        Button { model.play(asset, projectID: project.id) } label: {
                            Label(model.playingID == asset.id ? "Stop" : "Play", systemImage: model.playingID == asset.id ? "stop.fill" : "play.fill")
                        }
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.fileURL(asset, projectID: project.id)]) }
                        Button("Unpin") { Task { await model.pinMaster(nil, projectID: project.id) } }.disabled(model.busy)
                    }
                    Text("Your completed song. Drop another project audio file here to replace it.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Drag your finished master here from Project files.").font(.title3)
                    Text("Or right-click an audio file and choose Pin as final master.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(targeted ? Color.accentColor : Color.clear, lineWidth: 2))
        .dropDestination(for: String.self) { items, _ in
            guard !model.busy, let token = items.first else { return false }
            let parts = token.split(separator: "/")
            guard parts.count == 2, String(parts[0]) == project.id.uuidString,
                  let id = UUID(uuidString: String(parts[1])),
                  project.assets.contains(where: { $0.id == id && $0.isAudio }) else { return false }
            Task { await model.pinMaster(id, projectID: project.id) }
            return true
        } isTargeted: { targeted = $0 }
    }
}
