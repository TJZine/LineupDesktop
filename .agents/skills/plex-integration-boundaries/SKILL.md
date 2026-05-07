---
name: plex-integration-boundaries
description: Use when Lineup Desktop work changes Plex auth, discovery, selected server state, library data, stream resolution, subtitle policy, token handling, or playback URL setup.
---

# Plex Integration Boundaries

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/architecture/security-and-secret-flow.md`
4. `docs/architecture/import-ledger.md`
5. `docs/architecture/CURRENT_STATE.md`

Keep Plex transport and secret policy out of renderer code. Main and/or a
privileged helper own credentials, token-bearing operations, selected-server
persistence, URL setup, diagnostics redaction, and native playback handoff.

Renderer-facing contracts may contain renderer-safe media and capability state,
but must not include raw Plex tokens, tokenized URLs, auth headers, native
handles, raw Plex payloads where policy is still undecided, or transport retry
policy.

If Plex work also touches persisted selected-server state, renderer UI, or
Electron/native ownership, load `persistence-boundaries`,
`ui-composition-patterns`, or `architecture-boundaries`.

Copied or adapted upstream Lineup Plex code requires an import-ledger entry
before or with the import.
