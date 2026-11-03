import AppKit

/// Which AppleScript vocabulary a browser understands.
enum BrowserScriptDialect: String, Hashable, Sendable {
    /// Safari-style: `URL of current tab of front window`, `name of tab`.
    case safari
    /// Chromium-style: `URL of active tab of front window`, `title of tab`.
    case chromium
    /// No usable scripting dictionary (Firefox, Zen).
    case unsupported
}

struct BrowserInfo: Hashable, Sendable {
    let bundleID: String
    let name: String
    /// Whether the active tab URL can be read via AppleScript.
    let supportsTabURL: Bool
    var dialect: BrowserScriptDialect = .chromium

    init(bundleID: String, name: String, supportsTabURL: Bool, dialect: BrowserScriptDialect? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.supportsTabURL = supportsTabURL
        self.dialect = dialect ?? (supportsTabURL ? .chromium : .unsupported)
    }

    /// AppleScript expression for the URL of the active tab of the front window.
    var activeTabURLExpression: String? {
        switch dialect {
        case .safari: "URL of current tab of front window"
        case .chromium: "URL of active tab of front window"
        case .unsupported: nil
        }
    }
}

enum SupportedBrowsers {
    static let all: [BrowserInfo] = [
        BrowserInfo(bundleID: "com.apple.Safari", name: "Safari", supportsTabURL: true, dialect: .safari),
        BrowserInfo(bundleID: "com.apple.SafariTechnologyPreview", name: "Safari Technology Preview", supportsTabURL: true, dialect: .safari),
        BrowserInfo(bundleID: "com.google.Chrome", name: "Google Chrome", supportsTabURL: true, dialect: .chromium),
        BrowserInfo(bundleID: "com.google.Chrome.beta", name: "Chrome Beta", supportsTabURL: true, dialect: .chromium),
        BrowserInfo(bundleID: "com.google.Chrome.canary", name: "Chrome Canary", supportsTabURL: true, dialect: .chromium),
        BrowserInfo(bundleID: "company.thebrowser.Browser", name: "Arc", supportsTabURL: true, dialect: .chromium),
        BrowserInfo(bundleID: "com.brave.Browser", name: "Brave", supportsTabURL: true, dialect: .chromium),
        BrowserInfo(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", supportsTabURL: true, dialect: .chromium),
        BrowserInfo(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", supportsTabURL: true, dialect: .chromium),
        BrowserInfo(bundleID: "com.operasoftware.Opera", name: "Opera", supportsTabURL: true, dialect: .chromium),
        BrowserInfo(bundleID: "org.chromium.Chromium", name: "Chromium", supportsTabURL: true, dialect: .chromium),
        BrowserInfo(bundleID: "com.kagi.kagimacOS", name: "Orion", supportsTabURL: true, dialect: .safari),
        BrowserInfo(bundleID: "org.mozilla.firefox", name: "Firefox", supportsTabURL: false, dialect: .unsupported),
        BrowserInfo(bundleID: "app.zen-browser.zen", name: "Zen", supportsTabURL: false, dialect: .unsupported),
    ]

    static func info(for bundleID: String?) -> BrowserInfo? {
        guard let bundleID else { return nil }
        return all.first { $0.bundleID == bundleID }
    }

    /// Browsers whose app bundle is present on this Mac.
    static var installed: [BrowserInfo] {
        all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }
}
