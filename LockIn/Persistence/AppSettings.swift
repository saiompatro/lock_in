import Foundation
import Observation
import ServiceManagement

enum AlertStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Large on-screen pop-up over the current screen.
    case overlay
    /// Standard macOS notification banner.
    case notification
    /// Both of the above.
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overlay: "Full-screen pop-up"
        case .notification: "macOS notification"
        case .both: "Pop-up + notification"
        }
    }

    var showsOverlay: Bool { self == .overlay || self == .both }
    var showsNotification: Bool { self == .notification || self == .both }
}

/// User preferences, persisted in UserDefaults. Every property saves on write.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    /// Minutes outside study spaces before the alert fires. Default 5.
    var distractionThresholdMinutes: Double { didSet { save(distractionThresholdMinutes, "distractionThresholdMinutes") } }
    var alertStyle: AlertStyle { didSet { save(alertStyle.rawValue, "alertStyle") } }
    var soundEnabled: Bool { didSet { save(soundEnabled, "soundEnabled") } }
    /// Name of a system sound in /System/Library/Sounds (e.g. "Glass", "Hero", "Submarine").
    var soundName: String { didSet { save(soundName, "soundName") } }
    /// 0...1
    var soundVolume: Double { didSet { save(soundVolume, "soundVolume") } }
    /// Alarm mode: keep repeating the sound until the user returns or dismisses.
    var loopSoundUntilReturn: Bool { didSet { save(loopSoundUntilReturn, "loopSoundUntilReturn") } }
    /// Send follow-up reminders if the user stays distracted after the first alert.
    var repeatReminders: Bool { didSet { save(repeatReminders, "repeatReminders") } }
    /// Minutes between follow-up reminders.
    var repeatIntervalMinutes: Double { didSet { save(repeatIntervalMinutes, "repeatIntervalMinutes") } }
    /// Show the running timer next to the menu bar icon.
    var showTimerInMenuBar: Bool { didSet { save(showTimerInMenuBar, "showTimerInMenuBar") } }
    /// Pause tracking while the screen is locked or the Mac is asleep.
    var pauseWhenAway: Bool { didSet { save(pauseWhenAway, "pauseWhenAway") } }
    /// Length of the break offered by the alert pop-up, in minutes.
    var breakMinutes: Double { didSet { save(breakMinutes, "breakMinutes") } }
    /// Daily focused-time goal in minutes (dashboard ring).
    var dailyGoalMinutes: Double { didSet { save(dailyGoalMinutes, "dailyGoalMinutes") } }
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }

    /// Mirrors SMAppService state. Setting it registers/unregisters the login item.
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue, !isSyncingLoginItem else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
                isSyncingLoginItem = true
                launchAtLogin = oldValue
                isSyncingLoginItem = false
            }
        }
    }
    /// Last error from registering the login item, for display in Settings.
    var launchAtLoginError: String?
    @ObservationIgnored private var isSyncingLoginItem = false

    var distractionThreshold: TimeInterval { max(10, distractionThresholdMinutes * 60) }
    var repeatInterval: TimeInterval? { repeatReminders ? max(60, repeatIntervalMinutes * 60) : nil }

    static let availableSounds: [String] = {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let list = names.map { ($0 as NSString).deletingPathExtension }.sorted()
        return list.isEmpty ? ["Glass", "Hero", "Ping", "Submarine", "Sosumi"] : list
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        distractionThresholdMinutes = defaults.object(forKey: "distractionThresholdMinutes") as? Double ?? 5
        alertStyle = AlertStyle(rawValue: defaults.string(forKey: "alertStyle") ?? "") ?? .both
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        soundName = defaults.string(forKey: "soundName") ?? "Glass"
        soundVolume = defaults.object(forKey: "soundVolume") as? Double ?? 0.8
        loopSoundUntilReturn = defaults.object(forKey: "loopSoundUntilReturn") as? Bool ?? false
        repeatReminders = defaults.object(forKey: "repeatReminders") as? Bool ?? true
        repeatIntervalMinutes = defaults.object(forKey: "repeatIntervalMinutes") as? Double ?? 5
        showTimerInMenuBar = defaults.object(forKey: "showTimerInMenuBar") as? Bool ?? true
        pauseWhenAway = defaults.object(forKey: "pauseWhenAway") as? Bool ?? true
        breakMinutes = defaults.object(forKey: "breakMinutes") as? Double ?? 5
        dailyGoalMinutes = defaults.object(forKey: "dailyGoalMinutes") as? Double ?? 120
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Re-read the login item state (the user can change it in System Settings).
    func refreshLaunchAtLogin() {
        let enabled = SMAppService.mainApp.status == .enabled
        if enabled != launchAtLogin {
            isSyncingLoginItem = true
            launchAtLogin = enabled
            isSyncingLoginItem = false
        }
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
