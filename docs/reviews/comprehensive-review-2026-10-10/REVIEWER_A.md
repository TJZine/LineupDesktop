Unit A review completed read-only at `4fb7758034f4f47290fae13a4ea8275860ba1284` on `codex/desktop-ui-second-pass`. One bounded recovery defect is supported by a complete source trace. No new credential leak, persistence data-loss defect, or material architecture defect was established in the inspected paths.

**A01 — Accepted protected-profile selection can leave server failure recovery on the PIN screen**

- **Type/status:** confirmed defect / CONFIRMED by static trace.
- **Severity:** S2 Medium.
- **Confidence:** High for the retained wrong screen; animation and focus variants remain unexecuted.
- **Journeys/classes:** J01, J04; C01, C08.
- **Trigger:** Select a protected Home profile that has a saved server. Plex accepts its PIN and profile persistence succeeds, but the subsequent saved-server connection fails before server publication.

The profile is durably committed at [lineup_controller.dart:715](/Users/tristan/Software/LineupDesktop/lib/app/lineup_controller.dart:715), then `selectProfile` awaits discovery at [lineup_controller.dart:744](/Users/tristan/Software/LineupDesktop/lib/app/lineup_controller.dart:744). Discovery calls `selectServer` for the saved server at [lineup_controller.dart:776](/Users/tristan/Software/LineupDesktop/lib/app/lineup_controller.dart:776). That call increments the request epoch at [lineup_controller.dart:798](/Users/tristan/Software/LineupDesktop/lib/app/lineup_controller.dart:798). Consequently, the outer profile operation returns false through `_run`’s currentness result at [lineup_controller.dart:2798](/Users/tristan/Software/LineupDesktop/lib/app/lineup_controller.dart:2798).

The view clears its local PIN selection only through the accepted submit callback at [onboarding_view.dart:1544](/Users/tristan/Software/LineupDesktop/lib/app/onboarding_view.dart:1544). A false result leaves `_pinUser` set. `_screen` gives this local value precedence over the controller’s Servers stage at [onboarding_view.dart:279](/Users/tristan/Software/LineupDesktop/lib/app/onboarding_view.dart:279). The resulting screen continues asking for a PIN instead of exposing server selection, discovery retry, and sign-out recovery.

A slower connection adds another manifestation: the stage-keyed `AnimatedSwitcher` can create a fresh PIN step while the original submission is pending. The original callback then exits when unmounted at [onboarding_view.dart:1543](/Users/tristan/Software/LineupDesktop/lib/app/onboarding_view.dart:1543). The replacement step has fresh local pending/error state. This follows Flutter’s documented [key replacement](https://api.flutter.dev/flutter/widgets/Widget/key.html), [AnimatedSwitcher child identity](https://api.flutter.dev/flutter/widgets/AnimatedSwitcher-class.html), and [mounted lifetime](https://api.flutter.dev/flutter/widgets/State/mounted.html) contracts; I also inspected the pinned Flutter implementation.

**Consequence:** Users can re-enter a valid PIN to retry the wrong dependency, or see an idle PIN screen hiding the server failure. Back/Escape can clear the local PIN screen, limiting severity. Persisted profile/server data remains intact.

**Counterpoints checked:** Ordinary wrong-PIN retry is intentional. Successful downstream restoration eventually replaces onboarding. Neither mitigates the saved-server connection-failure path, which remains on Servers while local PIN state survives.

**Correction direction:** Separate accepted profile authentication/commit from downstream discovery/restoration completion. Retire PIN presentation when profile selection commits, while preserving wrong-PIN retry, failed-save retention, and account-picker origins. Keep server failures at their owning recovery surface.

**Minimal controller-owned probe recipe**

Use the real `LineupController` and `UpstreamOnboardingView`, synthetic credentials, `FixtureStore`, and a synthetic Plex boundary. Do not override `selectProfile`.

1. Initialize with multiple profiles and a protected child whose persisted scope names a saved server.
2. Submit four digits through actual keypad/key events.
3. Accept `switchHomeUser`; gate `selectConnection` after discovery.
4. Assert the profile is committed and controller stage is Servers. Pump beyond the 180 ms switch transition.
5. Release the connection with a safe synthetic failure.
6. Observe whether `profile-pin-sheet` remains and server recovery controls are hidden.
7. Tap Back/Escape and establish that server recovery becomes visible.

Controls: no saved server; incorrect PIN; failed profile-state save; successful saved-server connection. Record profile commit, network call counts, visible screen, error semantics, focus, and retained durable scope. This reviewer ran no probe.

**Actual coverage**

Wide searches covered request epochs/currentness, cancellation, authorization recovery, content generations, save queues, credential operations, selection APIs, and cancellation eligibility across `lib/` and `test/`. Direct inventory identified sibling consumers in Setup, shell navigation, Guide, Studio, playback, Plex transport, and corresponding suites.

Deep inspection included:

- `LineupController`: initialization/linking, profile/server discovery and selection, staged scans and commits, restoration/migration, account-picker origins, channel mutations, settings transformations, playback/artwork authorization, logout barriers, queues, and disposal.
- Entire `app_store.dart`: strict decoding, artwork rewrite detection, exact-byte backup, quarantine, replacement-write queue, client identity, and secure credential adapter.
- `main.dart`, `lineup_app.dart`, restoration view, onboarding controller-listener/input/action paths, protected PIN state, and shell account/logout wiring.
- Selected Setup recovery callers and Plex authentication/authorization entry points.
- Test assertions for malformed inventory, restore/re-entry, retained readiness, cancellation/abort, secure cleanup, blocked/failed saves, cross-domain mutation ordering, selection lifetimes, nested origins, startup recovery, and PIN widgets.

**History reconciliation and sibling hunts**

| Class | Historical mechanism inspected | Current protection and disposition |
|---|---|---|
| C01 | `37416c1e` propagated scan cancellation and aborted obsolete transport instead of merely dropping results. | `_invalidateOperation` completes the scan cancellation lifetime; scan callbacks reject stale epochs; cancellation reaches library/playlist requests. Controller transport-abort tests inspect real abortable requests. No new stale scan publication defect established. |
| C02 | `204e0648` serialized controller snapshots/mutations; `c7c393aa` moved selection publication after persistence; `3fc568d9` replaced collision-prone quarantine names with exclusively owned containers. | State snapshots derive inside one queue; settings/channel/current-selection writes publish after save; selection failure retains old lifetime; logout waits behind started state work. Backup/quarantine preserve original bytes. No new data-loss sibling established. |
| C03 | `5598005e` replaced cloud credentials on PMS requests with resource-issued server access and bounded recovery. | Account/profile tokens remain private cloud scope; PMS tokens remain runtime-only; secure writes/clear have a separate queue. Distinct-token, refresh, supersession, and safe-error tests inspect these boundaries. No new credential-isolation defect established. |
| C08 | `9534b282` retained nested picker origins; `9aebd4c7` restored first-run sign-out exits. | Current origin state and Back/Escape callers retain immediate/outer destinations. Servers and no-library setup expose confirmed sign-out. Old F03/F04 are corrected. A01 is a separate completion/presentation seam. |

October 7 F01 is corrected by strict inventory parsing and controller preservation tests. F05/F06 are addressed by committable readiness, enrichment-aware retries, and playlist progress. I inspected the relevant `64be4860` and `f2eda950` diffs rather than relying on titles.

Known profile-token compensation residue, replacement-PIN cancellation, ambiguous profile-authentication taxonomy, plaintext metadata, and multi-instance policy remain explicitly recorded limitations in `product-parity.md`; they are not promoted as newly discovered regressions.

**Journey/action and claim checks**

| Journey/claim | Owners and evidence inspected | Disposition |
|---|---|---|
| J01 linking: expiry, terminal failure, cancel, secure retry | Controller PIN lifecycle; onboarding retry focus; credential-write/cleanup failure tests | Source aligns with bounded, safe recovery copy. A01 affects protected-profile completion. |
| J02 relaunch/restoration | Server-scoped saved selections; staged scan; required collections/playlists; schedule migration; bootstrap restore barrier | Saved data retained on inventory/enrichment failures; successful restored readiness supports setup re-entry. Physical relaunch remains outstanding. |
| J04 profile/server transitions | Save/publication barriers, old authorization during save, cancellation origins, refreshed access, logout queues | Strong controlled-race coverage; A01 survives those controller protections at the UI completion seam. |
| J10 persistence/startup recovery | Strict decoder, quarantine/backup, startup failure/banner, dismissal tests | Corruption and transient IO are distinguished; original bytes preserved. OS-specific acceptance remains outstanding. |
| User guide lines 48–52: secure cancellation before new link | `cancelLinking`, `secureCancellationRequired`, onboarding retry action | Agreement. |
| User guide lines 63–79: profile/server and credential isolation | Scoped maps, `_stateSnapshot`, private tokens, secure adapter | Agreement in inspected source. |
| Architecture lines 313–335: persistence and logout ordering | Selection commits, state/credential queues, mutation eligibility, controlled-save tests | Agreement. |
| Architecture lines 338–350: restoration readiness/origins | `_pendingScanScope`, retained readiness, origin restart, restore widgets/tests | Agreement for inspected controller flows. A01 is additional. |
| Product parity protected-PIN recovery | PIN widget tests primarily use overridden/fake profile completion | Existing evidence does not cover real profile commit followed by saved-server failure. |

**Dimension notes and limits**

| Dimension | Result |
|---|---|
| Architecture/ownership | Controller owns mutations and lifetimes; store owns replacement IO; native mechanisms remain separate. No material boundary defect established. A01 couples authentication completion to downstream recovery. |
| Correctness/failure modes | A01 confirmed by source trace. No new save/publication, corruption-recovery, or credential-cleanup defect established. |
| Security/privacy | No new leak established. Safe failure vocabulary and private token ownership inspected. Native authenticated-reference containment belongs to Unit D. |
| Concurrency/reliability | Separate queues/lifetimes and bounded four-library dispatch inspected. Explicit cancellation aborts requests. Actual latency and OS cleanup not measured. |
| Maintainability/AI debt | No independent material quality finding promoted. File size and public fixture-friendly fields alone are not defects. |
| Tests/verification | Meaningful controlled failures and real transport assertions exist. A01’s composed path lacks inspected coverage. No suites executed by this reviewer. |
| Operations/configuration/diagnostics | Startup and cleanup failures expose safe copy; scan timing/progress producers inspected. Support-export ownership belongs to Unit C. |
| Build/dependencies/release | Composition, dependency declarations, and CI definition read. No deep package/supply-chain conclusion; Unit E owns it. |
| Docs/DX | Relevant account/persistence/restoration claims reconciled above. Whole documentation review belongs to Unit E. |

Important exclusions: deep Plex parsing/paging and channel algorithms; Guide/Studio/Player interaction; native Windows implementation and harness execution; package/provisioning tools; private stores/logs; generated/cache output; Docker. No independent reviewer calibration occurred here.

No executable tests, cache-writing commands, artifacts, patches, commits, or product edits were made. Final read-only Git inspection still showed the same HEAD and pre-existing dirty paths. Pending parent baselines are not claimed as passing evidence.

Windows/live gaps: actual secure-storage read/write/delete behavior; saved-lineup relaunch and recovery in the packaged app; managed/protected/shared Plex account smoke; network interruption and shutdown during saves; physical keyboard/remote/focus behavior. Portable assertions cannot establish those results.

Automatic approval review rejected the cross-chat callback because it did not accept the retrieved authorization as explicit messaging consent. This terminal report remains here for the parent to retrieve.
