import AppKit
import SwiftUI

/// Owns the single main window (NSWindow + NSHostingView). Switches the app to `.regular`
/// activation policy while the window is open (Dock icon, Cmd-Tab) and back to `.accessory` on close.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func show(model: AppModel) {
        let window = self.window ?? makeWindow(model: model)
        self.window = window

        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Switching activation policy can swallow the first activation; repeat on the next turn.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Lock In"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.contentMinSize = NSSize(width: 820, height: 560)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self

        let hosting = NSHostingView(rootView: MainWindowView().environment(model))
        hosting.sizingOptions = []
        window.contentView = hosting

        window.setContentSize(NSSize(width: 1000, height: 700))
        window.center()
        window.setFrameAutosaveName("LockInMainWindow")
        return window
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
