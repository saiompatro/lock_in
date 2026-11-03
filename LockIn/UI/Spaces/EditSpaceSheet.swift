import SwiftUI

struct EditSpaceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: StudySpace
    @State private var pattern: String

    init(space: StudySpace) {
        _draft = State(initialValue: space)
        _pattern = State(initialValue: space.urlPattern ?? "")
    }

    private var browsers: [BrowserInfo] { InstalledBrowsers.all }

    private var isValid: Bool {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        switch draft.kind {
        case .app: return true
        case .window: return !(draft.titleContains ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case .website: return !StudySpaceMatcher.normalizedPattern(pattern).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                SpaceIconView(space: draft, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Study Space")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    KindBadge(kind: draft.kind)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                field("Name") {
                    TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder)
                }

                switch draft.kind {
                case .app:
                    Callout(text: "Any window of \(draft.appName ?? draft.name) counts as studying.")
                case .window:
                    field("Title contains") {
                        TextField("e.g. Lecture 4", text: titleBinding).textFieldStyle(.roundedBorder)
                    }
                    Text("Windows of \(draft.appName ?? "this app") whose title includes this text count as studying.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                case .website:
                    field("Website") {
                        TextField("notion.so or docs.google.com/document", text: $pattern).textFieldStyle(.roundedBorder)
                    }
                    let normalized = StudySpaceMatcher.normalizedPattern(pattern)
                    if !normalized.isEmpty && normalized != pattern {
                        Text("Saved as \(normalized)")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    field("Browser") {
                        Picker("Browser", selection: Binding(
                            get: { draft.bundleID },
                            set: { id in
                                draft.bundleID = id
                                draft.appName = browsers.first { $0.bundleID == id }?.name
                            }
                        )) {
                            Text("Any browser").tag(String?.none)
                            ForEach(browsers, id: \.bundleID) { Text($0.name).tag(String?.some($0.bundleID)) }
                            if let id = draft.bundleID, !browsers.contains(where: { $0.bundleID == id }) {
                                Text(draft.appName ?? id).tag(String?.some(id))
                            }
                        }
                        .labelsHidden()
                    }
                    field("Title keyword") {
                        TextField("Optional fallback", text: titleBinding).textFieldStyle(.roundedBorder)
                    }
                    Text("Used when the page address can't be read, for example in Firefox or if Automation access is declined.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.lockInSoft)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.lockInPrimary(expands: false))
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 460, height: draft.kind == .website ? 470 : 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleBinding: Binding<String> {
        Binding(get: { draft.titleContains ?? "" }, set: { draft.titleContains = $0 })
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    private func save() {
        var result = draft
        result.name = result.name.trimmingCharacters(in: .whitespaces)
        switch result.kind {
        case .app:
            break
        case .window:
            result.titleContains = (result.titleContains ?? "").trimmingCharacters(in: .whitespaces)
        case .website:
            result.urlPattern = StudySpaceMatcher.normalizedPattern(pattern)
            let keyword = (result.titleContains ?? "").trimmingCharacters(in: .whitespaces)
            result.titleContains = keyword.isEmpty ? nil : keyword
        }
        model.updateSpace(result)
        dismiss()
    }
}
