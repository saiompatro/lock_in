# Making a release

The `Release` workflow builds and tests both platforms before publishing assets. It requires GitHub Actions to be enabled and the repository to allow the workflow's `contents: write` permission.

1. Ensure CI passes and perform the manual checks below.
2. Tag the commit, e.g. `git tag v1.0.0-beta.2 && git push origin v1.0.0-beta.2`.
3. Watch **Actions → Release**. A tag containing `-` is published as a prerelease. To retry a tag, use **Run workflow** and supply the existing tag; assets are replaced on retry.
4. Check all three ZIPs and `SHA256SUMS.txt` on the release page before promoting it.
5. Update README download URLs when moving from beta to a stable release. For stable releases, `/releases/latest/download/<asset>` can replace the version-specific links.

The app's internal version is set in `project.yml` and `Windows/LockIn.Windows/LockIn.Windows.csproj`; update these before tagging a new app version. Regenerate the Xcode project with `make project`.

## Manual release checks

- macOS: test installing from the ZIP on Apple Silicon and Intel; grant Accessibility/Automation/Notifications; test an app, a window, a browser URL, an alert, break, lock/unlock, sleep/wake, restart recovery, and history deletion.
- Windows x64 and ARM64: extract on a clean device without .NET; start the app, add Notepad and a browser title keyword, test reminders/repeats, neutral own windows, break/resume, tray close/reopen/quit, lock/unlock, sleep/wake, interrupted-session recovery, and history deletion. ARM64 is cross-compiled in CI and needs a real-device check.

## Signing

Current builds have no paid signing credentials. macOS is ad-hoc signed, Windows is unsigned. Do not describe them as notarized or publisher-verified.

For broad consumer distribution, sign macOS with a Developer ID Application identity and notarize with `xcrun notarytool`, then staple the app before making the final ZIP. Windows can be Authenticode-signed with a trusted signing service/certificate before compression. Keep identities, passwords, and certificates in GitHub Actions secrets and never commit them. Signing must happen before the workflow computes checksums.
