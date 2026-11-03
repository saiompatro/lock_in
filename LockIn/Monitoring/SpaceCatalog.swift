import AppKit
import ApplicationServices

// MARK: - Catalog (for the "Add study space" picker)

struct AppCandidate: Identifiable, Hashable, Sendable {
    var bundleID: String
    var name: String
    var url: URL?
    var id: String { bundleID }
}

struct WindowCandidate: Identifiable, Hashable, Sendable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var title: String
}

struct TabCandidate: Identifiable, Hashable, Sendable {
    var id = UUID()
    var browserBundleID: String
    var browserName: String
    var title: String
    var url: URL
}

enum SpaceCatalog {
    private static let tabRunner = AppleScriptRunner(label: "com.lockin.catalog.applescript")

    private static func byName(_ a: AppCandidate, _ b: AppCandidate) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// Regular (Dock) apps currently running, excluding Lock In.
    @MainActor static func runningApps() -> [AppCandidate] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var result: [AppCandidate] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != own, !app.isTerminated, seen.insert(id).inserted else { continue }
            let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? id
            result.append(AppCandidate(bundleID: id, name: name, url: app.bundleURL))
        }
        return result.sorted(by: byName)
    }

    /// Apps in /Applications, /System/Applications, ~/Applications (one level + .app bundles in subfolders).
    static func installedApps() -> [AppCandidate] {
        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var result: [AppCandidate] = []

        func consider(_ url: URL) {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != own else { return }
            let info = bundle.infoDictionary ?? [:]
            if (info["LSBackgroundOnly"] as? Bool) == true || (info["LSBackgroundOnly"] as? String) == "1" { return }
            guard seen.insert(id).inserted else { return }
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            result.append(AppCandidate(bundleID: id, name: name, url: url))
        }

        let keys: [URLResourceKey] = [.isDirectoryKey]
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys,
                                                            options: [.skipsHiddenFiles]) else { continue }
            for entry in entries {
                if entry.pathExtension == "app" {
                    consider(entry)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          let inner = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles]) {
                    for item in inner where item.pathExtension == "app" { consider(item) }
                }
            }
        }
        return result.sorted(by: byName)
    }

    /// Titled windows of running apps (requires Accessibility). Minimized windows included.
    @MainActor static func openWindows() -> [WindowCandidate] {
        guard AXIsProcessTrusted() else { return [] }
        let own = Bundle.main.bundleIdentifier
        var result: [WindowCandidate] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != own, !app.isTerminated else { continue }
            let name = app.localizedName ?? id
            var titles = Set<String>()
            for window in AX.windows(pid: app.processIdentifier) {
                guard let title = AX.string(window, kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty, titles.insert(title).inserted else { continue }
                result.append(WindowCandidate(bundleID: id, appName: name, title: title))
            }
        }
        return result.sorted {
            if $0.appName != $1.appName { return $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// Tabs of running supported browsers (requires Automation; may prompt).
    static func openTabs() async -> [TabCandidate] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let browsers = SupportedBrowsers.all.filter { $0.supportsTabURL && running.contains($0.bundleID) }
        return await withTaskGroup(of: [TabCandidate].self) { group in
            for browser in browsers {
                group.addTask { await tabs(of: browser) }
            }
            var all: [TabCandidate] = []
            for await tabs in group { all.append(contentsOf: tabs) }
            return all.sorted {
                if $0.browserName != $1.browserName { return $0.browserName < $1.browserName }
                return false
            }
        }
    }

    private static func tabs(of browser: BrowserInfo) async -> [TabCandidate] {
        let titleProperty = browser.dialect == .safari ? "name" : "title"
        // Returns {{titles of window 1, urls of window 1}, {titles of window 2, ...}}.
        let source = """
        tell application id "\(browser.bundleID)"
            if it is running then
                with timeout of 5 seconds
                    set out to {}
                    repeat with w in windows
                        try
                            set end of out to {\(titleProperty) of tabs of w, URL of tabs of w}
                        end try
                    end repeat
                    return out
                end timeout
            end if
        end tell
        return {}
        """
        let bundleID = browser.bundleID
        let name = browser.name
        let result = await tabRunner.run(key: "tabs:" + bundleID, source: source) { descriptor in
            parseTabs(descriptor, bundleID: bundleID, name: name)
        }
        if case .success(let tabs) = result { return tabs }
        return []
    }

    private static func parseTabs(_ descriptor: NSAppleEventDescriptor, bundleID: String, name: String) -> [TabCandidate] {
        var tabs: [TabCandidate] = []
        guard descriptor.numberOfItems > 0 else { return tabs }
        for w in 1...descriptor.numberOfItems {
            guard let window = descriptor.atIndex(w), window.numberOfItems >= 2,
                  let titles = window.atIndex(1), let urls = window.atIndex(2) else { continue }
            let count = min(titles.numberOfItems, urls.numberOfItems)
            guard count > 0 else { continue }
            for i in 1...count {
                guard let urlString = urls.atIndex(i)?.stringValue,
                      let url = URL(string: urlString),
                      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
                let title = titles.atIndex(i)?.stringValue ?? ""
                tabs.append(TabCandidate(browserBundleID: bundleID, browserName: name,
                                         title: title.isEmpty ? (url.host(percentEncoded: false) ?? urlString) : title,
                                         url: url))
            }
        }
        return tabs
    }
}
