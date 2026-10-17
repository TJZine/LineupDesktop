# Final code-quality plan review

October 15, 2026. Final source review of implementation-plan revision 2;
accepted corrections are incorporated in revision 3.

## Verdict and scope

**Ready to begin implementation after P0 preparation and explicit execution
authorization.** No unresolved material design or execution contradiction was
established after the corrections recorded below. Suspected defects remain
execution-time confirming-test assignments. This is not a claim that they were
reproduced, product tests passed again, or Windows behavior was accepted.

Reviewed HEAD: `8c824420cad48d9af9aa01eb29cef200d1030121`, branch
`codex/desktop-ui-second-pass`. The plan's source anchors remain `7afa3688`;
the intervening commits do not change `lib/` or `test/`. The working tree
contained the two pre-existing tracked changes (`.github/workflows/ci.yml`,
`docs/README.md`) and untracked code-quality/feature-planning documents.

The controller read the whole plan and traces and checked integration,
authorization, verification, baseline, and documentation requirements. Four
bounded read-only reviews checked separate technical questions:

- B/C: controller/store and playback transactions, currentness, coalescing.
- D/E/U/V/W/Y: authoring, Guide, input, and visible-behavior preservation.
- F/M: native restoration, protocol, and Windows acceptance boundaries.
- A/L/S/K: Plex decoding/paging, worker messages, and diagnostics policy.

Material findings were reconciled against source before editing the documents.
Only planning/review/handoff documents were changed. No product implementation,
new product tests, native build, full portable suite, external publication,
Git integration, or separate implementation chat dispatch occurred.

## Interrupted-work reconciliation

The user's last Opus message said T6/T7 and factual corrections remained.
The on-disk `TRACES.md` already contained both sections when review began.
The corrected coalescing ordering and NF-16/NF-23 identifiers were also already
present. Review used those saved files, not the interrupted status as authority.

Remaining discrepancies in the traces were corrected, including the
investigator provenance, coordinator subclass count, native eviction policy,
restoration-divergence heading, and pager constant. The gap sweep's statement
about no reproduced additional defects is now distinguished from the original
CQ-09 parser probe.

## Accepted corrections

Source locations below describe the unchanged source at the anchored revision.

| Area | Finding / mechanism | Correction in revision 3 | Evidence |
| --- | --- | --- | --- |
| B / NF-07 | Clearing restore intent from a stale continuation can overwrite a newer restore's flag. | Gate creation of restore intent at the existing successful-publication assignment by request currentness; still publish durable selection state. Add an old-completion/new-restore control. | `lineup_controller.dart:931-958`, `_invalidateOperation:2643` |
| C / NF-10 | Recovery replaces a request during channel persistence; both success and failure can reach a request-mismatch return without settling tuning. | Specify stable lineage, successful settlement with recovered request, failed-owner tuning settlement and guarded rollback/cleanup, plus newer-tune controls. | `player_coordinator.dart:771-790, 1028, 1185` |
| B credentials | Saying credentials publish only with server selection excludes valid profile/initialization/logout effects. | Qualify server-token ownership and preserve profile token publication/old server cleanup after save. | `lineup_controller.dart:764-767` |
| C exceptions | Ordinary store IO was absent from the expected-error list. | Keep `FileSystemException` or an established normalized store failure in the expected path; test user-facing failure without programming-error reporting. | `app_store.dart:250` onward |
| C privacy | Proposed raw exception/stack reporting was described as an existing pattern, but the actual pattern reports fixed safe data. | Report a fixed internal error/context for unexpected failures; do not introduce a raw exception/stack sink. | `player_coordinator.dart:2032-2037` |
| C notification | The corrected ordering absorbs reconciliation reentry, but further rounds also need disposal guards. | Guard each reconciliation/publication/loop continuation and test bounded listener-origin re-publication. This is defensive preservation, not a reproduced supported synchronous-disposal bug. | Plan C pseudocode; `ChangeNotifier` lifetime contract and existing disposal guard |
| D undo | Pruning removed occurrences was incorrectly called existing behavior and exceeded the replacement-only approval. | Explicitly include removal pruning in §2.2b and cover last/partial removal; retain move/save behavior. | `channel_studio_view.dart:2488-2510`; TRACES T3 |
| D verification | The shorthand “valid” can exclude supported retained-off-air manual programming. | Both matching-key `valid` and `retainedOffAir` participate in exact identity commitment/save authorization. | `channel_studio_view.dart:2966-2974` |
| U badges | The proposed helper lacked runtime codec facts needed by current Now Playing. | Pass an effective codec or compose it outside; preserve `videoFormat → item.videoCodec → telemetry.videoCodec`. | `player_view.dart:1430-1442` |
| V notifications | Stale row results can still change active-load/queue observables used for the activity pulse. | Publish once after final bookkeeping/pumping if observables change; test stale last-load and current queued work. | `guide_controller.dart:819-823`; `guide_view.dart:481-491` |
| V viewport | Equal channel IDs/range do not prove the demand is current after schedule invalidation. | Include content/schedule generation or equivalent invalidation in deduplication. | `guide_controller.dart:981-1030` |
| W health | The proposed monitor listed concurrency/cache but omitted pending bound and signature obligations. | Preserve queue bound 12, concurrency 2, cache 1000, signatures, epochs, and same-channel serialization; defer build-discovered demand safely. | `channels_view.dart:45, 1155-1256` |
| U modality | Focus-ring visibility is not actual last-input modality, and history can be inconclusive. | Keep distinct facts; preserve current reset behavior when intent is unknown and retain pointer-activity handling. | `lineup_focus.dart:40-43`; `player_view.dart:164, 450` |
| D/E/U text checks | Equality of every string literal contradicts removing internal settings keys. | Use literal differences as triage; preserve visible text except approved changes. Do not retain dead internal identifiers. | `lineup_shell.dart:1259-1267` |
| Test gates | T compared against P0 even though A/H add tests; global monotonic counts overstate evidence. | Compare actual package bases and preserve distinct obligations through maps; counts remain diagnostic. | Package dependency order and T's fake-only migration |
| D3 scope | A line-count threshold allowed requested work to disappear without addressing its ownership burden. | Keep D3's concrete picker/editor coordination scope; return actual feature-design conflict instead of silently deferring. | Original complete-scope instruction and plan D3 |
| M/T4 queue | Non-property events first evict a queued property, not unconditionally the oldest event. | Correct both plan and trace; wire behavior is unchanged. | `native_player.cpp:1254-1267` |
| F/T4 history | Restoration attempts were listed as a fourth durable-true/live-false divergence. | Keep the first three divergences; move restoration into a separate asymmetry note. | `display_dynamic_range.cpp:423`; `display_recovery.cpp:246` |
| F integration | “Pending” meant both unmerged and permitted unverified integration, and could still count as complete. | Pending means retained unmerged candidate; all required Windows CTests gate integration. Distinguish portable delivery, full integration, and physical acceptance. | Plan §§2.1, 6.2, 8.4; actual CI/CTest tiers |
| A decoding | “Non-list” was ambiguous for null and could broaden unused media-version parsing. | Preserve absent/null empty defaults and existing first-Media/first-Part consumption; test controls. | `plex_client.dart:1579-1588, 1642` |
| L paging | Codes alone do not preserve endpoint policies and private subtype-based collection classification. | Carry oversized-complete options, raw offsets/counts, callback/check ordering, occurrence semantics, and limit-exception factories/types. | `plex_client.dart:602, 640, 730, 769`; `plex_library_scan_test.dart:672` |
| K diagnostics | Ingest sanitation and export admission intentionally differ. | Share per-key definitions while retaining separate operations and forged-snapshot filtering; expand byte-equivalence fixtures and assert stored values separately. | `diagnostics.dart:86-99, 303-328`; `diagnostics_view.dart:775` |
| S worker | VM-generated error lists/exit null cannot be replaced by application message types. | Type application messages; preserve VM decoding, fail matching/all waiters appropriately, and retain generation/unknown-ID rules. | `schedule_worker.dart:92-130, 174-199` |
| B identity | Narrowing read-error handling must preserve malformed text/UTF-8 recovery; permission bypass can invalidate a chmod observation. | Distinguish absence, malformed content, and filesystem read errors; verify denial and restore permissions in the test. | `app_store.dart:233-249` |
| Y expiry | UI and polling differ exactly at expiration. | Add explicit approval 2.2h and before/equal/after tests, with equality expired consistently. | `lineup_controller.dart:625`; `onboarding_view.dart:322, 385-388` |
| G evidence | An obligation row linking a deleted file does not preserve a live contract or useful evidence. | Preserve rationale and source/build identities, use recoverable commit references, migrate unique authority before deletion, retain documents if still needed. | Repository instructions and G's proposed archive list |
| H guard | A missing pin file silently bypassed the new guard even though temporary fixtures already have an explicit opt-out. | Fail real missing/malformed configuration; keep the fixture skip explicit and tested. | Package H and current formatter fixture harness |

## Confirmed critical contracts retained

- Persist-before-retire and runtime-derived ordinary save assembly stay intact.
- The revised NF-08 queued-predecessor mechanism is plausible from source;
  returning a committed boolean avoids inventing a visible supersession error.
- The synchronous dead tune block is removable; tune serialization remains
  necessary for cleanup ownership.
- Active channels remain nullable where current behavior permits orphaned
  playback after deletion. Tune/content/native-load/stop/track identities stay
  distinct.
- Setup review keeps a fresh anchor, live missing-source evidence, and queued
  expected-base authority.
- Native classification retains live versus durable late-attempt inputs,
  restart/guardian sequencing, and recovery's existing single write behavior.
- Transport rename retains channel/payloads/messages and unsupported macOS
  behavior. It does not implement a macOS player.
- Series/facet consolidation is bounded. TLS, XML-token, PIN-date, and other
  suspected failures remain confirming-test tasks.

## Verification performed and remaining gates

This final pass used document/source inspection, matching source/symbol
references, local link checks, whitespace checks, Git source-identity checks,
and focused reinspection of corrected contracts. No application baseline was
rerun for documentation edits. The plan author's historical 1,567-test baseline
remains attributed evidence, not a fresh result from this review.

P0 must establish and test the actual execution base with the pinned SDK.
Implementation packages must run their specified behavioral checks. Pending
native work is not integrated until every required Windows CTest passes;
physical media/HDR/input/package acceptance remains separate even then.

The [orchestration handoff](../../code-quality-orchestration-handoff.md) contains
a copyable prompt with explicit preparation/Git/callback approval and the safe
default of retaining F pending when Windows is unavailable. It is a prepared
prompt, not a record that implementation was authorized or dispatched here.
