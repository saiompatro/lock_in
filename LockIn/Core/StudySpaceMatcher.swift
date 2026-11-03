import Foundation

/// Pure matching logic: decides whether an activity snapshot is inside a study space.
/// Foundation only (also compiled into the test target).
enum StudySpaceMatcher {
    /// First enabled space that matches the snapshot, or nil if the user is outside all of them.
    static func match(_ snapshot: ActivitySnapshot, in spaces: [StudySpace]) -> StudySpace? {
        spaces.first { $0.isEnabled && matches(snapshot, space: $0) }
    }

    static func matches(_ snapshot: ActivitySnapshot, space: StudySpace) -> Bool {
        guard space.isEnabled else { return false }
        switch space.kind {
        case .app:
            guard sameBundle(snapshot, space) else { return false }
            return !snapshot.windowInfoAvailable || snapshot.hasVisibleWindow

        case .window:
            guard sameBundle(snapshot, space) else { return false }
            // Without Accessibility we cannot see titles: degrade to an app-level match.
            guard snapshot.windowInfoAvailable else { return true }
            guard snapshot.hasVisibleWindow else { return false }
            guard let needle = nonEmpty(space.titleContains) else { return true }
            return titleContains(snapshot.windowTitle, needle)

        case .website:
            guard snapshot.isBrowser else { return false }
            if let required = nonEmpty(space.bundleID), required != snapshot.bundleID { return false }
            if snapshot.windowInfoAvailable && !snapshot.hasVisibleWindow { return false }

            let pattern = nonEmpty(space.urlPattern)
            if let url = snapshot.browserURL, let pattern {
                return urlMatches(url, pattern: pattern)
            }
            // URL unknown (Firefox, permission denied, no URL pattern): fall back to the title keyword.
            guard let needle = nonEmpty(space.titleContains) else { return false }
            return titleContains(snapshot.windowTitle, needle)
        }
    }

    // MARK: URL patterns

    /// "https://www.Notion.so/My-Page?x=1#y" -> "notion.so/my-page". Used when the user types a pattern.
    static func normalizedPattern(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") {
            // Only treat it as a scheme if the prefix looks like one.
            let prefix = s[s.startIndex..<r.lowerBound]
            if !prefix.isEmpty, prefix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) {
                s = String(s[r.upperBound...])
            }
        }
        if let i = s.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            s = String(s[s.startIndex..<i])
        }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Domain (+ subdomains) match, plus optional path-prefix match when the pattern contains "/".
    static func urlMatches(_ url: URL, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        let scheme = url.scheme?.lowercased()

        // Local files: only when the pattern itself is a file pattern.
        if trimmed.hasPrefix("file:") {
            guard scheme == "file" else { return false }
            var rest = String(trimmed.dropFirst("file:".count))
            if rest.hasPrefix("//") { rest.removeFirst(2) }
            while rest.hasSuffix("/") { rest.removeLast() }
            let path = url.path(percentEncoded: false).lowercased()
            return rest.isEmpty ? true : path.hasPrefix(rest)
        }
        guard scheme == "http" || scheme == "https" else { return false }

        let normalized = normalizedPattern(trimmed)
        guard !normalized.isEmpty else { return false }

        let hostAndPort: Substring
        var patternPath = ""
        if let slash = normalized.firstIndex(of: "/") {
            hostAndPort = normalized[normalized.startIndex..<slash]
            patternPath = String(normalized[slash...])
        } else {
            hostAndPort = Substring(normalized)
        }

        var patternHost = String(hostAndPort)
        var patternPort: Int?
        if !patternHost.contains("]"), let colon = patternHost.lastIndex(of: ":"),
           let port = Int(patternHost[patternHost.index(after: colon)...]) {
            patternPort = port
            patternHost = String(patternHost[patternHost.startIndex..<colon])
        }
        if patternHost.hasPrefix("www.") { patternHost.removeFirst(4) }
        guard !patternHost.isEmpty else { return false }

        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return false }
        while host.hasSuffix(".") { host.removeLast() }
        if let patternPort, url.port != patternPort { return false }

        let hostOK: Bool
        if host == patternHost {
            hostOK = true
        } else if isIPAddressLike(host) || isIPAddressLike(patternHost) {
            hostOK = false
        } else {
            hostOK = host.hasSuffix("." + patternHost)
        }
        guard hostOK else { return false }

        guard !patternPath.isEmpty else { return true }
        let urlPath = url.path(percentEncoded: false).lowercased()
        return urlPath.hasPrefix(patternPath)
    }

    // MARK: Titles

    /// Case- and diacritic-insensitive substring test. An empty needle never matches.
    static func titleContains(_ title: String?, _ needle: String) -> Bool {
        guard let title, !title.isEmpty else { return false }
        let n = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        return title.range(of: n, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: Helpers

    private static func sameBundle(_ snapshot: ActivitySnapshot, _ space: StudySpace) -> Bool {
        guard let a = snapshot.bundleID, let b = space.bundleID, !b.isEmpty else { return false }
        return a == b
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func isIPAddressLike(_ host: String) -> Bool {
        host.contains(":") || (!host.isEmpty && host.allSatisfy { $0.isNumber || $0 == "." })
    }
}
