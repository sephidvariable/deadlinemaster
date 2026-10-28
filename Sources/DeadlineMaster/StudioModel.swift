import SwiftUI
import AppKit
import AVFoundation
import DeadlineCore
import DeadlineAudio

@MainActor @Observable
final class StudioModel {
    var projects: [MusicProject] = []
    var selectedID: UUID?
    var search = ""
    var busy = false
    var ready = false
    var error: String?
    var status = ""
    var playingID: UUID?
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
        do { projects = try await repository.load(); ready = true }
        catch { self.error = "Could not read the library. No data has been overwritten. \(error.localizedDescription)" }
    }
    func create(name: String, artist: String) async {
        guard ready, !busy else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        busy = true; defer { busy = false }
        let project = MusicProject(name: name, artist: artist)
        let next = [project] + projects
        do { try await repository.save(next); projects = next; selectedID = project.id }
        catch { self.error = error.localizedDescription }
    }
    func saveNotes(_ notes: String, id: UUID) async {
        guard ready, !busy, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        busy = true; defer { busy = false }
        var next = projects; next[index].notes = notes
        do { try await repository.save(next); projects = next; status = "Notes saved." }
        catch { self.error = error.localizedDescription }
    }
    func importFiles() {
        guard ready, !busy, let projectID = selectedID else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.message = "Files are copied into your local library. Zip package-based DAW sessions first."
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
        do { player = try AVAudioPlayer(contentsOf: fileURL(asset, projectID: projectID)); player?.play(); playingID = asset.id }
        catch { self.error = "Playback unavailable: \(error.localizedDescription)" }
    }
    func stop() { player?.stop(); player = nil; playingID = nil }
    func export(_ asset: ProjectAsset, projectID: UUID, spec: DeliverySpec) {
        guard !busy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]
        let title = spec.title.isEmpty ? "Deliverable" : spec.title
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + "_\(Int(spec.sampleRate))_\(spec.bitDepth)bit.wav"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let source = fileURL(asset, projectID: projectID)
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
