import AppKit

/// A standard macOS launch reminder; suppression persists across application updates.
@MainActor
enum BackupReminder {
    private static let suppressionKey = "suppressBackupReminder"

    static func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: suppressionKey) else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Your music stays on this Mac"
        alert.informativeText = "Keep a separate backup of your library. Deadline Master stores project information and file paths locally. Back up your original audio and documents separately; the library is not a backup of your files."
        alert.addButton(withTitle: "Got it")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t show this again"
        alert.runModal()
        UserDefaults.standard.set(alert.suppressionButton?.state == .on, forKey: suppressionKey)
    }
}
