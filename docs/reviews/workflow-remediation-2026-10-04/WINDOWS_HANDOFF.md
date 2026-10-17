# Windows acceptance handoff for the workflow remediation

Status: prepared on macOS; Windows acceptance has not run. The reviewed code
candidate is `15c07703b302284fd80523968052d97ff2ca9ff4` on
`codex/libmpv-reference-security-report`. The subsequent completion-documentation
commit changes no product, tests, runtime or build inputs. The orchestrator's
final response identifies that final HEAD; use its full SHA as the requested
acceptance target and record the actual SHA tested. Do not infer a physical
pass from portable evidence attributed to the code candidate.
Do not use a historical branch tip or treat earlier observations as a fresh pass.

Use [the authoritative Windows campaign](../../windows-native-validation.md)
and [Development prerequisites and commands](../../DEVELOPMENT.md), in order.
This handoff adds the changed scenarios; it does not replace the campaign.
Use a clean checkout at the full requested SHA and keep it fixed. Record the
actual HEAD, build/package hashes, pinned framework/engine/patch/libmpv identity,
Windows/GPU/driver, displays/HDR/DPI, input devices, and actual OS timezone.
The operator supplies authorized media, credentials, and physical judgments.
Keep credentials, tokenized URLs, private media data and personal paths out of
shared evidence. No product edits, push, merge, or publication are authorized by
this acceptance handoff.

## Corrected headless reference gate

Follow Development's authenticated-reference prerequisites: prepared pinned DLL,
Python 3, FFmpeg with libx264 and DASH, and OpenSSL. Configure the documented
Windows build first, then run:

```powershell
cmake --build .\build\windows\x64 --config Release --target authenticated_reference_test
ctest --test-dir .\build\windows\x64 -C Release -R '^authenticated_reference$' --repeat until-fail:3 --verbose --timeout 180
```

The stronger positive control introduced by `d6fff072` requires progress without
a later rejection. Older passes of the weaker checker do not prove it. Record
all three consecutive outcomes and prepared/copied DLL identity. This is
headless production-channel/DLL evidence; physical presentation and real Plex
remain separate. Preserve TLS verification, fail-closed initialization, redirect
and nested-reference containment, and the documented ordered-chapter limits.

## Changed scenarios on the final candidate

| Area | Scenario and distinguishing observation |
| --- | --- |
| Settings and focus | Change distinct settings through Settings and Guide in quick succession; both changes survive relaunch. Exercise a safely controlled persistence refusal: no failed proposal becomes committed, the control remains usable and accessible focus recovers. |
| Channel mutation/currentness | Save/edit/delete/reorder while same-profile/server discovery refresh completes: the successful write and live lineup agree. Switch profile/server during captured or queued work and leave then return: obsolete work cannot publish into the new scope. |
| Authorization | Trigger controlled native authorization rejection during same-scope discovery and during pending selection of another server: active recovery still works. Repeat across committed profile/server retirement and logout: obsolete recovery cannot probe or publish credentials for the new scope. |
| Logout ordering | With a controlled slow channel save, exercise successful logout and credential-cleanup refusal. Successful logout clears runtime after the mutation barrier; failed cleanup retains the session and an already-started successful committed change. Old queued work or captured authorization must not resume. Record unavailable fault controls as not run. |
| Quarantine | Recover corrupt state beside an existing legacy file and directory; retain their different bytes/marker. Repeat recovery, including invalid UTF-8, then save and restart: each original corrupt byte sequence survives separately. Exercise safe Windows reservation/rename refusal (for example controlled access denial or a file lock) and confirm startup fails clearly, original bytes survive, and existing recovery artifacts remain untouched. Reservation and rename refusal were source-reviewed only on macOS. |
| Multipart load and seek | Real Plex tune at a nonzero program offset, natural part advance, and cross-part seek wait for correct readiness. Seek twice while the destination loads, including changing the latest target to zero: only the latest target is applied. Repeat destination failure and replacement tune during readiness/seek: no stale seek or hidden failure affects replacement. |
| Authorization during part load | Reject authorization during initial-offset seek and multipart seek. Replacement retains part and latest target, retries at most once, and failed/obsolete recovery produces no late output. |
| Lifetime and surface | Rapid tune/stop/replacement, logout, route return, app close and surface recreation preserve one current native player/lease and correct bounds. Asynchronous failure and failed stop remain visible/retryable; no late frames/audio/events or orphan process. |
| Tracks and interaction | Requested audio/subtitle selection becomes actual output only after native observation; failure/replacement does not falsely confirm it. Verify keyboard, available remote and Windows assistive technology, including Settings/Guide focus and Player-local DVR/classic-TV contracts. |

Do not invent test-only fault injection as a physical result. State the mechanism
used and classify inaccessible cases as blocked/not run.

## Campaign and package obligations still required

Run the existing local SDR smoke before real Plex. Complete the campaign's
Player/PiP/mini-Guide overlays, resize/minimize/restore/fullscreen, route/focus,
monitor/DPI, representative codecs/audio/subtitles, HDR/SDR/fallback and lifecycle
matrix. The current Guide is PiP-only; alternate Overlay Guide is N/A, retired.
Repeat controlled authenticated redirect/nested-reference rejection through the
app with no credential leakage or late output, including recovery afterward.

Build/package during the future authorized Windows acceptance execution and the
existing exact-artifact procedure. Verify clean-checkout provenance, licenses,
manifest/hashes and clean-environment launch; repeat mandatory SDR/Plex/Guide
and authenticated redirect scenarios from that exact archive. Exercise missing
and restored Vulkan loader only in an operator-approved disposable environment.

Use the existing report template under `build/native-acceptance/<commit>/`.
Classify every scenario as Pass, Fail — blocker, Fail — non-blocking, or
Blocked/not run; share only a sanitized summary. Portable Dart/widget/fake
checks, host filesystem fixtures, source review, headless CTest and compilation
each establish distinct facts. None substitutes for physical Windows acceptance.
