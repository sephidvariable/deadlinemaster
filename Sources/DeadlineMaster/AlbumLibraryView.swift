import SwiftUI
import DeadlineCore

struct AlbumLibraryView: View {
    @Bindable var model: StudioModel
    @State private var editing: MusicAlbum?
    private var visibleAlbums: [MusicAlbum] {
        model.albums.filter { album in
            model.search.isEmpty || album.name.localizedCaseInsensitiveContains(model.search) ||
            model.filtered.contains { album.projectIDs.contains($0.id) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Albums · \(model.albums.count)").font(.headline)
                Spacer()
                Button { editing = MusicAlbum(name: "") } label: { Label("New album", systemImage: "plus") }
                    .disabled(!model.ready || model.busy)
            }
            if model.albums.isEmpty {
                Text("Group your singles into albums. A track can belong to more than one album.").foregroundStyle(.secondary)
            } else if visibleAlbums.isEmpty {
                Text("No matching albums.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(visibleAlbums) { album in
                    AlbumCard(model: model, album: album) { editing = album }
                }
            }
        }
        .sheet(item: $editing) { album in AlbumEditorView(model: model, album: album) }
    }
}

private struct AlbumCard: View {
    @Bindable var model: StudioModel
    let album: MusicAlbum
    let edit: () -> Void
    @State private var expanded = false
    private var tracks: [MusicProject] {
        album.projectIDs.compactMap { id in model.projects.first { $0.id == id } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CoverArtworkView(model: model, cover: album.cover, symbol: "square.stack")
            HStack(alignment: .top) {
                Image(systemName: "square.stack").font(.largeTitle).foregroundStyle(.secondary)
                Text(album.name).font(.title3.bold()).lineLimit(3)
                Spacer()
                Menu {
                    Button(album.cover == nil ? "Add cover…" : "Replace cover…") { model.chooseCover(for: .album(album.id)) }
                    if album.cover != nil { Button("Remove cover", role: .destructive) { model.updateCover(nil, for: .album(album.id)) } }
                    Button("Edit album / manage tracks…", action: edit)
                    Button("Delete album…", role: .destructive) { model.deleteAlbum(album) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
                .accessibilityLabel("Actions for \(album.name)")
            }
            DisclosureGroup("\(tracks.count) \(tracks.count == 1 ? "track" : "tracks")", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if tracks.isEmpty { Text("No tracks yet. Add singles from your project library.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(tracks) { track in
                        HStack {
                            Button { model.selectedID = track.id } label: {
                                Label(track.name, systemImage: "waveform").lineLimit(2).multilineTextAlignment(.leading)
                            }.buttonStyle(.plain)
                            Spacer()
                            Button { Task { await model.removeTrack(track.id, from: album) } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).disabled(model.busy)
                                .help("Remove from this album")
                                .accessibilityLabel("Remove \(track.name) from \(album.name)")
                        }
                    }
                }.padding(.top, 10)
            }
            Button("Manage tracks…", action: edit).disabled(model.busy)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}

private struct AlbumEditorView: View {
    @Bindable var model: StudioModel
    let album: MusicAlbum
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selected: Set<UUID>
    @State private var search = ""
    @State private var saveError: String?
    init(model: StudioModel, album: MusicAlbum) {
        self.model = model; self.album = album
        _name = State(initialValue: album.name)
        _selected = State(initialValue: Set(album.projectIDs))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.albums.contains(where: { $0.id == album.id }) ? "Edit album" : "New album").font(.title.bold())
            TextField("Album name", text: $name).textFieldStyle(.roundedBorder)
            Text("Select singles from your project library. They can also belong to other albums.").foregroundStyle(.secondary)
            TextField("Find tracks", text: $search).textFieldStyle(.roundedBorder)
            List {
                ForEach(model.projects.filter { search.isEmpty || ($0.name + " " + $0.artist).localizedCaseInsensitiveContains(search) }) { project in
                    Toggle(isOn: Binding(get: { selected.contains(project.id) }, set: { included in
                        if included { selected.insert(project.id) } else { selected.remove(project.id) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(project.name)
                            if !project.artist.isEmpty { Text(project.artist).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.toggleStyle(.checkbox)
                }
            }.frame(height: 260)
            if model.projects.isEmpty { Text("Create projects first, or save an empty album and add tracks later.").font(.caption) }
            if let saveError { Text(saveError).foregroundStyle(.red).font(.caption) }
            HStack {
                Text("\(selected.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save album") {
                    Task {
                        // Preserve existing order; append newly selected projects in library order.
                        let ids = album.projectIDs.filter { selected.contains($0) } + model.projects.filter { selected.contains($0.id) && !album.projectIDs.contains($0.id) }.map(\.id)
                        var updated = MusicAlbum(id: album.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), projectIDs: ids)
                        updated.cover = model.albums.first(where: { $0.id == album.id })?.cover
                        if await model.saveAlbum(updated) { dismiss() }
                        else { saveError = model.error ?? "Could not save the album." }
                    }
                }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 470).disabled(model.busy).interactiveDismissDisabled(model.busy)
    }
}
