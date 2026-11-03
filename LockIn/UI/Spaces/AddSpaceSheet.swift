import SwiftUI

/// Sheet for adding study spaces: segmented App / Window / Website.
struct AddSpaceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: StudySpaceKind = .app

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Study Space")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(blurb)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .animation(nil, value: kind)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.lockInIcon)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.s)

            Picker("Kind", selection: $kind) {
                Text("App").tag(StudySpaceKind.app)
                Text("Window").tag(StudySpaceKind.window)
                Text("Website").tag(StudySpaceKind.website)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.s)

            Divider()

            Group {
                switch kind {
                case .app: AppPickerTab(onAdd: add)
                case .window: WindowPickerTab(onAdd: add)
                case .website: WebsitePickerTab(onAdd: add)
                }
            }
            .id(kind)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: kind)
        .frame(width: 580, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var blurb: String {
        switch kind {
        case .app: "Any window of the apps you choose counts as studying."
        case .window: "Only a specific window counts, like one document or project."
        case .website: "A site or page open in your browser counts as studying."
        }
    }

    private func add(_ spaces: [StudySpace]) {
        for space in spaces { model.addSpace(space) }
        dismiss()
    }
}

/// Sticky footer shared by the picker tabs.
struct AddFooter: View {
    var summary: String
    var buttonTitle: String
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                Button(buttonTitle, action: action)
                    .buttonStyle(.lockInPrimary(expands: false))
                    .disabled(!enabled)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
        }
        .background(.bar)
    }
}

// MARK: - App tab

struct AppPickerTab: View {
    @Environment(AppModel.self) private var model
    let onAdd: ([StudySpace]) -> Void

    @State private var running: [AppCandidate] = []
    @State private var installed: [AppCandidate] = []
    @State private var loading = true
    @State private var search = ""
    @State private var selection = Set<String>()

    private var alreadyAdded: Set<String> {
        Set(model.spaces.spaces.filter { $0.kind == .app }.compactMap(\.bundleID))
    }

    private func filtered(_ list: [AppCandidate]) -> [AppCandidate] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var runningFiltered: [AppCandidate] { filtered(running) }
    private var otherInstalled: [AppCandidate] {
        let runningIDs = Set(running.map(\.bundleID))
        return filtered(installed.filter { !runningIDs.contains($0.bundleID) })
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if !runningFiltered.isEmpty {
                        CaptionHeader(text: "Running now")
                            .padding(.vertical, 6)
                        ForEach(runningFiltered) { row($0) }
                    }
                    if !otherInstalled.isEmpty {
                        CaptionHeader(text: "All applications")
                            .padding(.top, Theme.Spacing.s)
                            .padding(.bottom, 6)
                        ForEach(otherInstalled) { row($0) }
                    }
                    if loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Finding installed apps…")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(Theme.Spacing.m)
                    } else if runningFiltered.isEmpty && otherInstalled.isEmpty {
                        Text(search.isEmpty ? "No apps found." : "No apps match “\(search)”.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(Theme.Spacing.xl)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.s)
            }

            AddFooter(
                summary: selection.isEmpty ? "Select one or more apps" : "\(selection.count) selected",
                buttonTitle: selection.count > 1 ? "Add \(selection.count) Apps" : "Add App",
                enabled: !selection.isEmpty,
                action: commit
            )
        }
        .task {
            running = SpaceCatalog.runningApps().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            installed = await Task.detached(priority: .userInitiated) {
                SpaceCatalog.installedApps().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }.value
            loading = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search apps", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.subtleFill))
    }

    private func row(_ app: AppCandidate) -> some View {
        SelectableRow(
            isSelected: selection.contains(app.bundleID),
            isDisabled: alreadyAdded.contains(app.bundleID),
            action: {
                if selection.contains(app.bundleID) { selection.remove(app.bundleID) } else { selection.insert(app.bundleID) }
            }
        ) {
            CandidateIconView(candidate: app, size: 28)
            Text(app.name).font(.system(size: 13.5))
        }
    }

    private func commit() {
        let all = running + installed
        var seen = Set<String>()
        let spaces: [StudySpace] = all.compactMap { app in
            guard selection.contains(app.bundleID), seen.insert(app.bundleID).inserted else { return nil }
            return SpaceFactory.app(app)
        }
        onAdd(spaces)
    }
}

// MARK: - Factory

enum SpaceFactory {
    static func app(_ c: AppCandidate) -> StudySpace {
        StudySpace(kind: .app, name: c.name, bundleID: c.bundleID, appName: c.name)
    }

    static func window(_ w: WindowCandidate, titleContains: String) -> StudySpace {
        let keyword = titleContains.trimmingCharacters(in: .whitespaces)
        return StudySpace(kind: .window, name: keyword.isEmpty ? w.appName : keyword,
                          bundleID: w.bundleID, appName: w.appName, titleContains: keyword)
    }

    static func website(pattern: String, browser: BrowserInfo?, titleKeyword: String) -> StudySpace {
        let keyword = titleKeyword.trimmingCharacters(in: .whitespaces)
        return StudySpace(kind: .website, name: pattern, bundleID: browser?.bundleID, appName: browser?.name,
                          titleContains: keyword.isEmpty ? nil : keyword, urlPattern: pattern)
    }

    /// "Lecture 4.pdf — Preview" -> "Lecture 4.pdf". Falls back to the whole title.
    static func smartTitleDefault(_ title: String) -> String {
        let separators = [" — ", " – ", " - ", " | ", " · "]
        var best = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in separators {
            if let range = best.range(of: sep) {
                let head = String(best[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if head.count >= 3 { best = head }
                break
            }
        }
        return best
    }
}
