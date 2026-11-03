import AppKit
import Observation

/// Sections of the main window.
enum MainSection: String, CaseIterable, Identifiable, Hashable {
    case overview, spaces, history, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .spaces: "Study Spaces"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "chart.bar.xaxis"
        case .spaces: "square.stack.3d.up"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

/// Composition root. Owns every service, wires them together, and is the single
/// object the UI talks to. Lives for the whole app lifetime (`AppModel.shared`).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings: AppSettings
    let spaces: StudySpaceStore
    let sessions: SessionStore
    let permissions: PermissionsManager
    let engine: SessionEngine
    let monitor: ActivityMonitor
    let alerts: AlertManager

    /// What is frontmost right now (updated only while a session is running).
    private(set) var currentSnapshot: ActivitySnapshot?
    /// Updated once per second while a session is active. Read it from views that show live timers
    /// (including the menu bar label) so they re-render every second.
    private(set) var now: Date = Date()
    /// Section the main window should show; the window controller observes this.
    var selectedSection: MainSection = .overview
    /// True until the user finishes onboarding (main window shows the onboarding flow).
    var showOnboarding: Bool { !settings.hasCompletedOnboarding }

    @ObservationIgnored private var clockTimer: Timer?
    @ObservationIgnored private var lastLiveSave = Date.distantPast
    @ObservationIgnored private var didLaunch = false
    /// Last app other than Lock In that was frontmost (cheap, permission-free tracking), used when
    /// a session is started from Lock In's own window or menu bar panel.
    @ObservationIgnored private var lastExternalApp: NSRunningApplication?
    @ObservationIgnored private var activationToken: NSObjectProtocol?

    var status: SessionStatus { engine.status }
    var isSessionActive: Bool { engine.isActive }
    var canStartSession: Bool { !spaces.enabledSpaces.isEmpty }

    private init() {
        settings = AppSettings()
        spaces = StudySpaceStore()
        sessions = SessionStore()
        permissions = PermissionsManager()
        engine = SessionEngine()
        monitor = ActivityMonitor(permissions: permissions)
        alerts = AlertManager(settings: settings)
        wire()
    }

    // MARK: Lifecycle

    /// Called once from the app delegate after launch.
    func launch() {
        guard !didLaunch else { return }
        didLaunch = true
        #if DEBUG
        if DebugSnapshots.runIfRequested(model: self) { return }
        #endif
        sessions.recoverInterruptedSession()
        trackExternalApps()
        permissions.refresh()
        settings.refreshLaunchAtLogin()
        if !settings.hasCompletedOnboarding {
            openMainWindow(.overview)
        }
    }

    /// Called from the app delegate when the app quits: finish and save the running session.
    func prepareForTermination() {
        if engine.isActive { stopSession() }
    }

    // MARK: Session control

    func startSession() {
        guard !engine.isActive else { return }
        guard canStartSession else {
            openMainWindow(.spaces)
            return
        }
        syncEngineSettings()
        permissions.refresh()
        Task { @MainActor in
            var snapshot = await monitor.captureNow()
            if snapshot.isOwnApp, let fallback = externalAppSnapshot() {
                snapshot = fallback
            }
            currentSnapshot = snapshot
            engine.start(snapshot: snapshot, matched: match(snapshot))
            monitor.start()
            startClock()
        }
    }

    func pauseSession() {
        guard engine.status == .studying || engine.status == .distracted else { return }
        engine.pause()
    }

    func resumeSession() {
        guard engine.status == .paused else { return }
        syncEngineSettings()
        engine.resume()
        monitor.refresh()
    }

    func togglePause() {
        engine.status == .paused ? resumeSession() : pauseSession()
    }

    func takeBreak() {
        guard engine.isActive else { return }
        engine.pause(for: max(60, settings.breakMinutes * 60))
    }

    func stopSession() {
        guard engine.isActive else { return }
        engine.stop()
        monitor.stop()
        stopClock()
        currentSnapshot = nil
        sessions.saveLiveSnapshot(nil)
    }

    // MARK: Study spaces (use these instead of the store so a running session re-evaluates)

    func addSpace(_ space: StudySpace) { spaces.add(space); reevaluate() }
    func updateSpace(_ space: StudySpace) { spaces.update(space); reevaluate() }
    func removeSpace(id: UUID) { spaces.remove(id: id); reevaluate() }
    func setSpaceEnabled(_ enabled: Bool, id: UUID) { spaces.setEnabled(enabled, id: id); reevaluate() }

    /// Bring a study space to the front.
    func open(_ space: StudySpace) { StudySpaceLauncher.open(space) }

    // MARK: Windows

    func openMainWindow(_ section: MainSection? = nil) {
        if let section { selectedSection = section }
        MainWindowController.shared.show(model: self)
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        selectedSection = spaces.spaces.isEmpty ? .spaces : .overview
    }

    // MARK: Wiring

    private func wire() {
        monitor.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            if !snapshot.isOwnApp { self.currentSnapshot = snapshot }
            self.engine.ingest(snapshot, matched: self.match(snapshot))
        }
        monitor.onAwayStateChanged = { [weak self] away in
            guard let self, self.settings.pauseWhenAway, self.engine.isActive else { return }
            if away {
                self.engine.systemWentAway()
            } else {
                self.engine.systemReturned()
                self.monitor.refresh()
            }
        }
        engine.onAlert = { [weak self] context in
            self?.alerts.present(context)
        }
        engine.onDistractionEnded = { [weak self] in
            self?.alerts.dismiss()
        }
        engine.onBreakEnded = { [weak self] in
            self?.monitor.refresh()
        }
        engine.onSessionEnded = { [weak self] record in
            self?.sessions.append(record)
            self?.sessions.saveLiveSnapshot(nil)
        }
        alerts.onReturnToStudy = { [weak self] space in
            guard let self else { return }
            if let target = space ?? self.engine.lastStudySpace ?? self.spaces.enabledSpaces.first {
                StudySpaceLauncher.open(target)
            }
        }
        alerts.onTakeBreak = { [weak self] in self?.takeBreak() }
        alerts.onEndSession = { [weak self] in self?.stopSession() }
    }

    private func trackExternalApps() {
        let own = Bundle.main.bundleIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != own {
            lastExternalApp = front
        }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app, app.bundleIdentifier != own { self?.lastExternalApp = app }
            }
        }
    }

    /// App-level snapshot of the last non-Lock In app. The monitor replaces it with a full snapshot
    /// (window title, tab URL) as soon as that app comes back to the front.
    private func externalAppSnapshot() -> ActivitySnapshot? {
        guard let app = lastExternalApp, !app.isTerminated else { return nil }
        var snapshot = ActivitySnapshot()
        snapshot.bundleID = app.bundleIdentifier
        snapshot.appName = app.localizedName
        snapshot.isBrowser = SupportedBrowsers.info(for: app.bundleIdentifier) != nil
        snapshot.windowInfoAvailable = false
        return snapshot
    }

    private func match(_ snapshot: ActivitySnapshot) -> StudySpace? {
        StudySpaceMatcher.match(snapshot, in: spaces.enabledSpaces)
    }

    /// Re-run matching for the current activity (after study spaces change).
    private func reevaluate() {
        guard engine.isActive, let snapshot = currentSnapshot else { return }
        engine.ingest(snapshot, matched: match(snapshot))
    }

    private func syncEngineSettings() {
        engine.distractionThreshold = settings.distractionThreshold
        engine.repeatInterval = settings.repeatInterval
    }

    // MARK: 1 Hz clock (only while a session is active)

    private func startClock() {
        stopClock()
        now = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.clockFired() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
        now = Date()
    }

    private func clockFired() {
        now = Date()
        syncEngineSettings()
        engine.tick()
        if now.timeIntervalSince(lastLiveSave) >= 30 {
            lastLiveSave = now
            sessions.saveLiveSnapshot(engine.liveRecord(at: now))
        }
    }
}
