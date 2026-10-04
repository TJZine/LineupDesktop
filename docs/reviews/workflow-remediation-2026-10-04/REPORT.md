# Workflow remediation completion report

Portable implementation is complete; physical Windows acceptance remains open.
The user chose portable work plus a Windows handoff, then authorized conventional
commits for all changes. No push, merge or publication occurred.

## Source and completed scope

Repository: `TJZine/LineupDesktop`, branch
`codex/libmpv-reference-security-report`. Integration began at
`52157d539f61103ff2966f2727a5fe51d50f2aab`. The final product/test candidate is
`15c07703b302284fd80523968052d97ff2ca9ff4`; the subsequent documentation commit
adds this report, plan, handoff and the reviewed architecture update without
changing tested product/build inputs. Resolve the final HEAD from Git for future
exact-artifact acceptance. Pre-existing unrelated untracked and ignored artifacts
were preserved and excluded from commits.

| Group | Executor | Commit | Result |
| --- | --- | --- | --- |
| A | worker, Sol/medium | `e3f36d00` | Controller derives settings inside its queue, saves proposals before publication, and separates discovery currentness from committed mutation and captured authorization lifetimes. Settings and Guide callers submit transformations; view ordering/merge policy was removed. |
| B | worker_luna, Luna/xhigh | `3fc568d9` | An exclusively reserved quarantine container preserves corrupt bytes and existing recovery artifacts despite timestamp collisions; startup evidence uses the new layout. |
| C | worker, Sol/medium | `5acae4d1` | Tune, part advance, cross-part seek and authorization replacement share one complete part-load operation while retaining latest targets, readiness, bounded retry and native cleanup/track distinctions. |
| D | worker_luna, Luna/xhigh | `15c07703` | Removed four test-only controller facades after migrating proof to real production operations, dormant surface presentationEpoch, and one subsumed timeout assertion. |

No Player layout redesign, native API change, transcoding/session implementation,
workflow rewrite or broad test-slimming campaign was included. The earlier
completed slimming deletions were not repeated. Detailed contracts, logout
adjudication and actual chat dispatch are recorded in [the execution plan](PLAN.md).

## Review and evidence

One independent Sol/high reviewer inspected all 13 A/B/C/architecture changed
tracked files at base `52157d53`, tracked diff SHA-256
`4c223856b2c9430eb26543ccdd70487ccbe53c8c4709b97d61d1a996b8c81a15`.
Requirements/correctness and design/standards review established no material
blocking or worthwhile findings. This was source review, with worker results
attributed rather than rerun. The parent inspected D's actual five-file diff and
proof migration; its SHA-256 was
`784ec47d31e4f42db17f6c4259db0b52dff1c5517395760aafaf56e4010dd5d9`.

Worker focused results:

- A: eight controller/settings/Guide/product suites, 218 passes; targeted analysis
  clean. Initial legacy-migration regression was repaired by restoring
  account-link scope retirement, retaining the assertion.
- B: store/startup suites, 63 passes. Real host temporary-filesystem fixtures
  observe legacy artifacts, fixed-clock repeated corruption, invalid bytes,
  restart/save retention and the live recovery banner.
- C: coordinator/Windows adapter suites, 147 passes; targeted analysis clean.
  Initial failed-load OSD regressions were repaired before the successful run.
- D: controller, 108 passes; product-spine/surface/transport, 130 passes;
  targeted analysis/formatting clean. Production/test/harness/visual source has
  no obsolete public references (successful search, no matches).

The parent observed combined acceptance on stable source now committed as
`15c07703`, on macOS with Flutter 3.47.6, framework
`5fc346839b5d0eef006ed8404392afb4dfae428d`, Dart 3.13.5:

| Command or observation | Result and boundary |
| --- | --- |
| `flutter analyze` | Passed, no issues; global static analysis. |
| `TZ=America/New_York flutter test` | Passed, 955 tests; deterministic, fake-boundary and Flutter widget evidence, including macOS Guide alpha. |
| `dart format --output=none --set-exit-if-changed .` | Exit 1: 20 pre-existing ignored capture scripts under `build/` would change. Output-none made no edits. This broad command is not reported as passing. |
| Same formatter on all `git ls-files` Dart paths | Passed, 80 files, zero changes; all tracked Dart source/test/tool files formatted. |
| `git diff --check` | Passed; final documentation links/claims checked against their repository owners. |

Focused results are not added to the full-suite count as distinct tests. The
product-spine and native adapter checks use fake boundaries and do not establish
real Plex/native media. No dependency or runtime inputs changed; no unnecessary
package provisioning, application build or visual baseline regeneration was run.

## Retained proof and limits

D moved distinct scan, commit failure/rollback/retry, expected-base reviewed-plan,
asynchronous schedule/projection retry and expected-channel deletion proof to
their current consumers. Empty/unsupported scan facts remain scan observations;
the retired permissive facade does not define a product commit obligation.
Player identity bounds invalidation, geometry/DPR, deduplication, teardown and
failure retry remain. The retained timeout case checks the same stable error
plus abort and late-body cancellation; timing-boundary, socket and body-deadline
cases remain. No test count or coverage policy target was used.

Quarantine reservation and post-reservation rename refusal are source-reviewed,
not fault-reproduced on this host. Windows filesystem behavior, real track
confirmation/output, native lifetime/composition/input, HDR and package operation
remain unaccepted. The corrected authenticated-reference checker still requires
three consecutive Windows CTest runs at the pinned prepared/copied DLL; earlier
weaker positive-control passes are insufficient.

[The Windows handoff](WINDOWS_HANDOFF.md) gives the exact changed scenarios and
links the authoritative campaign, including multipart latest-zero/recovery,
same-scope authorization, logout ordering, quarantine preservation/refusal,
physical focus/assistive technology, media/HDR and clean exact-package acceptance.
No physical Windows, native CTest, build or package pass is claimed here.
