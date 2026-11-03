#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `LOCKIN_SNAPSHOT_DIR=/some/dir` renders every main screen to PNG (light + dark)
/// with sample data, then quits. Nothing is written to the real data files or preferences.
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["LOCKIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func runIfRequested(model: AppModel) -> Bool {
        if ProcessInfo.processInfo.environment["LOCKIN_DEBUG_MONITOR"] != nil {
            Storage.isReadOnly = true
            Task { @MainActor in
                await monitorRun(model: model)
                NSApp.terminate(nil)
            }
            return true
        }
        guard let dir = directory else { return false }
        Storage.isReadOnly = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            await run(model: model, dir: dir)
            NSApp.terminate(nil)
        }
        return true
    }

    private static func run(model: AppModel, dir: URL) async {
        let defaults = UserDefaults.standard
        let onboardingWas = defaults.object(forKey: "hasCompletedOnboarding")
        defer {
            if let onboardingWas { defaults.set(onboardingWas, forKey: "hasCompletedOnboarding") }
            else { defaults.removeObject(forKey: "hasCompletedOnboarding") }
        }

        seed(model: model)

        for appearance in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance.1)

            model.settings.hasCompletedOnboarding = false
            model.openMainWindow(.overview)
            await settle()
            capture(mainWindow(), to: dir.appendingPathComponent("onboarding-\(appearance.0).png"))

            model.settings.hasCompletedOnboarding = true
            for section in MainSection.allCases {
                model.selectedSection = section
                await settle()
                capture(mainWindow(), to: dir.appendingPathComponent("\(section.rawValue)-\(appearance.0).png"))
            }

            // Menu bar panel, idle and during a session.
            let panel = hostWindow(MenuBarContentView().environment(model), size: NSSize(width: 320, height: 640))
            await settle()
            capture(panel, to: dir.appendingPathComponent("menubar-idle-\(appearance.0).png"))
            if let space = model.spaces.enabledSpaces.first {
                var snap = ActivitySnapshot()
                snap.bundleID = space.bundleID
                snap.appName = space.appName
                model.engine.start(snapshot: snap, matched: space)
                await settle(1.5)
                capture(panel, to: dir.appendingPathComponent("menubar-studying-\(appearance.0).png"))
                snap.bundleID = "com.apple.Music"
                snap.appName = "Music"
                model.engine.ingest(snap, matched: nil)
                await settle(1.5)
                capture(panel, to: dir.appendingPathComponent("menubar-distracted-\(appearance.0).png"))
                model.engine.stop()
            }
            panel.close()
        }

        // Alert pop-up card.
        let overlayModel = DistractionOverlayModel(
            context: AlertContext(distractedFor: 300, distractingAppName: "Safari",
                                  lastStudySpace: model.spaces.enabledSpaces.first, isRepeat: false),
            breakMinutes: 5, isPreview: false)
        let overlay = hostWindow(DistractionOverlayView(model: overlayModel), size: NSSize(width: 1100, height: 760))
        await settle(1.5)
        capture(overlay, to: dir.appendingPathComponent("alert-overlay.png"))
        overlay.close()
    }

    /// Live detection test: Finder is the only study space, 8 s threshold, alerts are printed instead of shown.
    private static func monitorRun(model: AppModel) async {
        let finder = StudySpace(kind: .app, name: "Finder", bundleID: "com.apple.finder", appName: "Finder")
        model.spaces.add(finder)
        for space in model.spaces.spaces where space.id != finder.id { model.spaces.setEnabled(false, id: space.id) }
        model.settings.distractionThresholdMinutes = 8.0 / 60
        let original = model.monitor.onSnapshot
        model.monitor.onSnapshot = { snapshot in
            original?(snapshot)
            let t = Date()
            print("SNAP app=\(snapshot.appName ?? "-") own=\(snapshot.isOwnApp) ax=\(snapshot.windowInfoAvailable) -> \(model.engine.status.rawValue) distractedFor=\(Int(model.engine.currentDistractionElapsed(at: t)))s")
        }
        model.engine.onAlert = { ctx in
            print("ALERT after \(Int(ctx.distractedFor))s on \(ctx.distractingAppName ?? "-") repeat=\(ctx.isRepeat)")
        }
        model.engine.onDistractionEnded = { print("DISTRACTION ENDED") }
        model.startSession()
        try? await Task.sleep(for: .seconds(32))
        let t = Date()
        print(String(format: "TOTALS focused=%.1f distracted=%.1f distractions=%d alerts=%d",
                     model.engine.focusedTime(at: t), model.engine.distractedTime(at: t),
                     model.engine.liveRecord(at: t)?.distractionCount ?? -1, model.engine.alertCount))
        model.stopSession()
        model.settings.distractionThresholdMinutes = 5
    }

    // MARK: Helpers

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.title == "Lock In" && $0.isVisible }
    }

    private static func hostWindow<V: View>(_ view: V, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        return window
    }

    private static func settle(_ seconds: Double = 1.0) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func capture(_ window: NSWindow?, to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: Sample data (in memory only)

    private static func seed(model: AppModel) {
        let samples: [StudySpace] = [
            StudySpace(kind: .app, name: "Xcode", bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
            StudySpace(kind: .window, name: "Lecture 4 – Thermodynamics.pdf", bundleID: "com.apple.Preview",
                       appName: "Preview", titleContains: "Lecture 4"),
            StudySpace(kind: .website, name: "notion.so", urlPattern: "notion.so"),
            StudySpace(kind: .website, name: "docs.google.com", bundleID: "com.google.Chrome",
                       appName: "Google Chrome", urlPattern: "docs.google.com/document"),
        ]
        for space in samples where !model.spaces.spaces.contains(where: { $0.name == space.name }) {
            model.spaces.add(space)
        }

        let cal = Calendar.current
        let apps = ["Safari", "Messages", "Music", "Discord", "Mail"]
        var records: [StudySessionRecord] = []
        for dayOffset in 0..<9 where dayOffset != 3 {
            let day = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: Date()))!
            for (i, hour) in [9, 14, 20].enumerated() where (dayOffset + i) % 4 != 0 {
                let start = cal.date(byAdding: .hour, value: hour, to: day)!
                let focused = Double(1800 + ((dayOffset * 7 + i * 13) % 5) * 900)
                let distracted = Double(180 + ((dayOffset + i) % 4) * 240)
                let n = 1 + (dayOffset + i) % 4
                let events = (0..<n).map { k in
                    DistractionEvent(start: start.addingTimeInterval(Double(600 + k * 900)),
                                     duration: distracted / Double(n),
                                     appName: apps[(dayOffset + k + i) % apps.count],
                                     triggeredAlert: k == 0 && distracted > 400)
                }
                records.append(StudySessionRecord(
                    id: UUID(), startedAt: start,
                    endedAt: start.addingTimeInterval(focused + distracted + 300),
                    focusedSeconds: focused, distractedSeconds: distracted, pausedSeconds: 300,
                    distractionCount: n, alertCount: events.filter(\.triggeredAlert).count,
                    longestFocusStreak: focused / Double(n),
                    distractions: events,
                    spaceBreakdown: ["Xcode": focused * 0.5, "notion.so": focused * 0.3,
                                     "Lecture 4 – Thermodynamics.pdf": focused * 0.2]))
            }
        }
        model.sessions.loadPreviewData(records)
    }
}
#endif
