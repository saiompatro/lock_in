import AppKit
import SwiftUI

/// Content of the menu bar panel (MenuBarExtra, `.window` style).
struct MenuBarContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xs)

            if !model.permissions.accessibilityGranted {
                permissionBanner
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.top, Theme.Spacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SessionHeroView()
                .padding(.vertical, Theme.Spacing.l)
                .padding(.horizontal, Theme.Spacing.m)

            SessionStatsRow()
                .padding(.horizontal, Theme.Spacing.m)

            SessionControls(inMenuBar: true)
                .padding(Theme.Spacing.m)

            Divider().opacity(0.6)

            QuickSpacesList()
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 6)

            Divider().opacity(0.6)

            footer
                .padding(Theme.Spacing.xs)
        }
        .frame(width: 320)
        .animation(Theme.smooth, value: model.status)
        .animation(Theme.smooth, value: model.permissions.accessibilityGranted)
        .onAppear {
            model.permissions.refresh()
            model.permissions.startPolling()
        }
        .onDisappear { model.permissions.stopPolling() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.brandGradient))
            Text("Lock In")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            StatusPill(status: model.status, label: pillLabel)
        }
    }

    private var pillLabel: String? {
        guard model.status == .paused else { return nil }
        if case .onBreak = model.engine.pauseReason { return "On break" }
        return nil
    }

    // MARK: Permission banner

    private var permissionBanner: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text("Limited detection")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Grant access") { model.permissions.requestAccessibility() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Button { openMain(.overview) } label: {
                Label("Dashboard", systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(.lockInRow)
            Button { openMain(.settings) } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.lockInRow)
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .accessibilityLabel("Quit Lock In")
            }
            .buttonStyle(.lockInRow(tint: .secondary))
            .frame(width: 44)
            .help("Quit Lock In")
            .keyboardShortcut("q")
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func openMain(_ section: MainSection) {
        MenuBarPanel.dismiss()
        model.openMainWindow(section)
    }
}

// MARK: - Quick spaces list

struct QuickSpacesList: View {
    @Environment(AppModel.self) private var model
    @AppStorage("menuSpacesExpanded") private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(Theme.smooth) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Study spaces")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("\(model.spaces.enabledSpaces.count)/\(model.spaces.spaces.count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.s)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Study spaces, \(expanded ? "expanded" : "collapsed")")

            if expanded {
                VStack(spacing: 0) {
                    if model.spaces.spaces.isEmpty {
                        Text("No study spaces yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, 6)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(model.spaces.spaces) { space in
                                    QuickSpaceRow(space: space)
                                }
                            }
                        }
                        .frame(maxHeight: 156)
                        .fixedSize(horizontal: false, vertical: model.spaces.spaces.count <= 5)
                    }
                    Button { manage() } label: {
                        Label("Manage…", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.lockInRow(tint: Theme.accent))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    private func manage() {
        MenuBarPanel.dismiss()
        model.openMainWindow(.spaces)
    }
}

private struct QuickSpaceRow: View {
    @Environment(AppModel.self) private var model
    let space: StudySpace
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            SpaceIconView(space: space, size: 22)
            Text(space.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .foregroundStyle(space.isEnabled ? .primary : .secondary)
            Spacer(minLength: 4)
            Toggle("Enabled", isOn: Binding(
                get: { space.isEnabled },
                set: { model.setSpaceEnabled($0, id: space.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .accessibilityLabel("\(space.name) enabled")
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(space.detailText)
    }
}
