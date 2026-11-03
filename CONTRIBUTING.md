# Contributing to Lock In

Bug reports, small fixes, accessibility improvements, and Windows testing are welcome.
For larger changes, open an issue first so we can agree on scope.

1. Fork the repository and create a branch from `main`.
2. Follow the build instructions in [README.md](README.md).
3. Keep monitoring code separate from matching and timing logic. Add regression coverage for changes to those rules.
4. Run the checks for the platform you changed:
   - macOS: `make test` and `make build`.
   - Windows core: `dotnet run --project Windows/LockIn.Core.Tests -c Release` (works on macOS/Linux too).
   - Windows UI: `dotnet build Windows/LockIn.Windows -c Release`, then run the app on Windows.
5. Open a pull request describing the problem, resulting behavior, and how you verified it. Include screenshots for UI changes and disclose anything you could not test.

Use synthetic study spaces in screenshots and logs. Never include personal URLs, window titles, session history, signing certificates, or tokens.

The macOS Xcode project is generated from `project.yml`. Run `make project` after changing its sources or configuration, and include the generated project changes.

By contributing, you agree that your contributions are licensed under the repository's MIT license.
