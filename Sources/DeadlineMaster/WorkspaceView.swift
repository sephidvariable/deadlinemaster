import SwiftUI
import AppKit
import DeadlineCore

private let lime = Color(red: 0.85, green: 0.93, blue: 0.62)
private let statusBarHeight: CGFloat = 34

struct WorkspaceView: View {
    @Bindable var model: StudioModel
    @State private var creating = false
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
                Button { creating = true } label: { Label("New project", systemImage: "plus") }
                    .disabled(!model.ready || model.busy)
            }
        }
        .sheet(isPresented: $creating) { NewProjectView(model: model) }
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
                Text("Project library · \(model.filtered.count)").font(.headline)
                if model.filtered.isEmpty {
                    ContentUnavailableView {
                        Label(model.projects.isEmpty ? "Your next release starts here" : "No matching projects", systemImage: "waveform")
                    } description: { Text("Create a project and import your mixes, sessions, and artwork.") }
                    actions: { Button("Create project") { creating = true }.disabled(!model.ready || model.busy) }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230))], spacing: 18) {
                        ForEach(model.filtered) { project in
                            Button { model.selectedID = project.id } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(systemName: "waveform").font(.system(size: 52, weight: .light)).frame(maxWidth: .infinity).frame(height: 100).background(lime.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                                    Text(project.name).font(.headline).lineLimit(2)
                                    Text(project.artist.isEmpty ? "Independent release" : project.artist).foregroundStyle(.secondary)
                                    HStack { Text("\(project.assets.count) files"); Spacer(); Text(project.createdAt, style: .date) }.font(.caption).foregroundStyle(.secondary)
                                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("A fresh start").font(.caption).foregroundStyle(.secondary)
            Text("New project").font(.largeTitle.bold())
            TextField("Project name", text: $name)
            TextField("Artist or band", text: $artist)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Create project") { Task { await model.create(name: name, artist: artist); if model.error == nil { dismiss() } } }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy) }
        }.textFieldStyle(.roundedBorder).padding(30).frame(width: 420)
    }
}
