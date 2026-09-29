# Contributing to Codex Notch

Small fixes, clear bug reports, and testing on other Mac displays are welcome. This is a spare-time project; opening an issue does not guarantee a feature or a response date.

## Report a problem

Check existing issues, then use the [bug report form](https://github.com/nemvik/codex-notch/issues/new?template=bug_report.yml). Include the app revision or release, macOS and Codex versions, Mac model, and steps to reproduce. For visual problems, include display scaling, menu-bar auto-hide settings, connected displays, and a screenshot if possible. Crop or redact private chat titles and other personal information.

Do not upload your Codex database, session files, configuration, credentials, or conversation logs. If connection diagnostics help, the built executable supports `--diagnose`, which observes your real local Codex for ten seconds and prints status and counts only. Read the output before sharing it.

Report security concerns privately as described in [SECURITY.md](SECURITY.md).

## Make a change

1. Fork the repository and create a branch for one focused change.
2. Read `AGENTS.md` and the nearby implementation before editing.
3. Keep the app native: SwiftUI, AppKit, Swift Package Manager, and system SQLite. Explain why any additional dependency is needed.
4. Add a regression test when changing status handling, IPC parsing, or presentation geometry. Keep Codex access read-only. The status rim must remain wholly within the safe drawable menu-bar band below the camera; never add a persistent panel over application content. Counts and chat details belong in the native popover opened by an explicit click. Use a native menu-bar item only when the notch rim is unavailable.
5. Run the relevant checks and describe the result in your pull request.

```bash
swift test
./scripts/build.sh
```

For adapter changes, also run the isolated integration check:

```bash
python3 scripts/test-adapter.py
```

For visual changes, use demo mode and inspect the notch rim, clicking the notch, opening and dismissing the popover, menu actions, and accessibility labels. Also check the fallback on a display without a notch or without a safe drawable band, including menu-bar auto-hide behavior. Include before/after screenshots or a short recording and confirm that hovering does not open the overview. Do not claim hardware verification for a display you have not tested.

Keep generated `.build/` and `build/` output out of commits. Do not include real user data in fixtures. In your PR, explain the problem, what changes, how you verified it, and any remaining limits. AI-assisted contributions are welcome when you understand and review the result and report verification accurately.

For substantial features or changes to the connection model, start with an issue so the design can be discussed before implementation. Contributions are provided under the repository's [MIT License](LICENSE).
