import AppKit
import SwiftUI

/// Cached application icons, looked up by bundle identifier.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }

    static func icon(for candidate: AppCandidate) -> NSImage? {
        if let hit = cache[candidate.bundleID] { return hit }
        guard let url = candidate.url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[candidate.bundleID] = image
        return image
    }
}

/// App icon by bundle ID, with a symbol fallback.
struct AppIconView: View {
    var bundleID: String?
    var size: CGFloat = 32
    var fallbackSymbol = "app.dashed"

    var body: some View {
        if let image = AppIcons.icon(bundleID: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        Image(systemName: fallbackSymbol)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

/// Icon for a candidate app row.
struct CandidateIconView: View {
    let candidate: AppCandidate
    var size: CGFloat = 28

    var body: some View {
        if let image = AppIcons.icon(for: candidate) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            AppIconView(bundleID: nil, size: size)
        }
    }
}

/// Globe-style tile used for websites.
struct GlobeTile: View {
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: "globe")
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.studying, Color(red: 0.12, green: 0.62, blue: 0.62)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
    }
}

/// Icon for any study space: the real app icon for apps/windows, a globe tile for websites.
struct SpaceIconView: View {
    let space: StudySpace
    var size: CGFloat = 32

    var body: some View {
        switch space.kind {
        case .app:
            AppIconView(bundleID: space.bundleID, size: size, fallbackSymbol: "app.dashed")
        case .window:
            AppIconView(bundleID: space.bundleID, size: size, fallbackSymbol: "macwindow")
        case .website:
            GlobeTile(size: size)
        }
    }
}

// MARK: - Space descriptions

extension StudySpace {
    /// Friendly one-line explanation of what this space matches.
    var detailText: String {
        switch kind {
        case .app:
            return "Any window of \(appName ?? name)"
        case .window:
            let title = (titleContains ?? "").trimmingCharacters(in: .whitespaces)
            let app = appName ?? "app"
            return title.isEmpty ? "Any window in \(app)" : "\(app) · window title contains “\(title)”"
        case .website:
            let pattern = urlPattern ?? name
            let browser = SupportedBrowsers.info(for: bundleID)?.name ?? appName ?? "any browser"
            var text = "\(pattern) · \(bundleID == nil ? "any browser" : browser)"
            if let keyword = titleContains?.trimmingCharacters(in: .whitespaces), !keyword.isEmpty {
                text += " · title “\(keyword)”"
            }
            return text
        }
    }
}

/// Browsers that are actually installed on this Mac.
@MainActor
enum InstalledBrowsers {
    static var all: [BrowserInfo] {
        SupportedBrowsers.all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }
}
