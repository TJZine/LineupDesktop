# Testing And Verification

## Commands

```sh
npm run typecheck
npm run test:contracts
npm run test:harness-docs
npm run verify:docs
npm run verify:redaction
npm run verify
```

## Current Scope

The repo currently verifies scaffold contracts and control-plane documents only.
Future Electron, renderer, native playback, persistence/secrets, and packaging
work must expand this guide before implementation begins.

## Redaction

Do not add fixtures, logs, docs, or tests containing raw Plex tokens, tokenized
URLs, raw auth headers, native media logs with secrets, or crash dumps with
secret-bearing state.
