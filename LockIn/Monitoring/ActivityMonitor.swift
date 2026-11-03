import AppKit
import ApplicationServices

/// Watches the frontmost app, its focused window, and the active browser tab.
/// Event-driven (NSWorkspace + AXObserver) with a slow fallback poll, only while running.
@MainActor
final class ActivityMonitor {
    /// Called on the main actor whenever the activity changes (de-duplicated).
    var onSnapshot: ((ActivitySnapshot) -> Void)?
    /// true = screen locked / Mac asleep / user switched out; false = back.
    var onAwayStateChanged: ((Bool) -> Void)?
    private(set) var isRunning = false

    private let permissions: PermissionsManager
    private let scriptRunner = AppleScriptRunner(label: "com.lockin.monitor.applescript")

    // Tunables.
    private let debounceInterval: Duration = .milliseconds(150)
    private let pollInterval: TimeInterval = 3
    private let deniedRetryInterval: TimeInterval = 10
    private let errorRetryInterval: TimeInterval = 3

    // Observers / timers.
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var debounceTask: Task<Void, Never>?

    // Accessibility observation of the frontmost app.
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var observedAppElement: AXUIElement?
    private var observedWindow: AXUIElement?

    // Capture bookkeeping.
    private var captureGeneration = 0
    private var lastEmitted: ActivitySnapshot?
    private var browserRetryNotBefore: [String: Date] = [:]

    // Away state.
    private var awayReasons: Set<String> = []
    private var isAway = false

    init(permissions: PermissionsManager) {
        self.permissions = permissions
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastEmitted = nil
        awayReasons = []
        isAway = false
        browserRetryNotBefore = [:]
        installWorkspaceObservers()
        installAwayObservers()
        rebuildAXObserver()
        installPollTimer()
        beginCapture()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        debounceTask?.cancel()
        debounceTask = nil
        captureGeneration += 1
        pollTimer?.invalidate()
        pollTimer = nil
        tearDownAXObserver()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens = []
        for token in distributedTokens { DistributedNotificationCenter.default().removeObserver(token) }
        distributedTokens = []
        lastEmitted = nil
        awayReasons = []
        isAway = false
    }

    /// Capture the current activity (including browser URL) right now.
    func captureNow() async -> ActivitySnapshot {
        await buildSnapshot()
    }

    /// Re-capture asynchronously and emit via `onSnapshot` if it changed.
    func refresh() {
        guard isRunning else { return }
        if AXIsProcessTrusted(), axObserver == nil { rebuildAXObserver() }
        beginCapture()
    }

    // MARK: Capture pipeline

    /// Debounced: coalesces bursts of events into one capture.
    private func scheduleCapture() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounceInterval)
            guard !Task.isCancelled else { return }
            self.beginCapture()
        }
    }

    /// Starts a capture now. A newer capture supersedes (and discards) an older one still in flight.
    private func beginCapture() {
        guard isRunning else { return }
        debounceTask?.cancel()
        debounceTask = nil
        captureGeneration += 1
        let generation = captureGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.buildSnapshot()
            guard self.isRunning, generation == self.captureGeneration else { return }
            self.emitIfChanged(snapshot)
        }
    }

    private func emitIfChanged(_ snapshot: ActivitySnapshot) {
        if let last = lastEmitted, last.sameActivity(as: snapshot) { return }
        lastEmitted = snapshot
        onSnapshot?(snapshot)
    }

    /// Full snapshot including the browser URL. The URL is only ever attached to the app it was read from.
    private func buildSnapshot() async -> ActivitySnapshot {
        var snapshot = baseSnapshot()
        for _ in 0..<2 {
            guard snapshot.isBrowser, !snapshot.isOwnApp,
                  !snapshot.windowInfoAvailable || snapshot.hasVisibleWindow,
                  let bundleID = snapshot.bundleID,
                  let info = SupportedBrowsers.info(for: bundleID), info.supportsTabURL
            else { break }
            let url = await fetchURL(for: info)
            // If the user switched apps while we waited, the URL is stale: rebuild.
            let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if current == bundleID {
                snapshot.browserURL = url
                snapshot.timestamp = Date()
                return snapshot
            }
            snapshot = baseSnapshot()
        }
        snapshot.browserURL = nil
        return snapshot
    }

    /// Everything that can be read synchronously: app identity and Accessibility window info.
    private func baseSnapshot() -> ActivitySnapshot {
        var snapshot = ActivitySnapshot()
        guard let app = NSWorkspace.shared.frontmostApplication else { return snapshot }
        snapshot.bundleID = app.bundleIdentifier
        snapshot.appName = app.localizedName
        snapshot.isBrowser = SupportedBrowsers.info(for: app.bundleIdentifier) != nil
        snapshot.isOwnApp = app.bundleIdentifier != nil && app.bundleIdentifier == Bundle.main.bundleIdentifier

        let trusted = AXIsProcessTrusted()
        snapshot.windowInfoAvailable = trusted
        if snapshot.isOwnApp { return snapshot }
        if trusted {
            let state = AccessibilityReader.windowState(pid: app.processIdentifier, isHidden: app.isHidden)
            snapshot.windowTitle = state.title
            snapshot.hasVisibleWindow = state.hasVisibleWindow
        }
        return snapshot
    }

    // MARK: Browser URL

    private func fetchURL(for info: BrowserInfo) async -> URL? {
        guard let expression = info.activeTabURLExpression else { return nil }
        if let notBefore = browserRetryNotBefore[info.bundleID], Date() < notBefore { return nil }

        let source = """
        tell application id "\(info.bundleID)"
            if it is running then
                with timeout of 2 seconds
                    if (count of windows) > 0 then
                        return \(expression)
                    end if
                end timeout
            end if
        end tell
        return ""
        """
        let result = await scriptRunner.runString(key: "url:" + info.bundleID, source: source)
        switch result {
        case .success(let text):
            browserRetryNotBefore[info.bundleID] = nil
            permissions.noteAutomation(.granted, for: info.bundleID)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(string: trimmed)
        case .failure(let failure):
            if failure.isPermissionProblem {
                browserRetryNotBefore[info.bundleID] = Date().addingTimeInterval(deniedRetryInterval)
                permissions.noteAutomation(failure.code == ScriptFailure.notPermitted ? .denied : .notDetermined,
                                           for: info.bundleID)
            } else {
                browserRetryNotBefore[info.bundleID] = Date().addingTimeInterval(errorRetryInterval)
            }
            return nil
        }
    }

    // MARK: Workspace notifications

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let add: (NSNotification.Name, @escaping @MainActor (Notification) -> Void) -> Void = { name, handler in
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { handler(note) }
            }
            self.workspaceTokens.append(token)
        }

        add(NSWorkspace.didActivateApplicationNotification) { [weak self] _ in
            guard let self else { return }
            self.rebuildAXObserver()
            self.scheduleCapture()
        }
        for name in [NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            add(name) { [weak self] _ in self?.scheduleCapture() }
        }

        // Away state.
        add(NSWorkspace.willSleepNotification) { [weak self] _ in self?.setAway("sleep", true) }
        add(NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.setAway("sleep", false)
            self?.scheduleCapture()
        }
        add(NSWorkspace.screensDidSleepNotification) { [weak self] _ in self?.setAway("screensSleep", true) }
        add(NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.setAway("screensSleep", false) }
        add(NSWorkspace.sessionDidResignActiveNotification) { [weak self] _ in self?.setAway("session", true) }
        add(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in
            self?.setAway("session", false)
            self?.scheduleCapture()
        }
    }

    private func installAwayObservers() {
        let center = DistributedNotificationCenter.default()
        let locked = center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"),
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setAway("locked", true) }
        }
        let unlocked = center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"),
                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setAway("locked", false)
                self?.scheduleCapture()
            }
        }
        distributedTokens = [locked, unlocked]
    }

    private func setAway(_ reason: String, _ active: Bool) {
        if active { awayReasons.insert(reason) } else { awayReasons.remove(reason) }
        let away = !awayReasons.isEmpty
        guard away != isAway else { return }
        isAway = away
        onAwayStateChanged?(away)
    }

    // MARK: Fallback poll

    private func installPollTimer() {
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func pollTick() {
        guard isRunning, !isAway else { return }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let trusted = AXIsProcessTrusted()
        if (trusted && axObserver == nil) || (!trusted && axObserver != nil) || frontPID != observedPID {
            rebuildAXObserver()
        }
        beginCapture()
    }

    // MARK: AXObserver

    private static let appNotifications: [String] = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXTitleChangedNotification,
        kAXWindowCreatedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
        kAXUIElementDestroyedNotification,
    ]

    private static let windowNotifications: [String] = [
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification,
    ]

    /// Re-creates the observer for the current frontmost app.
    private func rebuildAXObserver() {
        tearDownAXObserver()
        guard isRunning, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { observedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0; return }

        let pid = app.processIdentifier
        observedPID = pid
        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &created) == .success, let observer = created else { return }

        let element = AX.application(pid: pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        axObserver = observer
        observedAppElement = element
        observeFocusedWindow()
    }

    private func tearDownAXObserver() {
        if let observer = axObserver {
            unobserveWindow()
            if let element = observedAppElement {
                for name in Self.appNotifications { AXObserverRemoveNotification(observer, element, name as CFString) }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        axObserver = nil
        observedAppElement = nil
        observedWindow = nil
    }

    private func unobserveWindow() {
        if let observer = axObserver, let window = observedWindow {
            for name in Self.windowNotifications { AXObserverRemoveNotification(observer, window, name as CFString) }
        }
        observedWindow = nil
    }

    /// (Re-)registers per-window notifications on the app's current focused window.
    private func observeFocusedWindow() {
        guard let observer = axObserver, let app = observedAppElement else { return }
        unobserveWindow()
        guard let window = AX.element(app, kAXFocusedWindowAttribute) else { return }
        AXUIElementSetMessagingTimeout(window, AX.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
        observedWindow = window
    }

    fileprivate func handleAXNotification(_ name: String) {
        guard isRunning else { return }
        if name == kAXFocusedWindowChangedNotification || name == kAXMainWindowChangedNotification
            || name == kAXWindowCreatedNotification || name == kAXUIElementDestroyedNotification {
            observeFocusedWindow()
        }
        scheduleCapture()
    }
}

/// C callback for AXObserver. Runs on the main run loop, so hopping to the main actor is a no-op.
private let axObserverCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let monitor = Unmanaged<ActivityMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated { monitor.handleAXNotification(name) }
}
