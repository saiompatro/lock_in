import AppKit
import ApplicationServices
import CoreServices
import Observation

@MainActor
@Observable
final class PermissionsManager {
    enum AutomationState: String, Sendable {
        case granted, denied, notDetermined, notRunning
    }

    private(set) var accessibilityGranted: Bool = false
    /// Keyed by browser bundle ID. Only installed browsers that expose tab URLs appear.
    private(set) var automation: [String: AutomationState] = [:]

    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var pollCount = 0

    init() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    // MARK: Refresh

    /// Re-check all permission states without prompting.
    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        refreshAutomation()
    }

    private func refreshAutomation() {
        let browsers = SupportedBrowsers.installed.filter(\.supportsTabURL).map(\.bundleID)
        // Drop browsers that were uninstalled.
        for key in automation.keys where !browsers.contains(key) { automation[key] = nil }
        guard !browsers.isEmpty else { return }
        Task { @MainActor [weak self] in
            let results = await Task.detached(priority: .utility) {
                browsers.map { ($0, Self.determine(bundleID: $0, askUser: false)) }
            }.value
            guard let self else { return }
            for (bundleID, state) in results where self.automation[bundleID] != state {
                // A closed browser tells us nothing new: keep a previously learned answer.
                if state == .notRunning, let known = self.automation[bundleID], known != .notDetermined { continue }
                self.automation[bundleID] = state
            }
        }
    }

    // MARK: Accessibility

    /// Show the system Accessibility prompt and open the right System Settings pane.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted { openAccessibilitySettings() }
    }

    func openAccessibilitySettings() {
        openSettingsPane("Privacy_Accessibility")
    }

    // MARK: Automation

    /// Ask the user to allow Lock In to read the tab URL of `bundleID` (shows the system prompt once).
    func requestAutomation(for bundleID: String) async -> AutomationState {
        let state = await Task.detached(priority: .userInitiated) {
            Self.determine(bundleID: bundleID, askUser: true)
        }.value
        automation[bundleID] = state
        return state
    }

    func openAutomationSettings() {
        openSettingsPane("Privacy_Automation")
    }

    /// Lets the monitor report what it learned from a real Apple Event (success or -1743).
    func noteAutomation(_ state: AutomationState, for bundleID: String) {
        if automation[bundleID] != state { automation[bundleID] = state }
    }

    // MARK: Polling

    /// Poll accessibility state (every 1.5 s) while a permissions UI is visible.
    func startPolling() {
        guard pollTimer == nil else { return }
        pollCount = 0
        refresh()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollTick() {
        pollCount += 1
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityGranted { accessibilityGranted = trusted }
        // Automation changes are rarer; check them every ~6 s.
        if pollCount % 4 == 0 { refreshAutomation() }
    }

    // MARK: Helpers

    private func openSettingsPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Blocking: may wait for the user when `askUser` is true. Never call on the main thread.
    nonisolated static func determine(bundleID: String, askUser: Bool) -> AutomationState {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            return .notRunning
        }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .notDetermined }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, askUser)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .notRunning
        default: return .notDetermined
        }
    }
}
