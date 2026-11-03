import Foundation
import Testing

struct NormalizedPatternTests {
    @Test(arguments: [
        ("https://www.Notion.so/My-Page?x=1#y", "notion.so/my-page"),
        ("  Notion.so  ", "notion.so"),
        ("http://notion.so/", "notion.so"),
        ("www.notion.so", "notion.so"),
        ("notion.so///", "notion.so"),
        ("docs.google.com/document/d/ABC/edit?usp=sharing", "docs.google.com/document/d/abc/edit"),
        ("notion.so#section", "notion.so"),
        ("HTTPS://WWW.EXAMPLE.COM/Path/", "example.com/path"),
        ("localhost:3000/app", "localhost:3000/app"),
        ("", ""),
        ("   ", ""),
    ])
    func normalizes(raw: String, expected: String) {
        #expect(StudySpaceMatcher.normalizedPattern(raw) == expected)
    }
}

struct URLMatchTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func exactHost() {
        #expect(StudySpaceMatcher.urlMatches(url("https://notion.so/page"), pattern: "notion.so"))
        #expect(StudySpaceMatcher.urlMatches(url("https://notion.so"), pattern: "notion.so"))
    }

    @Test func subdomains() {
        #expect(StudySpaceMatcher.urlMatches(url("https://www.notion.so/x"), pattern: "notion.so"))
        #expect(StudySpaceMatcher.urlMatches(url("https://team.app.notion.so/x"), pattern: "notion.so"))
        #expect(StudySpaceMatcher.urlMatches(url("https://docs.google.com/x"), pattern: "google.com"))
    }

    @Test func patternSubdomainDoesNotMatchParent() {
        #expect(!StudySpaceMatcher.urlMatches(url("https://google.com"), pattern: "docs.google.com"))
        #expect(!StudySpaceMatcher.urlMatches(url("https://mail.google.com"), pattern: "docs.google.com"))
    }

    @Test func lookalikeDomainsDoNotMatch() {
        #expect(!StudySpaceMatcher.urlMatches(url("https://notnotion.so"), pattern: "notion.so"))
        #expect(!StudySpaceMatcher.urlMatches(url("https://notion.so.evil.com"), pattern: "notion.so"))
        #expect(!StudySpaceMatcher.urlMatches(url("https://evil.com/notion.so"), pattern: "notion.so"))
        #expect(!StudySpaceMatcher.urlMatches(url("https://evil.com/?q=notion.so"), pattern: "notion.so"))
        #expect(!StudySpaceMatcher.urlMatches(url("https://notion.sox"), pattern: "notion.so"))
    }

    @Test func wwwAndSchemeInPatternAreIgnored() {
        #expect(StudySpaceMatcher.urlMatches(url("https://notion.so/a"), pattern: "www.notion.so"))
        #expect(StudySpaceMatcher.urlMatches(url("https://www.notion.so/a"), pattern: "https://www.notion.so"))
        #expect(StudySpaceMatcher.urlMatches(url("http://notion.so/a"), pattern: "https://notion.so/"))
    }

    @Test func caseInsensitive() {
        #expect(StudySpaceMatcher.urlMatches(url("https://NOTION.so/Page"), pattern: "Notion.SO"))
        #expect(StudySpaceMatcher.urlMatches(url("https://docs.google.com/Document/D/ABC"), pattern: "docs.google.com/document/d/abc"))
    }

    @Test func pathPrefix() {
        let p = "docs.google.com/document/d/abc"
        #expect(StudySpaceMatcher.urlMatches(url("https://docs.google.com/document/d/abc"), pattern: p))
        #expect(StudySpaceMatcher.urlMatches(url("https://docs.google.com/document/d/abc/edit"), pattern: p))
        #expect(StudySpaceMatcher.urlMatches(url("https://docs.google.com/document/d/abc/edit?usp=x#heading=h.1"), pattern: p))
        #expect(!StudySpaceMatcher.urlMatches(url("https://docs.google.com/document/d/xyz/edit"), pattern: p))
        #expect(!StudySpaceMatcher.urlMatches(url("https://docs.google.com/spreadsheets/d/abc"), pattern: p))
        #expect(!StudySpaceMatcher.urlMatches(url("https://docs.google.com/"), pattern: p))
    }

    @Test func pathPatternWithTrailingSlashAndQuery() {
        #expect(StudySpaceMatcher.urlMatches(url("https://github.com/org/repo/issues"), pattern: "github.com/org/repo/"))
        #expect(StudySpaceMatcher.urlMatches(url("https://github.com/org/repo"), pattern: "https://github.com/org/repo?tab=x"))
        #expect(!StudySpaceMatcher.urlMatches(url("https://github.com/other/repo"), pattern: "github.com/org/repo"))
    }

    @Test func pathPatternAppliesToSubdomains() {
        #expect(StudySpaceMatcher.urlMatches(url("https://www.reddit.com/r/swift/top"), pattern: "reddit.com/r/swift"))
        #expect(!StudySpaceMatcher.urlMatches(url("https://www.reddit.com/r/rust"), pattern: "reddit.com/r/swift"))
    }

    @Test func ports() {
        #expect(StudySpaceMatcher.urlMatches(url("http://localhost:3000/app"), pattern: "localhost"))
        #expect(StudySpaceMatcher.urlMatches(url("http://localhost:3000/app"), pattern: "localhost:3000"))
        #expect(StudySpaceMatcher.urlMatches(url("http://localhost:3000/app/x"), pattern: "localhost:3000/app"))
        #expect(!StudySpaceMatcher.urlMatches(url("http://localhost:4000/app"), pattern: "localhost:3000"))
        #expect(StudySpaceMatcher.urlMatches(url("https://notion.so:443/a"), pattern: "notion.so"))
    }

    @Test func ipAddresses() {
        #expect(StudySpaceMatcher.urlMatches(url("http://192.168.1.10:8080/x"), pattern: "192.168.1.10"))
        #expect(!StudySpaceMatcher.urlMatches(url("http://192.168.1.10/x"), pattern: "1.10"))
    }

    @Test func nonWebSchemesNeverMatch() {
        #expect(!StudySpaceMatcher.urlMatches(url("about:blank"), pattern: "blank"))
        #expect(!StudySpaceMatcher.urlMatches(url("about:blank"), pattern: "about:blank"))
        #expect(!StudySpaceMatcher.urlMatches(url("chrome://newtab"), pattern: "newtab"))
        #expect(!StudySpaceMatcher.urlMatches(url("chrome://settings"), pattern: "settings"))
        #expect(!StudySpaceMatcher.urlMatches(url("favorites://"), pattern: "favorites"))
        #expect(!StudySpaceMatcher.urlMatches(url("safari-resource:/ErrorPage.html"), pattern: "errorpage.html"))
        #expect(!StudySpaceMatcher.urlMatches(url("ftp://notion.so/file"), pattern: "notion.so"))
        #expect(!StudySpaceMatcher.urlMatches(url("file:///Users/me/notion.so"), pattern: "notion.so"))
    }

    @Test func fileURLsOnlyMatchFilePatterns() {
        #expect(StudySpaceMatcher.urlMatches(url("file:///Users/me/Notes/lecture.pdf"), pattern: "file:///users/me/notes"))
        #expect(!StudySpaceMatcher.urlMatches(url("file:///Users/me/Other/lecture.pdf"), pattern: "file:///users/me/notes"))
        #expect(!StudySpaceMatcher.urlMatches(url("https://example.com/users/me/notes"), pattern: "file:///users/me/notes"))
    }

    @Test func emptyPatternNeverMatches() {
        #expect(!StudySpaceMatcher.urlMatches(url("https://notion.so"), pattern: ""))
        #expect(!StudySpaceMatcher.urlMatches(url("https://notion.so"), pattern: "   "))
        #expect(!StudySpaceMatcher.urlMatches(url("https://notion.so"), pattern: "/"))
    }
}

struct MatchesTests {
    // MARK: Fixtures

    private func snapshot(
        bundleID: String? = "com.apple.dt.Xcode",
        title: String? = nil,
        ax: Bool = true,
        visible: Bool = true,
        browser: Bool = false,
        url: String? = nil,
        own: Bool = false
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            bundleID: bundleID,
            appName: "App",
            windowTitle: title,
            windowInfoAvailable: ax,
            hasVisibleWindow: visible,
            isBrowser: browser,
            browserURL: url.flatMap(URL.init(string:)),
            isOwnApp: own
        )
    }

    private func appSpace(_ id: String = "com.apple.dt.Xcode") -> StudySpace {
        StudySpace(kind: .app, name: "Xcode", bundleID: id)
    }

    private func windowSpace(_ id: String = "com.apple.Preview", title: String = "Lecture") -> StudySpace {
        StudySpace(kind: .window, name: title, bundleID: id, titleContains: title)
    }

    private func site(_ pattern: String?, browser: String? = nil, title: String? = nil) -> StudySpace {
        StudySpace(kind: .website, name: pattern ?? "site", bundleID: browser, titleContains: title, urlPattern: pattern)
    }

    private func safariSnap(url: String?, title: String? = nil, ax: Bool = true, visible: Bool = true) -> ActivitySnapshot {
        snapshot(bundleID: "com.apple.Safari", title: title, ax: ax, visible: visible, browser: true, url: url)
    }

    // MARK: App spaces

    @Test func appMatchesSameBundle() {
        #expect(StudySpaceMatcher.matches(snapshot(), space: appSpace()))
    }

    @Test func appDoesNotMatchOtherBundle() {
        #expect(!StudySpaceMatcher.matches(snapshot(bundleID: "com.apple.Safari"), space: appSpace()))
        #expect(!StudySpaceMatcher.matches(snapshot(bundleID: nil), space: appSpace()))
    }

    @Test func appWithMinimizedOrNoWindowDoesNotMatch() {
        #expect(!StudySpaceMatcher.matches(snapshot(visible: false), space: appSpace()))
    }

    @Test func appWithoutAccessibilityDegradesToBundleMatch() {
        // hasVisibleWindow is meaningless without AX.
        #expect(StudySpaceMatcher.matches(snapshot(ax: false, visible: false), space: appSpace()))
    }

    @Test func appSpaceWithoutBundleNeverMatches() {
        var s = appSpace()
        s.bundleID = nil
        #expect(!StudySpaceMatcher.matches(snapshot(), space: s))
    }

    // MARK: Window spaces

    @Test func windowMatchesTitleSubstring() {
        let snap = snapshot(bundleID: "com.apple.Preview", title: "Algorithms Lecture 4.pdf — Page 2")
        #expect(StudySpaceMatcher.matches(snap, space: windowSpace()))
    }

    @Test func windowTitleIsCaseAndDiacriticInsensitive() {
        let snap = snapshot(bundleID: "com.apple.Preview", title: "LECTURE notes")
        #expect(StudySpaceMatcher.matches(snap, space: windowSpace(title: "lecture")))
        let accented = snapshot(bundleID: "com.apple.Preview", title: "Résumé draft")
        #expect(StudySpaceMatcher.matches(accented, space: windowSpace(title: "resume")))
        let plain = snapshot(bundleID: "com.apple.Preview", title: "Resume draft")
        #expect(StudySpaceMatcher.matches(plain, space: windowSpace(title: "RÉSUMÉ")))
    }

    @Test func windowWithDifferentTitleOrAppDoesNotMatch() {
        #expect(!StudySpaceMatcher.matches(snapshot(bundleID: "com.apple.Preview", title: "Invoice.pdf"), space: windowSpace()))
        #expect(!StudySpaceMatcher.matches(snapshot(bundleID: "com.apple.Preview", title: nil), space: windowSpace()))
        #expect(!StudySpaceMatcher.matches(snapshot(bundleID: "com.apple.TextEdit", title: "Lecture"), space: windowSpace()))
    }

    @Test func minimizedWindowDoesNotMatch() {
        let snap = snapshot(bundleID: "com.apple.Preview", title: "Lecture", visible: false)
        #expect(!StudySpaceMatcher.matches(snap, space: windowSpace()))
    }

    @Test func windowDegradesToAppMatchWithoutAccessibility() {
        let snap = snapshot(bundleID: "com.apple.Preview", title: nil, ax: false)
        #expect(StudySpaceMatcher.matches(snap, space: windowSpace()))
        let other = snapshot(bundleID: "com.apple.TextEdit", title: nil, ax: false)
        #expect(!StudySpaceMatcher.matches(other, space: windowSpace()))
    }

    // MARK: Website spaces

    @Test func websiteMatchesByURL() {
        let snap = safariSnap(url: "https://www.notion.so/My-Notes")
        #expect(StudySpaceMatcher.matches(snap, space: site("notion.so")))
        #expect(!StudySpaceMatcher.matches(snap, space: site("docs.google.com")))
    }

    @Test func websiteNeedsABrowser() {
        let snap = snapshot(bundleID: "com.example.NotABrowser", browser: false, url: "https://notion.so")
        #expect(!StudySpaceMatcher.matches(snap, space: site("notion.so")))
    }

    @Test func websiteRestrictedToOneBrowser() {
        let safari = safariSnap(url: "https://notion.so/a")
        let chrome = snapshot(bundleID: "com.google.Chrome", browser: true, url: "https://notion.so/a")
        let space = site("notion.so", browser: "com.google.Chrome")
        #expect(!StudySpaceMatcher.matches(safari, space: space))
        #expect(StudySpaceMatcher.matches(chrome, space: space))
        // nil bundle = any browser
        #expect(StudySpaceMatcher.matches(safari, space: site("notion.so")))
        #expect(StudySpaceMatcher.matches(chrome, space: site("notion.so")))
    }

    @Test func websiteMinimizedBrowserDoesNotMatch() {
        let snap = safariSnap(url: "https://notion.so/a", visible: false)
        #expect(!StudySpaceMatcher.matches(snap, space: site("notion.so")))
    }

    @Test func websiteWithoutAccessibilityStillMatchesByURL() {
        let snap = safariSnap(url: "https://notion.so/a", ax: false, visible: false)
        #expect(StudySpaceMatcher.matches(snap, space: site("notion.so")))
    }

    @Test func websiteLookalikeAndNewTabDoNotMatch() {
        #expect(!StudySpaceMatcher.matches(safariSnap(url: "https://notnotion.so"), space: site("notion.so")))
        #expect(!StudySpaceMatcher.matches(safariSnap(url: "about:blank"), space: site("blank")))
        #expect(!StudySpaceMatcher.matches(safariSnap(url: "favorites://"), space: site("favorites")))
        #expect(!StudySpaceMatcher.matches(safariSnap(url: "chrome://newtab"), space: site("newtab")))
    }

    @Test func websitePathPattern() {
        let space = site("docs.google.com/document/d/abc")
        #expect(StudySpaceMatcher.matches(safariSnap(url: "https://docs.google.com/document/d/abc/edit"), space: space))
        #expect(!StudySpaceMatcher.matches(safariSnap(url: "https://docs.google.com/document/d/zzz/edit"), space: space))
    }

    @Test func websiteKnownURLIgnoresTitleFallback() {
        // The URL is authoritative: a matching title on the wrong site must not match.
        let snap = safariSnap(url: "https://youtube.com/watch", title: "Notion tutorial")
        #expect(!StudySpaceMatcher.matches(snap, space: site("notion.so", title: "notion")))
    }

    @Test func websiteTitleFallbackWhenURLUnknown() {
        let space = site("notion.so", title: "Notion")
        #expect(StudySpaceMatcher.matches(safariSnap(url: nil, title: "My Notes – NOTION"), space: space))
        #expect(!StudySpaceMatcher.matches(safariSnap(url: nil, title: "YouTube"), space: space))
        #expect(!StudySpaceMatcher.matches(safariSnap(url: nil, title: nil), space: space))
    }

    @Test func websiteWithoutURLAndWithoutTitleKeywordNeverMatches() {
        #expect(!StudySpaceMatcher.matches(safariSnap(url: nil, title: "Notion"), space: site("notion.so")))
        #expect(!StudySpaceMatcher.matches(safariSnap(url: nil, title: "Notion"), space: site("notion.so", title: "  ")))
    }

    @Test func firefoxFallsBackToTitle() {
        let snap = snapshot(bundleID: "org.mozilla.firefox", title: "Lecture 4 - Notion", browser: true, url: nil)
        #expect(StudySpaceMatcher.matches(snap, space: site("notion.so", title: "notion")))
        #expect(!StudySpaceMatcher.matches(snap, space: site("notion.so")))
    }

    @Test func titleOnlyWebsiteSpace() {
        let snap = snapshot(bundleID: "org.mozilla.firefox", title: "Canvas – Dashboard", browser: true, url: "https://canvas.school.edu")
        // No URL pattern: the title keyword decides, even when the URL is known.
        #expect(StudySpaceMatcher.matches(snap, space: site(nil, title: "canvas")))
        #expect(!StudySpaceMatcher.matches(snap, space: site(nil, title: "gradescope")))
    }

    @Test func websiteTitleFallbackRespectsMinimized() {
        let snap = safariSnap(url: nil, title: "Notion", visible: false)
        #expect(!StudySpaceMatcher.matches(snap, space: site("notion.so", title: "notion")))
    }

    // MARK: match(in:)

    @Test func matchReturnsFirstEnabledMatch() {
        var first = appSpace()
        first.name = "first"
        var second = appSpace()
        second.name = "second"
        #expect(StudySpaceMatcher.match(snapshot(), in: [first, second])?.name == "first")
    }

    @Test func disabledSpacesAreSkipped() {
        var disabled = appSpace()
        disabled.isEnabled = false
        disabled.name = "disabled"
        var enabled = appSpace()
        enabled.name = "enabled"
        #expect(StudySpaceMatcher.match(snapshot(), in: [disabled]) == nil)
        #expect(StudySpaceMatcher.match(snapshot(), in: [disabled, enabled])?.name == "enabled")
        #expect(!StudySpaceMatcher.matches(snapshot(), space: disabled))
    }

    @Test func noSpacesNoMatch() {
        #expect(StudySpaceMatcher.match(snapshot(), in: []) == nil)
    }

    @Test func matchAcrossKinds() {
        let spaces = [appSpace("com.apple.dt.Xcode"), windowSpace(), site("notion.so")]
        #expect(StudySpaceMatcher.match(snapshot(), in: spaces)?.kind == .app)
        #expect(StudySpaceMatcher.match(snapshot(bundleID: "com.apple.Preview", title: "Lecture 1"), in: spaces)?.kind == .window)
        #expect(StudySpaceMatcher.match(safariSnap(url: "https://notion.so/x"), in: spaces)?.kind == .website)
        #expect(StudySpaceMatcher.match(safariSnap(url: "https://youtube.com"), in: spaces) == nil)
    }

    @Test func ownAppMatchesNothingUnlessConfigured() {
        let own = snapshot(bundleID: "com.lockin.LockIn", own: true)
        #expect(StudySpaceMatcher.match(own, in: [appSpace(), windowSpace(), site("notion.so")]) == nil)
    }
}
