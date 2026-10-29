import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DeadlineCore

struct ProjectDetailView: View {
    @Bindable var model: StudioModel
    let project: MusicProject
    @State private var notes = ""
    @State private var brief = ""
    @State private var spec = DeliverySpec()
    @State private var sourceID: UUID?
    @State private var sourceChosenManually = false
    @State private var scanMessage = "Offline text matching. Review every setting before exporting."
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("PROJECT WORKSPACE").font(.caption.bold()).tracking(2).foregroundStyle(.secondary)
                        Text(project.name).font(.largeTitle.bold())
                        Text(project.artist.isEmpty ? "Independent release" : project.artist).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.importFiles() } label: { Label("Add files", systemImage: "plus") }.disabled(model.busy).buttonStyle(.borderedProminent)
                }
                if let issue = model.folderRefreshIssues[project.id] {
                    Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                SpotlightView(model: model, project: project)
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 20) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Project files · \(project.assets.count)").font(.headline)
                                Text("Linked audio and documents. Keep original files in place and their drive connected.").font(.caption).foregroundStyle(.secondary)
                                if project.assets.isEmpty {
                                    ContentUnavailableView("Bring your files together", systemImage: "folder.badge.plus", description: Text("Add files to keep them with this project."))
                                }
                                ForEach(project.assets) { asset in
                                    HStack {
                                        Image(systemName: asset.isDirectory == true ? "folder" : (asset.isAudio ? "waveform" : "doc"))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(asset.name).lineLimit(2)
                                            Text(ByteCountFormatter.string(fromByteCount: asset.byteCount, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if asset.isAudio {
                                            Button { model.play(asset, projectID: project.id) } label: { Image(systemName: model.playingID == asset.id ? "stop.fill" : "play.fill") }.help("Play or stop audio")
                                        }
                                        Button { NSWorkspace.shared.activateFileViewerSelecting([model.fileURL(asset, projectID: project.id)]) } label: { Image(systemName: "folder") }.help("Reveal file in Finder")
                                    }
                                    .onDrag {
                                        guard asset.isAudio else { return NSItemProvider() }
                                        return NSItemProvider(object: "\(project.id.uuidString)/\(asset.id.uuidString)" as NSString)
                                    }
                                    .contextMenu {
                                        if asset.isAudio {
                                            Button("Pin as final master") { Task { await model.pinMaster(asset.id, projectID: project.id) } }.disabled(model.busy)
                                        }
                                    }
                                    Divider()
                                }
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        GroupBox("Project notes") {
                            VStack(alignment: .trailing) {
                                TextEditor(text: $notes).frame(minHeight: 150).font(.body)
                                Button(notes == project.notes ? "Notes saved" : "Save notes") { Task { await model.saveNotes(notes, id: project.id) } }.disabled(model.busy || notes == project.notes)
                            }.padding(8)
                        }
                        Text("Notes save when you press Save notes. Keep originals and back up your library.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                    delivery.frame(width: 350)
                }
            }.padding(28)
        }
        .onAppear {
            notes = project.notes; spec.artist = project.artist; spec.title = project.name
            if !sourceChosenManually { sourceID = spotlightSourceID }
        }
        .onChange(of: project.assets) { _, assets in
            if let sourceID, !assets.contains(where: { $0.id == sourceID && $0.isAudio }) {
                sourceChosenManually = false
                self.sourceID = spotlightSourceID
            }
        }
        .onChange(of: project.spotlightAssetID) { _, _ in
            if !sourceChosenManually { sourceID = spotlightSourceID }
        }
    }
    private var spotlightSourceID: UUID? {
        project.assets.first { $0.id == project.spotlightAssetID && $0.isAudio }?.id
    }
    private var delivery: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("THE HANDOFF").font(.caption.bold()).tracking(2).foregroundStyle(.secondary)
                Text("Prepare deliverables").font(.title2.bold())
                Text("Paste the delivery brief, then check the extracted settings.").foregroundStyle(.secondary)
                TextEditor(text: $brief).frame(height: 100).font(.body).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .accessibilityLabel("Delivery brief")
                HStack {
                    Button("Import .txt") { importBrief() }
                    Spacer()
                    Button("Extract specs") { scan() }.disabled(brief.isEmpty)
                }
                Text(scanMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                Picker("Source", selection: Binding(get: { sourceID }, set: {
                    sourceID = $0
                    sourceChosenManually = true
                })) {
                    Text("Choose a mix or master").tag(nil as UUID?)
                    ForEach(project.assets.filter(\.isAudio)) { Text($0.name).tag(Optional($0.id)) }
                }
                LabeledContent("Format", value: "WAV · Integer PCM")
                Picker("Bit depth", selection: $spec.bitDepth) { Text("16-bit").tag(16); Text("24-bit").tag(24) }
                Picker("Sample rate", selection: $spec.sampleRate) { Text("44.1 kHz").tag(44_100.0); Text("48 kHz").tag(48_000.0); Text("96 kHz").tag(96_000.0) }
                Picker("Channels", selection: $spec.channels) { Text("Stereo").tag(2); Text("Mono (downmix)").tag(1) }
                TextField("Artist metadata", text: $spec.artist).textFieldStyle(.roundedBorder)
                TextField("Track title metadata", text: $spec.title).textFieldStyle(.roundedBorder)
                Text("Artist and title are written as WAV INFO tags. No mastering, loudness normalization, or dither. MP3/FLAC output and PDF briefs are not supported yet.").font(.caption).foregroundStyle(.secondary)
                Button {
                    if let asset = project.assets.first(where: { $0.id == sourceID }) { model.export(asset, projectID: project.id, spec: spec) }
                } label: { Label("Convert & save WAV", systemImage: "arrow.down.doc").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(sourceID == nil || model.busy)
            }.padding(12)
        }
    }
    private func scan() {
        let result = BriefParser.parse(brief, base: spec); spec = result.spec
        scanMessage = (result.detected.isEmpty ? "No supported specs detected." : "Detected: " + result.detected.joined(separator: ", ") + ".") + "\n" + result.warnings.joined(separator: "\n")
    }
    private func importBrief() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { brief = try String(contentsOf: url, encoding: .utf8); scan() }
        catch { model.error = "Could not read UTF-8 text: \(error.localizedDescription)" }
    }
}
