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
4. Add a regression test when changing status handling, IPC parsing, or presentation geometry. Keep Codex access read-only. The resting status rim must stay wholly within the safe drawable menu-bar band below the camera. Pointer approach may reveal a temporary 32-point tab below the bar; only a click expands the attached black surface into exact counts and chat details. Never add a persistent panel over application content or side wings over menu icons. Use a native menu-bar item and popover only when the notch interface is unavailable.
5. Run the relevant checks and describe the result in your pull request.

```bash
swift test
./scripts/build.sh
```

For adapter changes, also run the isolated integration check:

```bash
python3 scripts/test-adapter.py
```

For visual changes, use demo mode and inspect all three states: resting rim, temporary hover tab, and overview expanded by a click. Check approach delay, leaving and re-entering, dragging past the notch, menu tracking, click-away dismissal, Escape, Reduce Motion, and accessibility labels. Confirm that hover alone never shows the full overview. Also check the native fallback on a display without a notch or without a safe drawable band, including menu-bar auto-hide behavior.

Keep the menu-bar anchor panel confined to the camera column and the separate body panel below the bar throughout transitions. The pointer approach area must remain an observation region, not an invisible window that intercepts application controls. Include before/after screenshots or a short recording. Rendered previews and geometry tests do not establish that hover behavior works on hardware; describe what you actually observed.

Keep generated `.build/` and `build/` output out of commits. Do not include real user data in fixtures. In your PR, explain the problem, what changes, how you verified it, and any remaining limits. AI-assisted contributions are welcome when you understand and review the result and report verification accurately.

For substantial features or changes to the connection model, start with an issue so the design can be discussed before implementation. Contributions are provided under the repository's [MIT License](LICENSE).
