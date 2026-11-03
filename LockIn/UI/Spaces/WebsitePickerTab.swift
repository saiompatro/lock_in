import SwiftUI

struct WebsitePickerTab: View {
    @Environment(AppModel.self) private var model
    let onAdd: ([StudySpace]) -> Void

    private enum Scope: String, CaseIterable, Identifiable {
        case site, page
        var id: String { rawValue }
        var title: String { self == .site ? "Whole site (domain)" : "This page only (URL prefix)" }
    }

    @State private var tabs: [TabCandidate] = []
    @State private var loading = true
    @State private var selectedTabs = Set<TabCandidate.ID>()
    @State private var scope: Scope = .site
    @State private var manual = ""
    @State private var browserID: String?
    @State private var keyword = ""

    private var browsers: [BrowserInfo] { InstalledBrowsers.all }
    private var selectedBrowser: BrowserInfo? { browsers.first { $0.bundleID == browserID } }
    private var hasKeywordOnlyBrowser: Bool { browsers.contains { !$0.supportsTabURL } }

    private var manualPattern: String {
        let trimmed = manual.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : StudySpaceMatcher.normalizedPattern(trimmed)
    }

    private var pendingCount: Int { selectedTabs.count + (manualPattern.isEmpty ? 0 : 1) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    tabsSection
                    manualSection
                    optionsSection
                }
                .padding(Theme.Spacing.l)
            }
            AddFooter(
                summary: pendingCount == 0 ? "Pick a tab or type a website" : "\(pendingCount) to add",
                buttonTitle: pendingCount > 1 ? "Add \(pendingCount) Websites" : "Add Website",
                enabled: pendingCount > 0,
                action: commit
            )
        }
        .task { await loadTabs() }
        .onAppear { model.permissions.refresh() }
    }

    // MARK: Open tabs

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Open tabs")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { Task { await loadTabs() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.lockInIcon)
                .disabled(loading)
                .help("Refresh")
                .accessibilityLabel("Refresh tab list")
            }

            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking at your browsers…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.s)
            } else if tabs.isEmpty {
                Callout(
                    symbol: "info.circle.fill",
                    text: "No open tabs found. Lock In asks each browser for its tabs through macOS Automation, and macOS shows a one-time permission prompt for every browser. Open a site in Safari, Chrome, Arc or another supported browser, then refresh. Or type a website below."
                )
            } else {
                VStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        SelectableRow(isSelected: selectedTabs.contains(tab.id)) {
                            if selectedTabs.contains(tab.id) { selectedTabs.remove(tab.id) } else { selectedTabs.insert(tab.id) }
                        } content: {
                            AppIconView(bundleID: tab.browserBundleID, size: 26, fallbackSymbol: "globe")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tab.title.isEmpty ? (tab.url.host(percentEncoded: false) ?? "Untitled") : tab.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Text(displayURL(tab.url))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                if !selectedTabs.isEmpty {
                    Picker("Match", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 6)
                    Text(scope == .site
                         ? "Anything on that site counts as studying, including its subdomains."
                         : "Only pages whose address starts with this one count as studying.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(Theme.smooth, value: selectedTabs.isEmpty)
    }

    // MARK: Manual

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Or enter a website")
                .font(.system(size: 13, weight: .semibold))
            TextField("e.g. notion.so or docs.google.com/document", text: $manual)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if pendingCount > 0 { commit() } }
            if manualPattern.isEmpty {
                Text("Use just a domain to include the whole site, or add a path to narrow it to one section.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.studying)
                    Text("Will match: ")
                        .foregroundStyle(.secondary)
                    + Text(manualPattern).fontWeight(.semibold)
                }
                .font(.system(size: 12))
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: manualPattern)
    }

    // MARK: Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Options")
                .font(.system(size: 13, weight: .semibold))

            LabeledContent("Browser") {
                Picker("Browser", selection: $browserID) {
                    Text("Any browser").tag(String?.none)
                    ForEach(browsers, id: \.bundleID) { b in
                        Text(b.name).tag(String?.some(b.bundleID))
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Fallback title keyword") {
                    TextField("Optional", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                Text("Some browsers, like Firefox, can't tell Lock In which page is open. For those (or if you decline the Automation prompt), Lock In falls back to matching this keyword against the browser window's title.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasKeywordOnlyBrowser && keyword.trimmingCharacters(in: .whitespaces).isEmpty {
                Callout(symbol: "exclamationmark.triangle.fill", tint: .orange,
                        text: "Firefox-style browsers are installed. Add a title keyword if you want this site to count there.")
            }
            if model.permissions.automation.values.contains(.denied) {
                HStack {
                    Callout(symbol: "lock.slash.fill", tint: .orange,
                            text: "Automation access was denied for a browser, so Lock In can't read its page addresses.")
                    Button("Open Settings") { model.permissions.openAutomationSettings() }
                        .buttonStyle(.lockInSoft)
                }
            }
        }
    }

    // MARK: Actions

    private func loadTabs() async {
        loading = true
        let found = await SpaceCatalog.openTabs()
        tabs = found
        selectedTabs = selectedTabs.filter { id in found.contains { $0.id == id } }
        loading = false
    }

    private func displayURL(_ url: URL) -> String {
        let host = (url.host(percentEncoded: false) ?? "").replacingOccurrences(of: "www.", with: "")
        let path = url.path == "/" ? "" : url.path
        return host + path
    }

    private func commit() {
        var spaces: [StudySpace] = []
        var seen = Set<String>()
        for tab in tabs where selectedTabs.contains(tab.id) {
            let pattern: String
            switch scope {
            case .site:
                let host = (tab.url.host(percentEncoded: false) ?? "").lowercased()
                pattern = StudySpaceMatcher.normalizedPattern(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
            case .page:
                pattern = StudySpaceMatcher.normalizedPattern(tab.url.absoluteString)
            }
            guard !pattern.isEmpty, seen.insert(pattern).inserted else { continue }
            spaces.append(SpaceFactory.website(pattern: pattern, browser: selectedBrowser, titleKeyword: keyword))
        }
        if !manualPattern.isEmpty, seen.insert(manualPattern).inserted {
            spaces.append(SpaceFactory.website(pattern: manualPattern, browser: selectedBrowser, titleKeyword: keyword))
        }
        guard !spaces.isEmpty else { return }
        onAdd(spaces)
    }
}
