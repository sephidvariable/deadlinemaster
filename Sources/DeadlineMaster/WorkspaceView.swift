import SwiftUI
import AppKit
import DeadlineCore

private let lime = Color(red: 0.85, green: 0.93, blue: 0.62)
private let statusBarHeight: CGFloat = 34

struct WorkspaceView: View {
    @Bindable var model: StudioModel
    @State private var creating = false
    @State private var batchCreating = false
    @State private var sidebarVisible = true
    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                if sidebarVisible {
                    WorkspaceSidebar(model: model)
                        .frame(minWidth: 215, idealWidth: 240, maxWidth: 240)
                }
                Group {
                    if let project = model.selected { ProjectDetailView(model: model, project: project).id(project.id) }
                    else { library }
                }
                .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.caption).lineLimit(1).help(model.status)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: statusBarHeight)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
                    .accessibilityLabel(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }
            ToolbarItem {
                Menu {
                    Button("Add project…") { creating = true }
                    Button("Add projects from folder…") { batchCreating = true }
                } label: { Label("Add projects", systemImage: "plus") }
                    .help("Add one project or find projects in a folder")
                    .disabled(!model.ready || model.busy)
            }
        }
        .sheet(isPresented: $creating) { NewProjectView(model: model) }
        .sheet(isPresented: $batchCreating) { BatchProjectImportView(model: model) }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: model.selectedID) { _, _ in model.stop() }
    }
    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MAKE ROOM FOR YOUR MUSIC").font(.caption.bold()).tracking(2).foregroundStyle(.secondary)
                    Text("Your projects.").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("From the first bounce to the final send. All together.").foregroundStyle(.secondary)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("YOUR FINAL BOUNCE, SORTED").font(.caption.bold()).tracking(1)
                        Text("Make the music.\nMaster the deadline.").font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Bring your mixes, paste the brief, and prepare the handoff.")
                    }
                    Spacer()
                    Image(systemName: "opticaldisc").font(.system(size: 130, weight: .ultraLight))
                }.padding(30).foregroundStyle(Color.black.opacity(0.85)).frame(maxWidth: .infinity).background(lime, in: RoundedRectangle(cornerRadius: 18))
                AlbumLibraryView(model: model)
                Text("Project library · \(model.filtered.count)").font(.headline)
                if model.filtered.isEmpty {
                    ContentUnavailableView {
                        Label(model.projects.isEmpty ? "Your next release starts here" : "No matching projects", systemImage: "waveform")
                    } description: { Text("Create a project and import your audio and documents.") }
                    actions: {
                        Button("Create project") { creating = true }.disabled(!model.ready || model.busy)
                        Button("Add projects from folder…") { batchCreating = true }.disabled(!model.ready || model.busy)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230))], spacing: 18) {
                        ForEach(model.filtered) { project in
                            Button { model.selectedID = project.id } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    CoverArtworkView(model: model, cover: project.cover, symbol: "waveform")
                                    Text(project.name).font(.headline).lineLimit(2)
                                    Text(project.artist.isEmpty ? "Independent release" : project.artist).foregroundStyle(.secondary)
                                    HStack { Text("\(project.assets.count) files"); Spacer(); Text(project.createdAt, style: .date) }.font(.caption).foregroundStyle(.secondary)
                                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) {
                                Menu {
                                    Button(project.cover == nil ? "Add cover…" : "Replace cover…") { model.chooseCover(for: .project(project.id)) }
                                    if project.cover != nil { Button("Remove cover", role: .destructive) { model.updateCover(nil, for: .project(project.id)) } }
                                } label: { Image(systemName: "photo.badge.plus").padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6)) }
                                .menuStyle(.borderlessButton).fixedSize().padding(22).disabled(model.busy)
                                .accessibilityLabel("Cover for \(project.name)")
                            }
                            .contextMenu {
                                Button(project.cover == nil ? "Add cover…" : "Replace cover…") { model.chooseCover(for: .project(project.id)) }
                                if project.cover != nil { Button("Remove cover", role: .destructive) { model.updateCover(nil, for: .project(project.id)) } }
                                Button("Delete project…", role: .destructive) { model.deleteProject(project) }.disabled(model.busy)
                            }
                        }
                    }
                }
            }.padding(32)
        }
    }
}

struct NewProjectView: View {
    @Bindable var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var artist = ""
    @State private var folder: URL?
    @State private var scanning = false
    @State private var scanSummary = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("A fresh start").font(.caption).foregroundStyle(.secondary)
            Text("New project").font(.largeTitle.bold())
            Button(folder == nil ? "Choose project folder…" : "Change folder…") { chooseFolder() }.disabled(model.busy || scanning)
            if let folder { Text(folder.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Text("Live Sets, analysis files, production folders and nested Live projects are excluded. Audio and documents are read from their original paths. The file list refreshes when the app launches.").font(.caption).foregroundStyle(.secondary)
            if scanning { ProgressView("Checking folder…") }
            if !scanSummary.isEmpty { Text(scanSummary).font(.caption).foregroundStyle(.secondary) }
            TextField("Project name", text: $name)
            TextField("Artist or band", text: $artist)
            HStack { Spacer(); Button("Cancel") { dismiss() }.disabled(model.busy); Button("Create project") { Task { guard let folder else { return }; await model.create(name: name, artist: artist, folder: folder); if model.error == nil { dismiss() } } }.buttonStyle(.borderedProminent).disabled(scanning || folder == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy) }
                    if model.busy { ProgressView("Importing folder…") }
        }.textFieldStyle(.roundedBorder).padding(30).frame(width: 420)
        .interactiveDismissDisabled(model.busy || scanning)
        .onAppear { chooseFolder() }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose folder"
        if panel.runModal() == .OK, let url = panel.url {
            folder = nil
            name = url.lastPathComponent
            scanSummary = ""
            scanning = true
            Task {
                defer { scanning = false }
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try AbletonFolderScan.scan(url.resolvingSymlinksInPath())
                    }.value
                    if !result.resemblesProject {
                        let alert = NSAlert()
                        alert.messageText = "This doesn’t seem like a project folder"
                        alert.informativeText = "No Ableton Live project structure was found. Look for Live Set (.als) files alongside Ableton Project Info or Samples. You can choose another folder or import this folder anyway."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Choose another folder")
                        alert.addButton(withTitle: "Import anyway")
                        guard alert.runModal() == .alertSecondButtonReturn else { return }
                    }
                    folder = url
                    scanSummary = result.resemblesProject
                        ? "Found \(result.projectPaths.count) Live project folder(s) and \(result.setCount) Live Set file(s). Production material will be excluded."
                        : "Unrecognized folder. Live Set and analysis files will still be excluded."
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Could not scan this folder"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
}
