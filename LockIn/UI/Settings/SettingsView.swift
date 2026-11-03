import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Settings", subtitle: "Tune how Lock In keeps you on track")
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xs)

            Form {
                SessionSettingsSection(settings: settings)
                AlertSettingsSection(settings: settings)
                BehaviorSettingsSection(settings: settings)
                PermissionsSettingsSection()
                PrivacySettingsSection()
                AboutSettingsSection()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            model.permissions.refresh()
            model.permissions.startPolling()
            model.settings.refreshLaunchAtLogin()
        }
        .onDisappear { model.permissions.stopPolling() }
    }
}

// MARK: - Session

private struct SessionSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            LabeledContent {
                Stepper(value: $settings.distractionThresholdMinutes, in: 1...60, step: 1) {
                    Text(minutes(settings.distractionThresholdMinutes))
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alert me after")
                    Text("How long you can be outside your study spaces before Lock In speaks up.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            LabeledContent {
                Stepper(value: $settings.breakMinutes, in: 1...60, step: 1) {
                    Text(minutes(settings.breakMinutes))
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Break length")
                    Text("Used by “Take a break” in the menu bar and in alerts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            LabeledContent {
                Stepper(value: $settings.dailyGoalMinutes, in: 15...720, step: 15) {
                    Text(UIFormat.duration(settings.dailyGoalMinutes * 60))
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily focus goal")
                    Text("Shown as the ring on your dashboard.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Session")
        }
    }

    private func minutes(_ value: Double) -> String {
        "\(Int(value)) min"
    }
}

// MARK: - Alerts

private struct AlertSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            Picker("Alert style", selection: $settings.alertStyle) {
                ForEach(AlertStyle.allCases) { Text($0.displayName).tag($0) }
            }

            Toggle("Play a sound", isOn: $settings.soundEnabled)

            if settings.soundEnabled {
                LabeledContent("Sound") {
                    HStack(spacing: Theme.Spacing.xs) {
                        Picker("Sound", selection: $settings.soundName) {
                            ForEach(AppSettings.availableSounds, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        Button { model.alerts.playSoundPreview() } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.lockInIcon)
                        .help("Preview sound")
                        .accessibilityLabel("Preview sound")
                    }
                }

                LabeledContent("Volume") {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary).font(.caption)
                        Slider(value: $settings.soundVolume, in: 0...1)
                            .frame(width: 160)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).font(.caption)
                    }
                }

                Toggle(isOn: $settings.loopSoundUntilReturn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alarm mode")
                        Text("Keep repeating the sound until you return to studying or dismiss the alert.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Toggle(isOn: $settings.repeatReminders) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat reminders")
                    Text("Nudge again if you stay distracted after the first alert.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if settings.repeatReminders {
                LabeledContent("Remind every") {
                    Stepper(value: $settings.repeatIntervalMinutes, in: 1...60, step: 1) {
                        Text("\(Int(settings.repeatIntervalMinutes)) min")
                            .monospacedDigit()
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                }
            }

            LabeledContent {
                Button("Send Test Alert") { model.alerts.preview() }
                    .buttonStyle(.lockInSoft(tint: Theme.accent))
            } label: {
                Text("See how it looks")
            }
        } header: {
            Text("Alerts")
        }
        .animation(Theme.smooth, value: settings.soundEnabled)
        .animation(Theme.smooth, value: settings.repeatReminders)
    }
}

// MARK: - Behavior

private struct BehaviorSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            Toggle("Show timer in the menu bar", isOn: $settings.showTimerInMenuBar)
            Toggle(isOn: $settings.pauseWhenAway) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause when the screen is locked or the Mac sleeps")
                    Text("Time away from your desk won't count as a distraction.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Launch Lock In at login", isOn: $settings.launchAtLogin)
            if let error = settings.launchAtLoginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Behavior")
        }
    }
}

// MARK: - Permissions

private struct PermissionsSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var notificationStatus: Bool?
    @State private var statusLoaded = false

    var body: some View {
        Section {
            permissionRow(
                title: "Accessibility",
                why: "Lets Lock In see which window is in front, so it can tell your lecture PDF from a random Preview window. Window titles are never stored.",
                granted: model.permissions.accessibilityGranted,
                statusText: model.permissions.accessibilityGranted ? "Allowed" : "Not allowed"
            ) {
                if !model.permissions.accessibilityGranted {
                    Button("Grant Access") { model.permissions.requestAccessibility() }
                        .buttonStyle(.lockInSoft(tint: Theme.accent))
                }
                Button("Open Settings") { model.permissions.openAccessibilitySettings() }
                    .buttonStyle(.lockInSoft)
            }

            permissionRow(
                title: "Notifications",
                why: "Lets Lock In send a banner when you've been away too long, even if the pop-up is off.",
                granted: notificationStatus == true,
                statusText: !statusLoaded ? "Checking…" : (notificationStatus == nil ? "Not asked yet" : (notificationStatus == true ? "Allowed" : "Not allowed"))
            ) {
                if notificationStatus == nil && statusLoaded {
                    Button("Allow") {
                        Task {
                            _ = await model.alerts.requestNotificationPermission()
                            await refreshNotifications()
                        }
                    }
                    .buttonStyle(.lockInSoft(tint: Theme.accent))
                } else if notificationStatus == false {
                    Button("Open Settings") { openNotificationSettings() }
                        .buttonStyle(.lockInSoft)
                }
            }

            ForEach(InstalledBrowsers.all, id: \.bundleID) { browser in
                browserRow(browser)
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("After rebuilding a development version of Lock In, macOS may need Accessibility granted again. Remove the old entry in System Settings, then add the app back.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await refreshNotifications() }
    }

    private func refreshNotifications() async {
        notificationStatus = await model.alerts.notificationPermissionStatus()
        statusLoaded = true
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private func browserRow(_ browser: BrowserInfo) -> some View {
        let state = model.permissions.automation[browser.bundleID] ?? .notDetermined
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            AppIconView(bundleID: browser.bundleID, size: 28, fallbackSymbol: "globe")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(browser.name) automation")
                    if browser.supportsTabURL { statusBadge(state) }
                }
                Text(browser.supportsTabURL
                     ? "Lets Lock In read the address of the active tab in \(browser.name) so websites can count as study spaces."
                     : "\(browser.name) can't share page addresses. Website study spaces use the window title keyword instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if browser.supportsTabURL {
                switch state {
                case .granted:
                    EmptyView()
                case .denied:
                    Button("Open Settings") { model.permissions.openAutomationSettings() }
                        .buttonStyle(.lockInSoft)
                case .notRunning:
                    Text("Open \(browser.name) first")
                        .font(.caption).foregroundStyle(.secondary)
                case .notDetermined:
                    Button("Allow") {
                        Task { _ = await model.permissions.requestAutomation(for: browser.bundleID) }
                    }
                    .buttonStyle(.lockInSoft(tint: Theme.accent))
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusBadge(_ state: PermissionsManager.AutomationState) -> some View {
        switch state {
        case .granted: badge("Allowed", Theme.studying)
        case .denied: badge("Denied", Theme.distracted)
        case .notDetermined: badge("Not asked yet", .secondary)
        case .notRunning: badge("Not running", .secondary)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.13)))
    }

    private func permissionRow<Actions: View>(
        title: String, why: String, granted: Bool, statusText: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(granted ? Theme.studying : Color.orange)
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                    badge(statusText, granted ? Theme.studying : .secondary)
                }
                Text(why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6, content: actions)
        }
        .padding(.vertical, 2)
        .animation(Theme.smooth, value: granted)
    }
}

// MARK: - Privacy

private struct PrivacySettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                privacyLine("checkmark.circle.fill", Theme.studying,
                            "Only the front app, its window title and the active browser tab address are read, and only during a session.")
                privacyLine("checkmark.circle.fill", Theme.studying,
                            "Saved: your study spaces, settings, session totals, and the name of each app you got distracted by.")
                privacyLine("xmark.circle.fill", Theme.distracted,
                            "Never saved: page addresses, window titles, keystrokes, or screenshots.")
                privacyLine("lock.shield.fill", Theme.accent,
                            "Everything stays on this Mac. Nothing is sent anywhere.")
            }
            .padding(.vertical, 2)

            LabeledContent {
                Button("Delete All History…", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.lockInSoft(tint: Theme.distracted))
                    .disabled(model.sessions.sessions.isEmpty)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session history")
                    Text(UIFormat.count(model.sessions.sessions.count, "session") + " saved")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Privacy")
        }
        .confirmationDialog("Delete all session history?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { model.sessions.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every saved session and your stats will be permanently removed. Your study spaces and settings are kept.")
        }
    }

    private func privacyLine(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 13)).padding(.top, 1)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - About

private struct AboutSettingsSection: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Section {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.brandGradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock In").font(.headline)
                    Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        } header: {
            Text("About")
        }
    }
}
