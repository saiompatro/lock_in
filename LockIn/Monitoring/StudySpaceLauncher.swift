import AppKit
import ApplicationServices

@MainActor
enum StudySpaceLauncher {
    /// Bring a study space to the front: activate the app, raise the matching window,
    /// or open the website in its browser (or the default browser).
    static func open(_ space: StudySpace) {
        switch space.kind {
        case .app:
            if let bundleID = space.bundleID { activateApp(bundleID: bundleID) }
        case .window:
            guard let bundleID = space.bundleID else { return }
            activateApp(bundleID: bundleID)
            if let needle = space.titleContains, !needle.isEmpty {
                raiseWindow(bundleID: bundleID, titleContains: needle)
            }
        case .website:
            openWebsite(space)
        }
    }

    // MARK: Apps

    private static func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    private static func activateApp(bundleID: String) {
        let running = runningApp(bundleID)
        if running?.isHidden == true { running?.unhide() }
        guard let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            running?.activate()
            return
        }
        // Launch Services activates (and launches, if needed) reliably for an accessory-policy app like ours.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: Windows

    private static func raiseWindow(bundleID: String, titleContains needle: String) {
        guard AXIsProcessTrusted(), let app = runningApp(bundleID) else { return }
        let pid = app.processIdentifier
        guard let window = AX.windows(pid: pid).first(where: {
            StudySpaceMatcher.titleContains(AX.string($0, kAXTitleAttribute), needle)
        }) else { return }
        AX.set(window, kAXMinimizedAttribute, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AX.set(window, kAXMainAttribute, kCFBooleanTrue)
        AX.set(AX.application(pid: pid), kAXFrontmostAttribute, kCFBooleanTrue)
    }

    // MARK: Websites

    private static func openWebsite(_ space: StudySpace) {
        let workspace = NSWorkspace.shared
        let pattern = space.urlPattern?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let browserURL: URL? = space.bundleID.flatMap { workspace.urlForApplication(withBundleIdentifier: $0) }

        if pattern.isEmpty {
            // Title-only space: just bring the browser forward.
            if let bundleID = space.bundleID {
                activateApp(bundleID: bundleID)
            } else if let probe = URL(string: "https://example.com"),
                      let defaultBrowser = workspace.urlForApplication(toOpen: probe) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                workspace.openApplication(at: defaultBrowser, configuration: configuration)
            }
            return
        }

        let text = pattern.contains("://") ? pattern : "https://" + pattern
        guard let url = URL(string: text) ?? URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)
        else { return }

        if let browserURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            workspace.open([url], withApplicationAt: browserURL, configuration: configuration)
        } else {
            workspace.open(url)
        }
    }
}
