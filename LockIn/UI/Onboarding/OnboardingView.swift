import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    private enum Step: Int, CaseIterable {
        case welcome, permissions, spaces, done
    }

    @State private var step: Step = .welcome
    @State private var goingForward = true

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if step != .done {
                        Button("Skip") { model.completeOnboarding() }
                            .buttonStyle(.lockInSoft)
                            .help("You can set everything up later")
                    }
                }
                .frame(height: 28)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)

                ZStack {
                    switch step {
                    case .welcome: WelcomeStep().transition(transition)
                    case .permissions: PermissionsStep().transition(transition)
                    case .spaces: SpacesStep().transition(transition)
                    case .done: DoneStep().transition(transition)
                    }
                }
                .frame(maxWidth: 560, maxHeight: .infinity)
                .padding(.horizontal, Theme.Spacing.l)

                footer
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.l)
            }
        }
        .animation(.smooth(duration: 0.45), value: step)
        .onAppear {
            model.permissions.refresh()
            model.permissions.startPolling()
        }
        .onDisappear { model.permissions.stopPolling() }
    }

    private var transition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.violet.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                move(-1)
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.lockInSoft)
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)

            Spacer()

            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s == step ? Theme.accent : Color.primary.opacity(0.15))
                        .frame(width: s == step ? 22 : 7, height: 7)
                }
            }
            .animation(Theme.smooth, value: step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            Spacer()

            if step == .done {
                Color.clear.frame(width: 90, height: 1)
            } else {
                Button {
                    move(1)
                } label: {
                    Text(step == .welcome ? "Get Started" : "Continue")
                }
                .buttonStyle(.lockInPrimary(expands: false))
                .keyboardShortcut(.defaultAction)
                .frame(minWidth: 90)
            }
        }
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        goingForward = delta > 0
        withAnimation(.smooth(duration: 0.45)) { step = next }
    }
}

// MARK: - Shared step layout

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 148, height: 148)
                    .scaleEffect(appeared ? 1.08 : 0.9)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: appeared)
                Image(systemName: "lock.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 112, height: 112)
                    .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.brandGradient))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 22, y: 10)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
            }

            StepHeader(title: "Welcome to Lock In",
                       subtitle: "A quiet menu bar companion that notices when you drift away from your work, and gently brings you back.")

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                feature("square.stack.3d.up", "Choose your study spaces",
                        "Apps, windows or websites that count as studying.")
                feature("timer", "Study as you normally would",
                        "Leave them and a silent timer starts. No nagging.")
                feature("bell.badge", "Get a nudge when it matters",
                        "After a few minutes away, you'll get an alert.")
            }
            .padding(.top, Theme.Spacing.xs)
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.35)) { appeared = true }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 420)
    }
}

// MARK: - Permissions

private struct PermissionsStep: View {
    @Environment(AppModel.self) private var model
    @State private var notificationStatus: Bool?

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer(minLength: 0)
            StepHeader(title: "A couple of permissions",
                       subtitle: "Lock In works best with these. Everything stays on your Mac.")

            VStack(spacing: Theme.Spacing.s) {
                card(
                    symbol: "macwindow.badge.plus", title: "Accessibility",
                    detail: "Lets Lock In see which window is in front, so a specific document or project can count as studying. Window titles are never saved.",
                    granted: model.permissions.accessibilityGranted
                ) {
                    Button("Grant Access") { model.permissions.requestAccessibility() }
                        .buttonStyle(.lockInPrimary(expands: false))
                }
                card(
                    symbol: "bell.badge.fill", title: "Notifications",
                    detail: "Lets Lock In send a banner when you've been away for too long.",
                    granted: notificationStatus == true
                ) {
                    Button("Allow") {
                        Task {
                            _ = await model.alerts.requestNotificationPermission()
                            notificationStatus = await model.alerts.notificationPermissionStatus()
                        }
                    }
                    .buttonStyle(.lockInPrimary(expands: false))
                }
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Image(systemName: "safari.fill")
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    Text("Browser access is asked for later, the first time you add a website as a study space.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }

            Text("If you rebuild a development version of the app, macOS may ask you to grant Accessibility again.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .task { notificationStatus = await model.alerts.notificationPermissionStatus() }
    }

    private func card<Action: View>(
        symbol: String, title: String, detail: String, granted: Bool,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.xs)
            ZStack {
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.studying)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .accessibilityLabel("\(title) allowed")
                } else {
                    action().transition(.opacity)
                }
            }
            .frame(minWidth: 90, alignment: .trailing)
        }
        .animation(.spring(duration: 0.5, bounce: 0.3), value: granted)
        .card(padding: Theme.Spacing.m)
    }
}

// MARK: - Spaces

private struct SpacesStep: View {
    @Environment(AppModel.self) private var model
    @State private var apps: [AppCandidate] = []
    @State private var website = ""

    private var addedAppIDs: [String: UUID] {
        Dictionary(model.spaces.spaces.filter { $0.kind == .app }.compactMap { s in s.bundleID.map { ($0, s.id) } },
                   uniquingKeysWith: { a, _ in a })
    }

    private var websites: [StudySpace] { model.spaces.spaces.filter { $0.kind == .website } }

    private var pattern: String {
        let trimmed = website.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : StudySpaceMatcher.normalizedPattern(trimmed)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
            StepHeader(title: "Where do you study?",
                       subtitle: "Pick a few apps you're running, or add a website. You can fine-tune this any time.")

            if apps.isEmpty {
                Text("Open the apps you study with and they'll show up here.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(Theme.Spacing.m)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.xs)], spacing: Theme.Spacing.xs) {
                        ForEach(apps) { app in appChip(app) }
                    }
                    .padding(2)
                }
                .frame(maxHeight: 190)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.Spacing.xs) {
                    TextField("Add a website, e.g. notion.so", text: $website)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addWebsite)
                    Button("Add", action: addWebsite)
                        .buttonStyle(.lockInSoft(tint: Theme.accent))
                        .disabled(pattern.isEmpty)
                }
                if !websites.isEmpty {
                    FlowChips(items: websites) { site in
                        HStack(spacing: 5) {
                            Image(systemName: "globe").font(.system(size: 10, weight: .semibold))
                            Text(site.urlPattern ?? site.name).font(.system(size: 12, weight: .medium))
                            Button { model.removeSpace(id: site.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(site.name)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.studying.opacity(0.14)))
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: 460)
            .animation(Theme.smooth, value: websites.map(\.id))
            Spacer(minLength: 0)
        }
        .task {
            apps = SpaceCatalog.runningApps().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func appChip(_ app: AppCandidate) -> some View {
        let id = addedAppIDs[app.bundleID]
        let selected = id != nil
        return Button {
            if let id { model.removeSpace(id: id) } else { model.addSpace(SpaceFactory.app(app)) }
        } label: {
            HStack(spacing: 8) {
                CandidateIconView(candidate: app, size: 22)
                Text(app.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(selected ? Theme.accent : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.13) : Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.5) : Theme.cardStroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.snappy, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func addWebsite() {
        guard !pattern.isEmpty else { return }
        model.addSpace(SpaceFactory.website(pattern: pattern, browser: nil, titleKeyword: ""))
        website = ""
    }
}

/// Simple wrapping layout for chips.
private struct FlowChips<Item: Identifiable, Chip: View>: View {
    let items: [Item]
    @ViewBuilder var chip: (Item) -> Chip

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { chip($0) }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Done

private struct DoneStep: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    var body: some View {
        let count = model.spaces.enabledSpaces.count
        VStack(spacing: Theme.Spacing.l) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Theme.studying.opacity(0.15))
                    .frame(width: 128, height: 128)
                    .scaleEffect(appeared ? 1 : 0.5)
                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Theme.studying)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
            }
            StepHeader(
                title: "You're all set",
                subtitle: count > 0
                    ? "\(UIFormat.count(count, "study space")) ready. Lock In lives in your menu bar. Click the lock icon any time to start or stop a session."
                    : "Lock In lives in your menu bar. Add a study space from the Study Spaces page, then start your first session."
            )
            VStack(spacing: Theme.Spacing.xs) {
                if count > 0 {
                    Button {
                        model.completeOnboarding()
                        model.startSession()
                    } label: {
                        Label("Start your first session", systemImage: "play.fill")
                    }
                    .buttonStyle(.lockInPrimary(expands: false))
                    .keyboardShortcut(.defaultAction)
                    Button("Explore the dashboard first") { model.completeOnboarding() }
                        .buttonStyle(.lockInSoft)
                } else {
                    Button("Add study spaces") { model.completeOnboarding() }
                        .buttonStyle(.lockInPrimary(expands: false))
                        .keyboardShortcut(.defaultAction)
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.45)) { appeared = true } }
    }
}
