# Testing And Verification

## Commands

```sh
npm run typecheck
npm run lint
npm run build:electron
npm run smoke:electron
npm run verify:architecture
npm run test:contracts
npm run test:harness-docs
npm run verify:docs
npm run verify:redaction
npm run verify
```

## Current Scope

The repo currently verifies scaffold contracts, control-plane documents,
redaction rules, first-pass Electron boundary linting, and the minimal secure
Electron shell frame. Future Plex, native playback, persistence/secrets, and
packaging work must expand this guide before implementation begins.

`npm run build:electron` emits the Electron main, preload, renderer, and shared
contract JavaScript into `dist/` and copies the renderer HTML/CSS assets.

`npm run smoke:electron` builds the shell, launches Electron in smoke mode, and
expects the app to exit after proving local protocol boot, approved preload API
calls, fullscreen intents, renderer privilege denial, CSP, and containment for
new windows and permissions.

## Lint And Architecture

`npm run verify:architecture` runs ESLint plus the Desktop boundary rules in
`tools/architecture-rules/`.

The initial boundary rules are intentionally narrow:

- renderer code must not import Electron, Node, main, preload, or native-helper
  implementation
- preload must not import renderer or native-helper implementation
- main and native-helper code must not import renderer implementation

Expand these rules only when a repeated mistake or approved plan shows the
extra guardrail is worth the maintenance cost.

## Redaction

Do not add fixtures, logs, docs, or tests containing raw Plex tokens, tokenized
URLs, raw auth headers, native media logs with secrets, or crash dumps with
secret-bearing state.
