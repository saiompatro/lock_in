import SwiftUI

/// Root of the main window: onboarding on first launch, otherwise sidebar + detail.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if model.showOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainSplitView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.showOnboarding)
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MainSplitView: View {
    @Environment(AppModel.self) private var model

    private var selection: Binding<MainSection?> {
        Binding(
            get: { model.selectedSection },
            set: { if let value = $0 { model.selectedSection = value } }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar(removing: .sidebarToggle)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .overview: OverviewView()
        case .spaces: SpacesView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: MainSection?

    var body: some View {
        List(MainSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.symbolName)
                .font(.system(size: 13.5, weight: .medium))
                .padding(.vertical, 3)
                .tag(section)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.brandGradient))
                Text("Lock In")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarSessionCard()
                .padding(Theme.Spacing.s)
        }
    }
}

/// Mini session status + quick action pinned to the bottom of the sidebar.
private struct SidebarSessionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = model.now
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                StatusPill(status: model.status)
                Spacer()
                if model.isSessionActive {
                    Text(DurationFormat.clock(model.engine.focusedTime(at: now)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            if model.isSessionActive {
                Button { model.stopSession() } label: {
                    Label("End session", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.lockInSoft(tint: Theme.distracted, expands: true))
            } else {
                Button { model.startSession() } label: {
                    Label("Start session", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.lockInPrimary)
                .disabled(!model.canStartSession)
            }
        }
        .padding(Theme.Spacing.s)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.subtleFill))
        .animation(Theme.smooth, value: model.isSessionActive)
    }
}
