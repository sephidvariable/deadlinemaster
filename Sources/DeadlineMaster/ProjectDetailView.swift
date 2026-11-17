import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DeadlineCore
import DeadlineDocuments

struct ProjectDetailView: View {
    @Bindable var model: StudioModel
    let project: MusicProject
    @State private var notes = ""
    @State private var brief = ""
    @State private var spec = DeliverySpec()
    @State private var deliveries: [HandoffItem] = []
    @State private var editingID: UUID?
    @State private var showDitherExplanation = false
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
                SpotlightView(model: model, project: project, premaster: true)
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 20) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Project files · \(project.assets.count)").font(.headline)
                                Text("Original audio and documents · File list refreshed at app launch.").font(.caption).foregroundStyle(.secondary)
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
                                            Button("Pin as premaster 2mix") { Task { await model.pinMaster(asset.id, projectID: project.id, premaster: true) } }.disabled(model.busy)
                                            Button("Pin as final master") { Task { await model.pinMaster(asset.id, projectID: project.id) } }.disabled(model.busy)
                                        }
                                    }
                                    if model.playingID == asset.id { PlaybackProgressView(model: model) }
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
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button {
                    model.stop()
                    model.selectedID = nil
                } label: {
                    Label("Back to Your projects", systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
                .help("Return to Your projects")
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(.bar)
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
                Text("One version per line: include a source filename, sample rate and bit depth. Review each version before export.").foregroundStyle(.secondary)
                TextEditor(text: $brief).frame(height: 100).font(.body).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .accessibilityLabel("Delivery brief")
                HStack {
                    Button("Import document") { importBrief() }
                    Spacer()
                    Button("Add from brief") { scan() }.disabled(brief.isEmpty)
                }
                Text(scanMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                if !deliveries.isEmpty { deliveryList }
                Text(editingID == nil ? "New version" : "Edit version").font(.headline)
                Picker("Source", selection: Binding(get: { sourceID }, set: {
                    sourceID = $0
                    sourceChosenManually = true
                })) {
                    Text("Choose a mix or master").tag(nil as UUID?)
                    ForEach(project.assets.filter(\.isAudio)) { Text($0.name).tag(Optional($0.id)) }
                }
                LabeledContent("Format", value: spec.bitDepth == 32 ? "WAV · 32-bit floating point" : "WAV · Integer PCM")
                HStack {
                    Picker("Bit depth", selection: $spec.bitDepth) { Text("16-bit").tag(16); Text("24-bit").tag(24); Text("32-bit float").tag(32) }
                    Button { showDitherExplanation = true } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain)
                        .help("why can't I choose dithering algorithms?")
                        .accessibilityLabel("why can't I choose dithering algorithms?")
                        .popover(isPresented: $showDitherExplanation) {
                            Text("Deadline Master only allows TPDF white noise dithering. It is true that noise-shaping algorithms may be superior, but remember: your audio will be normalised again for streaming platforms, get compressed when being uploaded to YouTube, or event get shamelessly ripped into 96kbps bootleg MP3 files by random internet strangers. These are all scenarios when noise-shaping may cause more trouble than it solves.")
                                .padding(20).frame(width: 360).fixedSize(horizontal: false, vertical: true)
                        }
                }
                Picker("Sample rate", selection: $spec.sampleRate) { Text("44.1 kHz").tag(44_100.0); Text("48 kHz").tag(48_000.0); Text("96 kHz").tag(96_000.0); Text("192 kHz").tag(192_000.0) }
                Picker("Channels", selection: $spec.channels) { Text("Stereo").tag(2); Text("Mono (downmix)").tag(1) }
                TextField("Artist metadata", text: $spec.artist).textFieldStyle(.roundedBorder)
                TextField("Track title metadata", text: $spec.title).textFieldStyle(.roundedBorder)
                Text("FFmpeg converts locally using SoX resampling. Artist and title are written as WAV INFO tags. TPDF dither is applied when reducing source bit depth or converting float to integer, after any resampling. Resampling alone does not add dither. Matching formats bypass processing. No mastering or loudness normalization. MP3/FLAC output is not supported yet.").font(.caption).foregroundStyle(.secondary)
                Button {
                    if let editingID, let index = deliveries.firstIndex(where: { $0.id == editingID }) {
                        deliveries[index].sourceID = sourceID; deliveries[index].spec = spec
                    } else { deliveries.append(HandoffItem(sourceID: sourceID, spec: spec)) }
                    editingID = nil
                } label: { Label(editingID == nil ? "Add version" : "Save version", systemImage: "plus.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(sourceID == nil || model.busy)
                if editingID != nil {
                    Button("Cancel edit") { editingID = nil }
                }
            }.padding(12).disabled(model.busy)
        }
    }
    private var deliveryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delivery list · \(deliveries.count)").font(.headline)
            ForEach(deliveries) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.assets.first(where: { $0.id == item.sourceID })?.name ?? "Choose a source").font(.subheadline.bold()).lineLimit(2)
                    Text("\(item.spec.sampleRate / 1000, specifier: "%g") kHz · \(item.spec.bitDepth)-bit\(item.spec.bitDepth == 32 ? " float" : "") · \(item.spec.channels == 1 ? "Mono" : "Stereo")").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Edit") { editingID = item.id; sourceID = item.sourceID; sourceChosenManually = true; spec = item.spec }
                        Button("Export WAV") {
                            if let asset = project.assets.first(where: { $0.id == item.sourceID }) { model.export(asset, projectID: project.id, spec: item.spec) }
                        }.disabled(!project.assets.contains(where: { $0.id == item.sourceID && $0.isAudio }) || editingID != nil)
                        Spacer()
                        Button { deliveries.removeAll { $0.id == item.id }; if editingID == item.id { editingID = nil } } label: { Image(systemName: "trash") }.help("Remove version from delivery list")
                    }
                }
                Divider()
            }
            Button { model.exportBatch(deliveries, project: project, zip: false) } label: {
                Label("Export all as WAV files", systemImage: "folder").frame(maxWidth: .infinity)
            }.disabled(!canExportBatch)
            Button { model.exportBatch(deliveries, project: project, zip: true) } label: {
                Label("Export all as ZIP", systemImage: "archivebox").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(!canExportBatch)
            Text("Separate WAVs go into a new folder. Save any edits before exporting. This delivery list lasts while the workspace is open.").font(.caption).foregroundStyle(.secondary)
            Divider()
        }
    }
    private var canExportBatch: Bool {
        editingID == nil && !deliveries.isEmpty && deliveries.allSatisfy { item in project.assets.contains { $0.id == item.sourceID && $0.isAudio } }
    }
    private func scan() {
        let result = HandoffBriefParser.parse(brief, assets: project.assets, defaultSource: sourceID, base: spec)
        deliveries += result.items
        scanMessage = "Added \(result.items.count) versions. Review sources and settings.\n" + result.warnings.joined(separator: "\n")
    }
    private func importBrief() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = BriefDocumentReader.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = "Import a text, Word, Pages or PDF brief. Pages files require Apple Pages; scanned PDFs use offline OCR."
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.busy = true; model.status = "Reading delivery brief… Scanned PDFs may take longer."
        Task {
            defer { model.busy = false }
            do {
                let result: BriefDocumentText
                do {
                    result = try await Task.detached(priority: .userInitiated) { try BriefDocumentReader.read(url) }.value
                } catch BriefDocumentError.passwordRequired {
                    let alert = NSAlert(); alert.messageText = "PDF password required"
                    alert.informativeText = "Enter the password to read this brief. It will not be saved."
                    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
                    alert.accessoryView = field; alert.addButton(withTitle: "Unlock"); alert.addButton(withTitle: "Cancel")
                    alert.window.initialFirstResponder = field
                    guard alert.runModal() == .alertFirstButtonReturn else { model.status = "Brief import cancelled."; return }
                    let password = field.stringValue
                    result = try await Task.detached(priority: .userInitiated) { try BriefDocumentReader.read(url, password: password) }.value
                }
                brief = result.text; scanMessage = result.notes
                model.status = "Brief imported. Review the text, then choose Add from brief."
            } catch {
                model.error = error.localizedDescription
                model.status = "Brief import failed. Your existing brief and delivery list are unchanged."
            }
        }
    }
}
