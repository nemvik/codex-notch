# Codex Island

- Native macOS application: Swift Package Manager, SwiftUI/AppKit, SQLite from the OS. No runtime dependencies.
- Keep all desktop IPC state on DesktopFeed's serial queue, all UI state on MainActor.
- The notch is the primary indicator. At rest, draw only a thin colored line within a verified drawable menu-bar band under the camera, confined to its exclusion column. Pointer approach may reveal a temporary black tab attached below the notch after a short dwell; leaving retracts it. Only an explicit click expands the same black surface to show exact counts and chats. Never add a persistent panel below the bar or side wings over menu icons. Use a native status item and NSPopover only when no safe notch band exists.
- Keep the camera-column anchor and below-bar body in separate NSPanels so no menu-bar hit region extends beyond the camera exclusion, including during animation. The approach region (camera column plus 12 points below the bar) is observation-only, never an invisible event-intercepting window. Preserve the 180 ms reveal dwell and 350 ms leave grace unless a requested interaction change requires otherwise; test these transitions, drag suppression, explicit dismissal, and geometry. Rendered previews and unit tests do not replace observing hover behavior on hardware.
- Codex data is read-only. Never add actions that answer approvals or start/interrupt work without a separately authorized feature.
- Desktop IPC is internal: gate stream versions, handle revision gaps by requesting a new snapshot, and show disconnection on incompatible data. Never substitute historic file activity for a live status.
- Discard conversation text and tool output. Diagnostics must print counts and connection status only.
- Keep tasks and subagents separate; exclude guardian review threads from the catalog.
- Run `swift test`, `./scripts/build.sh`, and the bounded `--diagnose` check when modifying the protocol adapter. Only run diagnostics against the user's Codex when authorized.
- Build output is generated in ignored `build/`; do not commit it or `.build/`.
