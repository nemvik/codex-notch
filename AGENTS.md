# Codex Island

- Native macOS application: Swift Package Manager, SwiftUI/AppKit, SQLite from the OS. No runtime dependencies.
- Keep all desktop IPC state on DesktopFeed's serial queue, all UI state on MainActor.
- The notch is the primary indicator. Draw only a thin colored line within a verified drawable menu-bar band under the camera, confined to its exclusion column. Never add a persistent panel below the menu bar, side wings over icons, or hover-open behavior. Counts/details belong in a native popover opened explicitly. Use a native status item only when no safe notch band exists. Cover these geometry and state rules with tests.
- Codex data is read-only. Never add actions that answer approvals or start/interrupt work without a separately authorized feature.
- Desktop IPC is internal: gate stream versions, handle revision gaps by requesting a new snapshot, and show disconnection on incompatible data. Never substitute historic file activity for a live status.
- Discard conversation text and tool output. Diagnostics must print counts and connection status only.
- Keep tasks and subagents separate; exclude guardian review threads from the catalog.
- Run `swift test`, `./scripts/build.sh`, and the bounded `--diagnose` check when modifying the protocol adapter. Only run diagnostics against the user's Codex when authorized.
- Build output is generated in ignored `build/`; do not commit it or `.build/`.
