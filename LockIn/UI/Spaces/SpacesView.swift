import SwiftUI

struct SpacesView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false
    @State private var editing: StudySpace?
    @State private var deleting: StudySpace?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                PageHeader(
                    title: "Study Spaces",
                    subtitle: subtitle
                ) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Study Space", systemImage: "plus")
                    }
                    .buttonStyle(.lockInPrimary(expands: false))
                    .keyboardShortcut("n")
                }

                if model.spaces.spaces.isEmpty {
                    EmptyStateView(
                        symbol: "square.stack.3d.up",
                        title: "Where do you study?",
                        message: "Add the apps, windows, or websites that count as studying. When you leave them during a session, Lock In starts a quiet timer.",
                        actionTitle: "Add Study Space",
                        action: { showingAdd = true }
                    )
                    .card()
                } else {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(model.spaces.spaces) { space in
                            SpaceRow(
                                space: space,
                                onEdit: { editing = space },
                                onDelete: { deleting = space }
                            )
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                    removal: .opacity.combined(with: .scale(scale: 0.96))))
                        }
                    }
                    .animation(Theme.smooth, value: model.spaces.spaces.map(\.id))

                    Callout(text: "Spaces that are switched off stay saved but don't count as studying. If you're in none of the enabled spaces, the distraction timer runs.")
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.s)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingAdd) {
            AddSpaceSheet()
        }
        .sheet(item: $editing) { space in
            EditSpaceSheet(space: space)
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { space in
            Button("Delete", role: .destructive) {
                withAnimation(Theme.smooth) { model.removeSpace(id: space.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Lock In will stop treating it as a study space. You can add it again any time.")
        }
    }

    private var subtitle: String {
        let all = model.spaces.spaces.count
        if all == 0 { return "Tell Lock In what counts as studying" }
        let enabled = model.spaces.enabledSpaces.count
        return "\(enabled) of \(UIFormat.count(all, "space")) active"
    }
}

// MARK: - Row

private struct SpaceRow: View {
    @Environment(AppModel.self) private var model
    let space: StudySpace
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            SpaceIconView(space: space, size: 40)
                .opacity(space.isEnabled ? 1 : 0.5)
                .saturation(space.isEnabled ? 1 : 0.3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(space.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    KindBadge(kind: space.kind)
                }
                Text(space.detailText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(space.isEnabled ? 1 : 0.55)

            Spacer(minLength: Theme.Spacing.s)

            HStack(spacing: 2) {
                Button { model.open(space) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.lockInIcon)
                    .help("Open")
                    .accessibilityLabel("Open \(space.name)")
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .buttonStyle(.lockInIcon)
                    .help("Edit")
                    .accessibilityLabel("Edit \(space.name)")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.lockInIcon(tint: Theme.distracted))
                    .help("Delete")
                    .accessibilityLabel("Delete \(space.name)")
            }
            .opacity(hovering ? 1 : 0.55)

            Toggle("Enabled", isOn: Binding(
                get: { space.isEnabled },
                set: { model.setSpaceEnabled($0, id: space.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("\(space.name) enabled")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(hovering ? Theme.accent.opacity(0.35) : Theme.cardStroke, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app") { model.open(space) }
            Button("Edit…", systemImage: "pencil", action: onEdit)
            Button(space.isEnabled ? "Turn Off" : "Turn On",
                   systemImage: space.isEnabled ? "pause.circle" : "play.circle") {
                model.setSpaceEnabled(!space.isEnabled, id: space.id)
            }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}
