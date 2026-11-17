import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import DeadlineCore
import DeadlineAudio

@MainActor @Observable
final class StudioModel {
    var projects: [MusicProject] = []
    var albums: [MusicAlbum] = []
    var selectedID: UUID?
    var search = ""
    var busy = false
    var ready = false
    var error: String?
    var status = ""
    var playingID: UUID?
    var folderRefreshIssues: [UUID: String] = [:]
    private var player: AVAudioPlayer?
    let repository: ProjectRepository
    let libraryURL: URL
    var selected: MusicProject? { projects.first { $0.id == selectedID } }
    var filtered: [MusicProject] {
        projects.filter { search.isEmpty || ($0.name + " " + $0.artist).localizedCaseInsensitiveContains(search) }
    }
    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Override is useful for isolated development and UI smoke tests; normal users use Application Support.
        libraryURL = ProcessInfo.processInfo.environment["DEADLINE_MASTER_LIBRARY"].map { URL(fileURLWithPath: $0) }
            ?? support.appendingPathComponent("Deadline Master", isDirectory: true)
        repository = ProjectRepository(root: libraryURL)
    }
    func load() async {
        do { projects = try await repository.load(); albums = try await repository.loadAlbums(); ready = true }
        catch { self.error = "Could not read the library. No data has been overwritten. \(error.localizedDescription)" }
    }
    private var refreshedAtLaunch = false
    func refreshFoldersAtLaunch() async {
        guard ready, !refreshedAtLaunch else { return }
        refreshedAtLaunch = true
        busy = true
        defer { busy = false }
        for id in projects.filter({ $0.sourceFolderPath != nil }).map(\.id) {
            do {
                projects = try await repository.refreshProject(id, existing: projects)
                folderRefreshIssues[id] = nil
            } catch {
                folderRefreshIssues[id] = "Launch scan failed: " + error.localizedDescription + ". Reopen the app after restoring access."
            }
        }
    }
    func create(name: String, artist: String, folder: URL) async {
        guard ready, !busy else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        busy = true; defer { busy = false }
        let project = MusicProject(name: name, artist: artist)
        error = nil
        status = "Reading project folder…"
        do {
            let imported = try await repository.createFromFolder(folder, project: project, existing: projects)
            projects = [imported] + projects
            selectedID = imported.id
            status = "Project created with \(imported.assets.count) files and folders."
        }
        catch { self.error = error.localizedDescription }
    }
    func saveNotes(_ notes: String, id: UUID) async {
        guard ready, !busy, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        busy = true; defer { busy = false }
        var next = projects; next[index].notes = notes
        do { try await repository.save(next); projects = next; status = "Notes saved." }
        catch { self.error = error.localizedDescription }
    }

    func deleteProject(_ project: MusicProject) {
        guard ready, !busy else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(project.name)”?"
        alert.informativeText = "Remove this project and its notes from the library. No original files or folders will be changed or deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete project")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        busy = true
        Task {
            defer { busy = false }
            let next = projects.filter { $0.id != project.id }
            do {
                let cleanupWarning = try await repository.deleteProject(project.id, existing: projects)
                stop()
                projects = next
                albums = albums.map { album in var updated = album; updated.projectIDs.removeAll { $0 == project.id }; return updated }
                folderRefreshIssues[project.id] = nil
                if selectedID == project.id { selectedID = nil }
                status = cleanupWarning ?? "Project removed from the library. Original files are untouched."
            } catch { self.error = error.localizedDescription }
        }
    }
    func chooseCover(for owner: CoverOwner) {
        guard ready, !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a cover between 9:16 and 2.39:1. Any image resolution is accepted."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        updateCover(source, for: owner)
    }
    func updateCover(_ source: URL?, for owner: CoverOwner) {
        guard ready, !busy else { return }
        busy = true; status = source == nil ? "Removing cover…" : "Importing cover…"
        Task {
            defer { busy = false }
            do {
                try await repository.setCover(from: source, for: owner)
                projects = try await repository.load(); albums = try await repository.loadAlbums()
                status = source == nil ? "Cover removed. Original image retained." : "Cover saved."
            } catch { self.error = error.localizedDescription; status = "Cover unchanged." }
        }
    }
    func saveAlbum(_ album: MusicAlbum) async -> Bool {
        guard ready, !busy else { return false }
        busy = true; defer { busy = false }
        var next = albums
        if let index = next.firstIndex(where: { $0.id == album.id }) { next[index] = album }
        else { next.append(album) }
        do {
            try await repository.saveAlbums(next); albums = next; status = "Album saved."; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func deleteAlbum(_ album: MusicAlbum) {
        guard ready, !busy else { return }
        let alert = NSAlert(); alert.messageText = "Delete “\(album.name)”?"
        alert.informativeText = "Only this album grouping will be removed. Its projects and original files will remain."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete album")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        busy = true
        Task {
            defer { busy = false }
            let next = albums.filter { $0.id != album.id }
            do { try await repository.saveAlbums(next); albums = next; status = "Album deleted. Projects retained." }
            catch { self.error = error.localizedDescription }
        }
    }
    func removeTrack(_ projectID: UUID, from album: MusicAlbum) async {
        var updated = album; updated.projectIDs.removeAll { $0 == projectID }
        _ = await saveAlbum(updated)
    }
    func pinMaster(_ assetID: UUID?, projectID: UUID, premaster: Bool = false) async {
        guard ready, !busy, let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard assetID == nil || projects[index].assets.contains(where: { $0.id == assetID && $0.isAudio }) else { return }
        busy = true; defer { busy = false }
        var next = projects
        if premaster { next[index].premasterAssetID = assetID }
        else { next[index].spotlightAssetID = assetID }
        do {
            try await repository.save(next)
            projects = next
            status = assetID == nil ? "Spotlight cleared." : (premaster ? "Premaster 2mix pinned." : "Final master pinned.")
        } catch { self.error = error.localizedDescription }
    }
    func importFiles() {
        guard ready, !busy, let projectID = selectedID else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = (ImportFileTypes.audio + ImportFileTypes.documents).compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose audio or document files to read from their original location."
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        busy = true
        Task {
            defer { busy = false }
            for url in urls {
                do {
                    let asset = try await repository.importFile(url, projectID: projectID)
                    guard let index = projects.firstIndex(where: { $0.id == projectID }) else { continue }
                    var next = projects; next[index].assets.append(asset)
                    try await repository.save(next); projects = next
                } catch { self.error = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"; break }
            }
        }
    }
    func fileURL(_ asset: ProjectAsset, projectID: UUID) -> URL { repository.fileURL(asset, projectID: projectID) }
    func play(_ asset: ProjectAsset, projectID: UUID) {
        if playingID == asset.id { stop(); return }
        stop()
        do { player = try AVAudioPlayer(contentsOf: repository.availableFileURL(asset, projectID: projectID)); player?.play(); playingID = asset.id }
        catch { self.error = "Playback unavailable: \(error.localizedDescription)" }
    }
    var playbackProgress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return min(1, max(0, player.currentTime / player.duration))
    }
    func seekPlayback(to fraction: Double) {
        guard fraction.isFinite, let player, player.duration > 0 else { return }
        player.currentTime = min(1, max(0, fraction)) * player.duration
        // A seek after natural completion should start previewing again.
        if fraction < 1 && !player.isPlaying { player.play() }
    }
    func stop() { player?.stop(); player = nil; playingID = nil }
    func exportBatch(_ items: [HandoffItem], project: MusicProject, zip: Bool) {
        guard !busy, !items.isEmpty else { return }
        let exports: [BatchExportItem]
        do {
            exports = try items.map { item in
                guard let asset = project.assets.first(where: { $0.id == item.sourceID && $0.isAudio }) else {
                    throw StudioError.message("Choose an available audio source for every version.")
                }
                return BatchExportItem(source: try repository.availableFileURL(asset, projectID: project.id), spec: item.spec)
            }
        } catch { self.error = error.localizedDescription; return }
        let destination: URL
        if zip {
            let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]
            panel.nameFieldStringValue = project.name.replacingOccurrences(of: "/", with: "-") + " Deliverables.zip"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destination = url
        } else {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.prompt = "Export here"; panel.message = "A new Deliverables folder will be created here."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let stem = project.name.replacingOccurrences(of: "/", with: "-") + " Deliverables"
            var candidate = url.appendingPathComponent(stem, isDirectory: true)
            var suffix = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = url.appendingPathComponent("\(stem) \(suffix)", isDirectory: true); suffix += 1
            }
            destination = candidate
        }
        busy = true; status = "Preparing \(exports.count) delivery versions…"
        Task {
            defer { busy = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BatchExporter.export(exports, destination: destination, zip: zip)
                }.value
                status = "Exported \(exports.count) versions: \(destination.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { self.error = error.localizedDescription; status = "Batch export failed. Originals are unchanged." }
        }
    }
    func export(_ asset: ProjectAsset, projectID: UUID, spec: DeliverySpec) {
        guard !busy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]
        let title = spec.title.isEmpty ? "Deliverable" : spec.title
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + "_\(Int(spec.sampleRate))_\(spec.bitDepth)bit.wav"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let source: URL
        do { source = try repository.availableFileURL(asset, projectID: projectID) }
        catch { self.error = error.localizedDescription; return }
        busy = true; status = "Converting audio on your Mac…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try AudioExporter.export(source: source, destination: destination, spec: spec)
                }.value
                status = "Export complete: \(destination.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { self.error = error.localizedDescription; status = "Export failed. Your source is unchanged." }
            busy = false
        }
    }
}
