import SwiftUI
import AppKit
import DeadlineCore

struct BatchProjectImportView: View {
    @Bindable var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var folder: URL?
    @State private var artist = ""
    @State private var choices: [ProjectFolderChoice] = []
    @State private var selected: Set<String> = []
    @State private var issues: [FolderImportIssue] = []
    @State private var scanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var error: String?
    @State private var report: BatchProjectImportResult?

    private var existingPaths: Set<String> {
        Set(model.projects.compactMap { $0.sourceFolderPath }.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        })
    }
    private var pending: [ProjectFolderChoice] {
        choices.filter { selected.contains($0.id) && !existingPaths.contains($0.id) }
    }
    private var canImport: Bool {
        !scanning && !model.busy && !pending.isEmpty
            && pending.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bring your music together").font(.caption).foregroundStyle(.secondary)
            Text(report == nil ? "Add projects from a folder" : "Import complete").font(.title.bold())
            if let report {
                summary(report)
            } else {
                Text("Choose a folder containing your music projects. We’ll search its subfolders for Ableton Live projects. Each project folder becomes one project, even if it contains several Live Sets.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(folder == nil ? "Choose folder…" : "Change folder…", action: chooseFolder)
                        .disabled(scanning || model.busy)
                    if scanning { ProgressView().controlSize(.small); Text("Searching subfolders…").font(.caption) }
                }
                if let folder { Text(folder.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2) }
                TextField("Artist or band for all selected projects", text: $artist).disabled(model.busy)
                    .accessibilityLabel("Artist or band for every imported project")
                if !choices.isEmpty {
                    HStack {
                        Text("\(choices.count) found · \(pending.count) selected").font(.headline)
                        Spacer()
                        Button("Select all") { selected = Set(choices.map(\.id)).subtracting(existingPaths) }
                        Button("Deselect all") { selected = [] }
                    }.disabled(model.busy)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach($choices) { $choice in
                                let alreadyAdded = existingPaths.contains(choice.id)
                                HStack(alignment: .top, spacing: 10) {
                                    Toggle("Add \(choice.folder.lastPathComponent)", isOn: Binding(
                                        get: { selected.contains(choice.id) && !alreadyAdded },
                                        set: { if $0 { selected.insert(choice.id) } else { selected.remove(choice.id) } }
                                    )).labelsHidden().toggleStyle(.checkbox)
                                        .accessibilityLabel("Add \(choice.folder.path)")
                                    VStack(alignment: .leading, spacing: 4) {
                                        TextField("Project name", text: $choice.name)
                                            .accessibilityLabel("Project name for \(choice.folder.lastPathComponent)")
                                        Text(choice.folder.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                        if alreadyAdded { Text("Already in your library").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.disabled(alreadyAdded || model.busy)
                            }
                        }.padding(4)
                    }.frame(minHeight: 120, maxHeight: 240)
                } else if folder != nil && !scanning && error == nil {
                    Text("No Ableton Live project folders found. Look for .als files alongside Ableton Project Info or Samples. Other folders can still be added using Add project…")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !issues.isEmpty { issueList(issues, title: "Some locations could not be searched") }
                Text("Project names start with their folder names; you can edit them above. The usual audio/document filters and master/2mix spotlights apply. Original files stay in place.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
                HStack {
                    if model.busy { ProgressView("Adding projects…").controlSize(.small) }
                    Spacer()
                    Button("Cancel") { scanTask?.cancel(); dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                    Button(pending.count == 1 ? "Add 1 project" : "Add \(pending.count) projects", action: startImport)
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canImport)
                }
            }
        }
        .textFieldStyle(.roundedBorder).padding(28).frame(width: 620)
        .interactiveDismissDisabled(model.busy)
        .onDisappear { scanTask?.cancel() }
    }

    @ViewBuilder private func summary(_ report: BatchProjectImportResult) -> some View {
        Text("\(report.added.count) projects added").font(.headline)
        Text("\(report.skipped.count) already in the library · \(report.failed.count) could not be added").foregroundStyle(.secondary)
        if !report.failed.isEmpty { issueList(report.failed, title: "Could not add these folders") }
        Text("Your original files are unchanged.").font(.caption).foregroundStyle(.secondary)
        HStack {
            if !report.failed.isEmpty {
                Button("Review remaining folders") { self.report = nil; selected.subtract(existingPaths) }
            }
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }

    private func issueList(_ issues: [FolderImportIssue], title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text("\(issue.folder.path): \(issue.message)").font(.caption).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 90)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Find projects"
        panel.message = "Choose your music folder. Subfolders will be searched for Ableton Live projects."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url; choices = []; selected = []; issues = []; error = nil; scanning = true
        let library = model.libraryURL
        scanTask = Task {
            defer { scanning = false }
            let worker = Task.detached(priority: .userInitiated) {
                try ProjectFolderDiscovery.scan(url, excluding: [library])
            }
            do {
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                choices = result.projects; issues = result.issues
                selected = Set(choices.map(\.id)).subtracting(existingPaths)
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func startImport() {
        let selectedChoices = pending
        Task {
            error = nil
            do { report = try await model.createBatch(selectedChoices, artist: artist) }
            catch { self.error = error.localizedDescription }
        }
    }
}
