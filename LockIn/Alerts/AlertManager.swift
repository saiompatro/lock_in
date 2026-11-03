import AppKit

/// Presents distraction alerts: a large on-screen pop-up, a macOS notification, and/or a sound,
/// according to `AppSettings`. Never spams: one presentation per `present` call, and the
/// pop-up is reused if already visible.
@MainActor
final class AlertManager {
    /// "Back to studying" pressed (pop-up button or notification action). Argument: space to reopen.
    var onReturnToStudy: ((StudySpace?) -> Void)?
    /// "Take a break" pressed.
    var onTakeBreak: (() -> Void)?
    /// "End session" pressed.
    var onEndSession: (() -> Void)?

    private let settings: AppSettings
    private let overlay = DistractionOverlayController()
    private let sound = SoundPlayer()
    private let notifications = NotificationController()

    /// Context of the alert currently on screen / in Notification Center.
    private var activeContext: AlertContext?
    /// True while the alert on screen is a Settings preview: its buttons must not touch the session.
    private var activeIsPreview = false
    /// Bumped by `dismiss()` so async work (notification permission) from an older alert is dropped.
    private var generation = 0

    init(settings: AppSettings) {
        self.settings = settings
        notifications.onAction = { [weak self] action in
            self?.handleNotificationAction(action)
        }
    }

    // MARK: Public API

    /// Show the alert for a distraction episode that crossed the threshold.
    func present(_ context: AlertContext) {
        show(context, isPreview: false)
    }

    /// Hide the pop-up, stop any looping sound, remove delivered notifications.
    func dismiss() {
        generation += 1
        activeContext = nil
        activeIsPreview = false
        overlay.hide()
        sound.stop()
        notifications.removeAll()
    }

    /// Show a sample alert (from Settings) using the current settings.
    func preview() {
        let sample = AlertContext(distractedFor: settings.distractionThreshold,
                                  distractingAppName: "Safari",
                                  lastStudySpace: nil,
                                  isRepeat: false)
        show(sample, isPreview: true)
    }

    /// Play the configured sound once (Settings preview).
    func playSoundPreview() {
        sound.play(name: settings.soundName, volume: settings.soundVolume, loop: false)
    }

    func requestNotificationPermission() async -> Bool {
        await notifications.requestAuthorization()
    }

    /// true = authorized, false = denied, nil = not determined yet.
    func notificationPermissionStatus() async -> Bool? {
        await notifications.authorizationStatus()
    }

    // MARK: Presentation

    private func show(_ context: AlertContext, isPreview: Bool) {
        let style = settings.alertStyle
        activeContext = context
        activeIsPreview = isPreview
        generation += 1
        let token = generation

        if style.showsOverlay {
            showOverlay(context, isPreview: isPreview)
        }

        if settings.soundEnabled {
            // Loop only if there is an overlay to stop it from; a preview of a notification-only
            // style would otherwise loop with no button to end it.
            let loop = settings.loopSoundUntilReturn && (!isPreview || style.showsOverlay)
            sound.play(name: settings.soundName, volume: settings.soundVolume, loop: loop)
        }

        if style.showsNotification {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let granted = await self.notifications.ensureAuthorized()
                guard self.generation == token else { return } // dismissed or replaced meanwhile
                if granted {
                    await self.notifications.post(title: "Time to lock back in",
                                                  body: Self.notificationBody(for: context))
                } else if !style.showsOverlay {
                    // Notifications are blocked and no pop-up was requested: never lose the alert.
                    self.showOverlay(context, isPreview: isPreview)
                }
            }
        }
    }

    private func showOverlay(_ context: AlertContext, isPreview: Bool) {
        overlay.show(
            context: context,
            breakMinutes: settings.breakMinutes,
            isPreview: isPreview,
            onReturn: { [weak self] in self?.returnToStudy() },
            onBreak: { [weak self] in self?.takeBreak() },
            onEnd: { [weak self] in self?.endSession() },
            onCancel: { [weak self] in self?.dismiss() }
        )
    }

    private static func notificationBody(for context: AlertContext) -> String {
        var body = "You've been away from your study spaces for \(DistractionOverlayModel.spoken(context.distractedFor))"
        if let app = context.distractingAppName, !app.isEmpty { body += ", on \(app)" }
        return body
    }

    // MARK: Actions

    private func returnToStudy() {
        let context = activeContext
        let preview = activeIsPreview
        if !preview { onReturnToStudy?(context?.lastStudySpace) }
        dismiss()
    }

    private func takeBreak() {
        let preview = activeIsPreview
        if !preview { onTakeBreak?() }
        dismiss()
    }

    private func endSession() {
        let preview = activeIsPreview
        if !preview { onEndSession?() }
        dismiss()
    }

    private func handleNotificationAction(_ action: NotificationController.Action) {
        // A banner can outlive its alert (e.g. the user already came back): ignore stale clicks.
        guard activeContext != nil else { return }
        switch action {
        case .backToStudying: returnToStudy()
        case .takeBreak: takeBreak()
        }
    }
}
