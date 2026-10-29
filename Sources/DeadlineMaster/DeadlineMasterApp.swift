import SwiftUI
import AppKit

@main
struct DeadlineMasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = StudioModel()
    var body: some Scene {
        Window("Deadline Master", id: "workspace") {
            WorkspaceView(model: model)
                .frame(minWidth: 960, minHeight: 680)
                .tint(Color(red: 0.36, green: 0.46, blue: 0.22))
                .task {
                    if !model.ready { await model.load() }
                    await model.monitorFolders()
                }
        }
        .defaultSize(width: 1240, height: 820)
        // Keep the toolbar controls without a visible window title.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Present once per process launch, not when a SwiftUI view is recreated.
        DispatchQueue.main.async { BackupReminder.showIfNeeded() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
