# RD-23 Hardening PR 13 Review Notes

This PR was applied through the GitHub connector without local command execution. Treat this document as an explicit review checklist for Codex/local verification before the PR is marked ready.

## Intent

- Keep RD-23 focused on live channel setup and runtime persistence hardening.
- Remove reachable fake/draft channel setup actions from the renderer setup route.
- Prefer the product-neutral `data-channel-setup-status` binding over the previous fixture-named selector.
- Add focused tests for live setup library selection and stale Plex item/search-result protection.

## Careful-Review Targets

1. `src/renderer/settingsSetup.ts`
   - Confirm removing the legacy draft setup action IDs does not leave stale compile references in renderer tests or event handlers.
   - Confirm no reachable setup UI depends on the removed draft mutation paths.

2. `src/renderer/domBindings.ts`, `src/renderer/staticDom.ts`, and `src/renderer/channelSetup/dom.ts`
   - Confirm `channelSetupStatusElement` is the only product selector used for setup status rendering.
   - Confirm production code no longer queries or writes the old fixture-named setup status selector.
   - Confirm static DOM mounting still exposes the setup status element in the channel setup commit header.

3. `src/__tests__/renderer/channelSetupLiveSelection.test.ts`
   - Confirm the test fixture shapes still match the current `PlexRuntimeSnapshot` and renderer state contracts.
   - Confirm stale item/search protection assertions reflect the intended product behavior.
   - Confirm the live setup selection view model remains renderer-safe.

4. Existing renderer tests
   - Run typecheck and focused renderer tests locally. Any stale test helpers or old draft-action assertions should be updated to the live setup workflow, not papered over with compatibility fallbacks.

## Required Local Verification

```bash
npm run typecheck
npm run test:contracts -- --test-name-pattern "channel setup live selection|channel setup|workflow|route DOM|channel runtime|preload|contracts"
npm run verify:redaction
npm run verify:maintainability
npm run verify:docs
git diff --check
npm run verify
```

## Gate

Do not mark RD-23 complete from this PR alone. RD-23 still needs local verification, implementation review, sanitized Windows proof, and roadmap/current-state reconciliation before RD-24 starts.
