import SwiftUI
import AppKit
import DeadlineCore

/// Header and footer have fixed content height; only the project list consumes spare space.
struct WorkspaceSidebar: View {
    @Bindable var model: StudioModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color(red: 0.85, green: 0.93, blue: 0.62))
                        .padding(9)
                        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    Text("Deadline\nMaster").font(.title2.bold())
                }.padding(.top, 14)
                Label("Your studio", systemImage: "music.note.house").font(.headline)
                Button { model.selectedID = nil; model.stop() } label: {
                    Label("All projects · \(model.projects.count)", systemImage: "square.grid.2x2")
                }.buttonStyle(.bordered)
                TextField("Search projects", text: $model.search).textFieldStyle(.roundedBorder)
            }
            .padding(18)
            .fixedSize(horizontal: false, vertical: true)

            List(selection: $model.selectedID) {
                ForEach(model.filtered) { project in
                    Label(project.name, systemImage: "waveform").tag(project.id)
                        .contextMenu {
                            Button("Delete project…", role: .destructive) { model.deleteProject(project) }.disabled(model.busy)
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 0, maxHeight: .infinity)
            .layoutPriority(-1)

            VStack(alignment: .leading, spacing: 16) {
                Text("Less file hunting.\nMore music making.")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Offline · On this Mac", systemImage: "internaldrive")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show library in Finder") { NSWorkspace.shared.open(model.libraryURL) }
                    .font(.caption).buttonStyle(.bordered)
            }
            .padding(18)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(white: 0.96))
    }
}
