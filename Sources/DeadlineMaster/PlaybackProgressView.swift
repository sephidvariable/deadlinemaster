import SwiftUI

struct PlaybackProgressView: View {
    let model: StudioModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            Slider(value: Binding(
                get: { model.playbackProgress },
                set: { model.seekPlayback(to: $0) }
            ), in: 0...1)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(Int(model.playbackProgress * 100)) percent")
                .help("Drag to preview a different part of the audio")
        }
    }
}
