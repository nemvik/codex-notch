# Security

Codex Notch is a local, read-only companion for the Codex desktop app. It observes an internal IPC interface and reads the chat catalog with SQLite in read-only mode. It does not answer approvals, run agents, transmit chat data to the internet, or write chat history.

The IPC stream may contain conversation text and tool output in transit. The application discards that content and retains only the metadata needed for its status display. Because the interface is internal, compatibility may change when Codex updates.

## Report a vulnerability

Email [codexnotch@nemvik.com](mailto:codexnotch@nemvik.com) with the subject **Codex Notch security report**. Please avoid a public issue for an unpatched vulnerability.

Include the affected release or commit, macOS and Codex versions, impact, and minimal reproduction steps. Use synthetic examples; do not send credentials, conversation contents, databases, or session files. Ask before sending a sensitive proof of concept.

This is a spare-time project without a guaranteed response window or a bug bounty. Security fixes target the current main branch and latest pre-release; older versions do not receive a separate maintenance commitment.

## Download integrity

Build from source if you want to inspect what runs locally. Pre-release binaries are signed ad-hoc and are not Developer ID signed or notarized. Obtain source and releases only from [nemvik/codex-notch](https://github.com/nemvik/codex-notch). The project is not an official Apple or OpenAI product.
