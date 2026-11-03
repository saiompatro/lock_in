import SwiftUI

struct WindowPickerTab: View {
    @Environment(AppModel.self) private var model
    let onAdd: ([StudySpace]) -> Void

    @State private var windows: [WindowCandidate] = []
    @State private var selectedID: WindowCandidate.ID?
    @State private var titleContains = ""
    @State private var refreshSpin = 0

    private var selected: WindowCandidate? { windows.first { $0.id == selectedID } }

    private var grouped: [(app: String, windows: [WindowCandidate])] {
        Dictionary(grouping: windows, by: \.appName)
            .map { (app: $0.key, windows: $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.app.localizedCaseInsensitiveCompare($1.app) == .orderedAscending }
    }

    var body: some View {
        Group {
            if model.permissions.accessibilityGranted {
                picker
            } else {
                permissionNeeded
            }
        }
        .onAppear {
            model.permissions.refresh()
            model.permissions.startPolling()
            if model.permissions.accessibilityGranted { reload() }
        }
        .onDisappear { model.permissions.stopPolling() }
        .onChange(of: model.permissions.accessibilityGranted) { _, granted in
            if granted { reload() }
        }
    }

    // MARK: Permission explainer

    private var permissionNeeded: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer()
            ZStack {
                Circle().fill(Color.orange.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
            }
            Text("Window detection needs Accessibility")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("To tell one window from another, Lock In reads window titles using macOS Accessibility. Titles are only compared with your study spaces during a session. They are never saved or sent anywhere.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            HStack {
                Button("Grant Access") { model.permissions.requestAccessibility() }
                    .buttonStyle(.lockInPrimary(expands: false))
                Button("Open System Settings") { model.permissions.openAccessibilitySettings() }
                    .buttonStyle(.lockInSoft)
            }
            Text("Tip: after rebuilding a development version of the app, macOS may ask you to grant access again.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.l)
    }

    // MARK: Picker

    private var picker: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Open windows")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    refreshSpin += 1
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(Double(refreshSpin) * 360))
                        .animation(.smooth(duration: 0.5), value: refreshSpin)
                }
                .buttonStyle(.lockInIcon)
                .help("Refresh")
                .accessibilityLabel("Refresh window list")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if windows.isEmpty {
                        VStack(spacing: 6) {
                            Text("No windows found")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Open the document or project you want to track, then press refresh.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(Theme.Spacing.xl)
                    }
                    ForEach(grouped, id: \.app) { group in
                        HStack(spacing: 8) {
                            AppIconView(bundleID: group.windows.first?.bundleID, size: 18)
                            Text(group.app)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, Theme.Spacing.xs)
                        .padding(.horizontal, Theme.Spacing.s)
                        ForEach(group.windows) { w in
                            SelectableRow(isSelected: selectedID == w.id, multiple: false) {
                                select(w)
                            } content: {
                                Image(systemName: "macwindow").foregroundStyle(.secondary)
                                Text(w.title).font(.system(size: 13)).lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.s)
            }

            if let selected {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title contains")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("e.g. Lecture 4", text: $titleContains)
                        .textFieldStyle(.roundedBorder)
                    Text("Any \(selected.appName) window whose title includes this text counts as studying. Keep it short so it still matches when the title changes slightly.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            AddFooter(
                summary: selected == nil ? "Choose a window" : selected!.appName,
                buttonTitle: "Add Window",
                enabled: selected != nil && !titleContains.trimmingCharacters(in: .whitespaces).isEmpty,
                action: commit
            )
        }
        .animation(Theme.smooth, value: selectedID)
    }

    private func select(_ window: WindowCandidate) {
        selectedID = window.id
        titleContains = SpaceFactory.smartTitleDefault(window.title)
    }

    private func reload() {
        let previous = selected?.title
        windows = SpaceCatalog.openWindows()
        if let previous, let match = windows.first(where: { $0.title == previous }) {
            selectedID = match.id
        } else {
            selectedID = nil
        }
    }

    private func commit() {
        guard let selected else { return }
        onAdd([SpaceFactory.window(selected, titleContains: titleContains)])
    }
}
