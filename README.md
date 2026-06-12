# Lineup Desktop

A Windows-first Electron desktop client for [Plex](https://www.plex.tv/) that
turns your media libraries into virtual TV channels with deterministic
scheduling, an EPG guide, and native video playback — all running locally with
no cloud backend.

> **Status:** Pre-release (`0.0.0`) · Private · Apache-2.0

---

## What Is Lineup?

Lineup lets you build custom channels from your Plex media library. Each channel
gets its own schedule, and the app presents a familiar TV-like experience:
flip through channels, check the guide, and watch content play continuously
— just like live television, powered entirely by your own Plex server.

**Lineup Desktop** is the native Windows port of that concept, built on Electron
with a C#/.NET native helper for video playback via
[libmpv](https://mpv.io/).

### Key Features

- 🔒 **Secure Plex auth** — encrypted credential storage via Electron
  `safeStorage`; renderer never touches tokens
- 📺 **Virtual channels** — deterministic scheduling with shuffle, block, and
  loop strategies
- 📖 **EPG guide** — full electronic program guide with current/next info,
  mini-guide overlay, and channel badges
- 🎬 **Native playback** — C# helper process with libmpv for direct play,
  direct stream, and transcode decisions
- 🎛️ **Media options** — subtitle, audio track, HDR/Dolby Vision, and quality
  controls
- 🖥️ **Desktop UX** — fullscreen, multi-monitor, keyboard/gamepad input, cursor
  auto-hide, and app-command support
- 🩺 **Diagnostics** — crash recovery, support-bundle export, and redacted
  logging

---

## Prerequisites

| Requirement | Version |
| --- | --- |
| **Node.js** | `22.19.0` (see [`.nvmrc`](./.nvmrc)) |
| **npm** | Bundled with Node |
| **Git** | Any recent version |
| **Windows** | 10+ (primary target for native playback proof) |
| **macOS** | Supported for development and automated tests |

> [!TIP]
> Use [nvm](https://github.com/nvm-sh/nvm) (macOS/Linux) or
> [nvm-windows](https://github.com/coreybutler/nvm-windows) to manage Node
> versions. Run `nvm use` in the repo root to switch automatically.

---

## Getting Started

```sh
# Clone the repository
git clone https://github.com/TJZine/LineupDesktop.git
cd LineupDesktop

# Install the correct Node version
nvm use

# Install dependencies
npm ci

# Run the full verification suite
npm run verify
```

### Launch the Electron App (Development)

```sh
# Build the Electron shell (main + preload + renderer)
npm run build:electron

# Run the Electron smoke test
npm run smoke:electron
```

> [!NOTE]
> There is no `npm run dev` hot-reload server yet. The current development
> workflow is build → smoke → iterate.

---

## Available Scripts

| Script | Description |
| --- | --- |
| `npm run build:electron` | Compile TypeScript, bundle preload, and copy renderer assets |
| `npm run smoke:electron` | Build + launch the Electron smoke test |
| `npm run typecheck` | Run the TypeScript compiler in check-only mode |
| `npm run lint` | Run ESLint across the project |
| `npm run test` | Run contract tests and harness-doc tests |
| `npm run test:contracts` | Run only the contract/unit test suite |
| `npm run test:harness-docs` | Run only the harness-doc verification tests |
| `npm run verify` | **Full verification** — typecheck, lint, architecture, tests, docs, and redaction |
| `npm run verify:architecture` | Lint + maintainability checks |
| `npm run verify:docs` | Verify doc structure and cross-references |
| `npm run verify:redaction` | Scan for leaked secrets, tokens, or private data |

> [!IMPORTANT]
> Always run `npm run verify` before committing. CI runs the same suite on
> Linux and Windows.

---

## Project Structure

```
LineupDesktop/
├── src/
│   ├── contracts/       # Renderer-safe type contracts (player, Plex, IPC, persistence, diagnostics)
│   ├── domain/          # Pure domain logic (scheduler, channel/content) — no Electron/Node deps
│   ├── main/            # Electron main process (shell, Plex runtime, player, persistence, window)
│   ├── preload/         # Narrow context bridge — single lineupDesktop exposure
│   ├── renderer/        # Unprivileged renderer (UI, routes, overlays, focus, input)
│   ├── native-helper/   # C#/.NET native player host (libmpv, NDJSON protocol)
│   └── __tests__/       # Contract, domain, main, preload, renderer, and integration tests
├── tools/               # Build scripts, verifiers, dev-only spike harnesses
├── docs/
│   ├── architecture/    # ADRs, current state, import ledger, guardrails
│   ├── roadmap/         # Ordered port roadmap and MVP sequence
│   ├── product/         # Product parity matrix
│   ├── development/     # Internal validation, Windows proof plans
│   ├── plans/           # Active and archived implementation plans
│   ├── runs/            # Platform proof evidence (gitignored contents)
│   └── agentic/         # Agentic workflow docs and session prompts
├── .github/             # CI workflows, issue/PR templates, CODEOWNERS
├── dist/                # Build output (gitignored)
└── out/                 # Package output (gitignored)
```

---

## Architecture Overview

Lineup Desktop follows a strict **privilege separation** model:

```
┌─────────────────────────────────────────────────────────┐
│                    Renderer (unprivileged)               │
│  Routes · Overlays · EPG · Settings · Focus · Input     │
│  No tokens, no credentials, no raw URLs, no Node APIs   │
└────────────────────────┬────────────────────────────────┘
                         │ window.lineupDesktop (preload bridge)
┌────────────────────────┴────────────────────────────────┐
│                    Preload (narrow bridge)               │
│  Single contextBridge exposure · payload guards          │
│  Validated IPC channels only                             │
└────────────────────────┬────────────────────────────────┘
                         │ Electron IPC
┌────────────────────────┴────────────────────────────────┐
│                    Main (privileged)                     │
│  Plex auth/discovery/library · Stream policy            │
│  Persistence (safeStorage) · Player adapter · Window    │
│  Diagnostics · Playback runtime/composition             │
└────────────────────────┬────────────────────────────────┘
                         │ NDJSON over stdin/stdout
┌────────────────────────┴────────────────────────────────┐
│              Native Helper (C#/.NET process)             │
│  libmpv playback · Track control · Video parameters     │
└─────────────────────────────────────────────────────────┘
```

**Key invariants:**

- The renderer never accesses Plex tokens, auth headers, raw media URLs, native
  handles, or filesystem paths.
- Plex credentials are encrypted at rest via Electron `safeStorage` with no
  plaintext fallback.
- The domain layer (`src/domain/`) is pure — no Electron, Node, or browser
  globals.
- Playback decisions are capability-driven, not hardcoded to any platform's
  codec assumptions.

For full details, see
[`docs/architecture/CURRENT_STATE.md`](./docs/architecture/CURRENT_STATE.md).

---

## Technology Stack

| Layer | Technology |
| --- | --- |
| **Runtime** | [Electron](https://www.electronjs.org/) 42 |
| **Language** | [TypeScript](https://www.typescriptlang.org/) 5.3 |
| **Bundler** | [esbuild](https://esbuild.github.io/) (preload bundling) |
| **Linter** | [ESLint](https://eslint.org/) 10 with architecture boundary rules |
| **Native playback** | C#/.NET helper with [libmpv](https://mpv.io/) |
| **Test runner** | Node.js built-in `--test` runner |
| **CI** | GitHub Actions (Linux + Windows) |

---

## Roadmap

The desktop port follows an ordered, incremental roadmap. Each slice has
explicit dependencies, exit gates, and platform proof requirements.

See [`docs/roadmap/desktop-port-roadmap.md`](./docs/roadmap/desktop-port-roadmap.md)
for the full checklist.

**Completed milestones** include: secure Electron shell, player contracts,
stream policy, persistence, Plex auth/discovery/library import, scheduler and
channel domains, Plex-to-player integration, renderer UI and navigation,
desktop input/fullscreen UX, UI-over-native-video composition, subtitle/audio/HDR
hardening, diagnostics and crash recovery, internal Windows packaging, internal
validation, upstream compatibility audit, product parity analysis, upstream UI
body parity, live Plex onboarding/library wiring, channel setup, guide runtime,
and production native playback code.

**Next up:** RD-27 — full Windows product proof for production native playback
and MVP visual/input/overlay behavior.

---

## Contributing

1. Read [`AGENTS.md`](./AGENTS.md) and
   [`docs/AGENTIC_DEV_WORKFLOW.md`](./docs/AGENTIC_DEV_WORKFLOW.md) before
   making changes.
2. Use the Node version from [`.nvmrc`](./.nvmrc).
3. Run `npm run verify` before pushing — it's the same gate CI enforces.
4. Record any copied or adapted upstream Lineup source in the
   [import ledger](./docs/architecture/import-ledger.md) before or with
   the import.
5. Never commit Plex tokens, auth headers, tokenized URLs, raw logs, or
   unredacted crash dumps.

See the [PR template](./.github/PULL_REQUEST_TEMPLATE.md) and
[issue templates](./.github/ISSUE_TEMPLATE/) for contribution guidelines.

---

## Security

This app handles Plex credentials, local storage, media playback, and
diagnostics. Security reports are welcome even in pre-release.

See [`SECURITY.md`](./SECURITY.md) for the full security policy, reporting
instructions, and scope.

---

## License

[Apache License 2.0](./LICENSE) — Copyright 2026 TJZine.
