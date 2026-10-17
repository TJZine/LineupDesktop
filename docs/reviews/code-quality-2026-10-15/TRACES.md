# Code-quality verification traces (2026-10-15)

Evidence appendix for [the implementation plan](../../code-quality-implementation-plan.md).
Five initial read-only investigators produced T1–T5 at HEAD `7afa3688`
(working tree with the pre-existing engine-identity edits); two gap sweeps
supplied T6–T7. They read source and ran nothing. Final review at `8c824420`
corrected the factual notes below; `lib/` and `test/` remain at the same source
anchors. The separate original parser probe is attributed in the assessment
handoff, not claimed as a run by these investigators. Anchors refer to that
state; symbols are
durable. "Suspected" items are hypotheses until a test confirms them (see the
plan's §4.2).

Abbreviations:

- LC = `lib/app/lineup_controller.dart`
- PC = `lib/playback/player_coordinator.dart`
- PCT = `test/playback/player_coordinator_test.dart`
- DM = `lib/playback/display_matching.dart`
- SV = `lib/app/channel_studio_view.dart`
- AC = `lib/app/channel_air_check.dart`

---

## T1. Controller commits (CQ-01, CQ-02)

### PersistedState (`lib/persistence/app_store.dart`)

Fields (21-27):

- `settings`
- `profileId`
- `selectedServerByProfile` (profile→serverId)
- `selectedLibraryIdsByProfileServer` (profile→server→List<String>)
- `channelsByProfileServer` (profile→server→List<Channel>)
- `currentChannelByProfileServer` (profile→server→String)

`toJson` is hand-written (29-44). `fromJson` requires exactly these six keys
(50-61) and parses through `_flatStringMap`, `_librarySelections`,
`_channelSelections` (which calls `validateChannels`), and
`_stringSelections` (89-138). Any parse error becomes a `FormatException`,
which `load` quarantines (183-188). The profile key is
`profile?.id ?? account?.id` (LC 410, 815, 874, 2276).

`_persisted` is assigned at LC 470 (load), 762 (profile), 916 (server), 1486
(`clearSavedServer`), and 2265 (`_save`). `PersistedState` is built in only two
places: `_stateSnapshot` (2314) and `clearSavedServer` (1475).

### Queues

| Queue | Location | Behavior |
| --- | --- | --- |
| `_queueStateOperation(epoch)` | LC 2335 | Skips stale `_epoch`; sets `_setupStateCommitInProgress` |
| `_queueScopeOperation(scope)` | LC 2354 | Checks `_mutationScope`, `_mutationEligibility`, `_logoutFuture` |
| `_queueGlobalStateOperation` | LC 2402 | Checks disposal only |

All three chain on `_stateOperations`.

### Commit owners

| Operation | Derive | Save | Success publication | Retirement | Failure |
| --- | --- | --- | --- | --- | --- |
| `selectProfile` 725 | `_stateSnapshot(profileId: selected, serverId: null)` 753 | `_persistState` 755 | `_persisted`, `_profile`, `_profileToken`, `_serverAccess`, `_pmsToken`, server, servers, connection, picker flags, libraries, library ids, media, playlists, channels, current, scan reset, `_contentGeneration++`, stage (762-784) | `_retireScope` 763, after save | Restores cancel flag and origin (757-758); rethrow; `_run` falls back to profiles |
| `selectServer` 844 | Reads the 3 maps; filters ids by loaded libraries (873-903) | 908 | `_serverAccess` (refresh-aware 914-915), `_persisted`, picker origin, server, connection, `_pmsToken`, libraries, library ids, media and playlists cleared, channels, current, stage, `_channelSetupCanCancel`, scan reset, `_restoringSavedLineup`, generation (916-934) | `_retireScope` 917, after save | Restores `_serverSelectionCanCancel` (910); rethrow; falls back to servers |
| `_commitScannedLibraries` 1030 | Rows plus migration (1049-1060) | `_save` 1061 | library ids, media, playlists, channels, `_scan.status`, generation (1066-1071) | None; a stale scope returns silently (1065) | `_run` sets error |
| `_commitChannelList` 1652 | Runtime `channels` | `_save` 1666 | `_publishChannelCommit` (1676), which records revisions | Stale scope throws `StateError` (1671) | Rethrow; nothing published |
| `setCurrentChannel` 2115 | Runtime | `_save` 2122 | `_publishCurrentChannel` | `StateError` (2124) | Rethrow |
| `updateSettings` 2130 | `change(settings)` | `_save` 2135 | `_settings`, `diagnostics.enabled` (2141) | Disposal check only | Rethrow |
| `_migrateLegacySchedules` 1880 | Runtime channels | `_save` 1890 | Channels and revisions, if still in scope | — | Rethrow (the try/catch at 1889-1893 has no effect) |
| `clearSavedServer` 1466 | Hand-built from `_persisted.*` | 1485 | `_persisted`, then `_clearServerRuntime` | Inside `_clearServerRuntime` | Falls back to servers |

`_save` (2250) calls `_stateSnapshot`. That deep-copies all maps and fills the
current scope with each override, or the runtime value when there is none
(2298-2313). It sets `_persisted` even if the scope was superseded, which is
correct because the disk now holds that state.

### Server-selection transitions

| Case | Behavior | Guard |
| --- | --- | --- |
| Success | network → queue → derive → hide cancel → save → retire → publish → restore scan (937-952) | Epoch checks at 860, 871, 936, 939, 946 |
| Save failure | `_persisted`, runtime, and old lifetime unchanged; cancel restored; a queued reorder still runs | No retirement before save success (917) |
| Refresh during save (playback recovery) | Refresh writes `_serverAccess` (2599); commit takes `_serverAccess[id] ?? access` (914-915) | `forPlayback` (2603); `_authorizationScope` retired at 917 |
| Refresh during save (`refreshServers`) | The started body publishes. The epoch bump stops the restore at 936. `_restoringSavedLineup` (931) may stay true because the epoch check at 958 fails. The UI disables refresh while busy (`onboarding_view.dart:893`). **Suspected NF-07; untested.** | Epoch only |
| Logout during commit | Logout bumps eligibility and epoch, then gates the queue (2177-2184). A started body publishes the target; logout clears after `await stateBeforeLogout` (2203). If credential cleanup fails, logout returns before that await (2195-2200) and the target stays published. A queued, not-started body is skipped (2340). | Epoch, `_mutationEligibility` |
| A→B→A | A late scan is rejected by the epoch (1007, 1107, 1139). Old readiness fails because `_scan.reset` runs (930) and `contentScope` no longer matches `_mutationScope` (127, 1035). Captured playback recovery fails through `_authorizationScope`. A queued channel operation fails on scope and eligibility (2357-2358). PMS refresh is targeted with `_serverTargetId` (2652). | `_epoch`, `_mutationScope`, `_mutationEligibility`, `_authorizationScope` |

### `_commitScannedLibraries` (1030-1077)

- **Pre-queue checks (1034-1038):** `pending != null`;
  `readinessScope == _mutationScope`; ids non-empty; `_scan.ids ⊇ ids`;
  `libraryScanReadyIds ⊇ ids`. Only the non-empty check and the ready-ids
  check are effective, because `readyIds(scope)` (127) is empty unless the
  scope matches.
- **In-queue recheck (1043-1044):** checks scope and
  `identical(_scan.readiness, pending)`. It does not recheck ids readiness.
- **Required sources:** `_requireAvailablePlaylists` and
  `_requireAvailableCollections(pending, libraryIds: ids)` (1047-1048).
- **Media source:** media comes from the live `_scan.rows` (1052), not from
  the readiness snapshot.
- **Silent success (suspected NF-08, corrected by the factual review):**
  1065 is unreachable. Every scope bump follows an epoch bump or runs in
  another queue body. The reachable path: a queued `selectServer` or
  `selectProfile` body retires the scope and resets the scan (917, 930); the
  scan body then returns early at 1043-1045, while `_isCurrent` stays true
  (2622).
- **Status write:** `_scan.status = _scan.statusFor(ids)` (1070).

Surface of `_LibraryScanState` that the controller touches:

- Fields: `status` (written at 940, 1070, 1266 and `lineup_scenario.dart:167`),
  `rows` (read at 1052, 1184), `failure`, `playlistProgress`, `readiness`,
  `readinessScope`, `ids`, `_cancelled` (2369; `lineup_scenario.dart:154`).
- Methods: `stage`, `beginRefresh`, `prepare`, `finishRefresh`,
  `interruptRefresh`, `cancel`, `reset`, `statusFor`, `result`, and the IO
  methods.

### Additional gaps

- `clearSavedServer` builds state separately and uses `_persisted.settings`.
- The empty-lineup publication appears 4× (476-478, 774-779, 2213-2222,
  2440-2446).
- The restore path in `selectServer` (937-952) is a second
  scan→inventory→migration flow.
- The scan commit publishes migrated channels without
  `_recordChannelChanges` (1069), unlike 1683 and 1896 (NF-09).
- The fixture actor (`lineup_scenario.dart:111-186`) publishes field by
  field.
- Some tests rely on runtime state being the save base (8292/8316,
  8485/8533).

### Protecting tests

`test/app/lineup_controller_test.dart`:

- Queues: 44, 139, 351, 2245, 6841, 6886, 6927, 6977, 7058, 7092, 7138, 7224,
  7262, 7295, 7477, 8008, 8038
- Selection: 7550, 7896, 7931, 8076 (5 variants), 8242
- Logout: 7031, 8272, 8335, 8385
- Same-scope refresh: 8464
- Channel commits: 2504, 2545, 3919, 4124, 6129
- Migration: 2748, 2820
- Scan: 926, 951, 1015, 1037, 1089, 1109, 1166, 1223, 1292, 2267, 2343, 4711,
  5105

`test/persistence/app_store_test.dart`: 44, 101, 162, 211, 237, 266, 311, 347,
656, 741, 850, 882, 917, 950, 984, 1029, 1042.

---

## T2. Playback session and publication (CQ-03, CQ-04)

### Fields by lifetime (PC)

| Group | Fields |
| --- | --- |
| Request/channel/program | `_activePlayback` 137, `_activeChannel` 139, `_loadedProgram` 76 |
| Resolving | `_resolvingProgram` 77, `_retryChannelId` 140 |
| Currentness | `_tuneGeneration` 116, `_continuationGeneration` 117, `_controlGeneration` 119, `_seekGeneration` 121, `_tuning` 108, `_canRetry` 109, `_error` 104, `_tuneOperations` 129 |
| Native load | `_nativeLoadGeneration` 123, `_activeLoad` 124 (`_PlaybackLoad` 2043-2068), `_nativePosition` 81, `_advancingGeneration` 128 |
| Multipart | `_partDurations` 127 |
| Auth recovery | `_authorizationRecovery` 138 (`_AuthorizationRecovery` 2070) |
| Native stop/scope | `_nativeStopOperation` 130, `_nativeCleanupRequired` 131, `_scopeCleanup` 132, `_scopeCleanupPending` 134 |
| Native facts | `_status`, `_position`, `_duration`, `_telemetry`, `_tracks` 78-83 |
| Track confirmation | `_pendingTrackType` 113, `_pendingTrackId` 114, `_trackSelectionError` 115, `_trackConfirmationTimer` 95, `_trackSelectionGeneration` 120 |
| Sleep | `_sleepTimer` 86, `_sleepEpoch` 99, `_sleepDuration` 110, `_sleepDeadline` 111, `_sleepPickerOpen` 112 |
| Overlay | `_overlay` 100, `_overlayTimer` 85, `_overlayEpoch` 96, `_overlayPresentationGeneration` 97, `_overlayFocusSuspended` 98, mini-guide 102-103, channel-number fields |
| Cursor/notice | cursor and notice timers and flags |
| Busy | `_busyTimer` 90, `_busyLabel` 92, `_busyIdentity` 93 |
| Display | `_playerDestinationVisible` 62, `_fullscreen` 105, `_fullscreenEpoch` 122, `_fullscreenOperations` 133 |

The triple is set together only at 753-757. It is cleared together at
521-523, 745-747, 760-762, 774-776, 811-813, 816-818, 1675-1677, and
1959-1961. It is cleared partially at:

- 1028 (recovery replaces the request only)
- 1785 (lineup refresh replaces the channel only)
- 1906-1907 (`_resetScopeState` clears channel and program, not the request)
- 2019-2020 (`dispose` clears request and program, not the channel)

The track-confirmation fields are always cleared together in
`_clearTrackSelection` (1392).

### `_performTune` (672-831)

1. Await the native stop; on failure, publish an error if still current
   (686-694).
2. Generation check (696). `ensureCurrentProgram` (697), then a check (698).
   A null program retires an ended continuation or publishes an error
   (699-710).
3. Continuation successor (712-727). `_resolvingProgram` (729).
   `previousChannelId` (732).
4. `playbackFor` (734), then `_loadPlayback` (737) →
   `_loadPartAtPosition` → `_startLoad` → `player.load` (868). Then
   `_completePartLoad`, which awaits readiness and loops pending seeks
   (956-974). A superseded load returns null, which throws
   `PlayerUnavailable('superseded')` (911).
5. Conditional clear if the triple still holds the replaced request (744).
   Supersession check (749): stop only if `_tuning || _disposed`.
6. Commit the triple (753). **758-770 is dead code**: no `await` separates
   it from 749-757.
7. `await lineup.setCurrentChannel(channelId)` (771). In LC 2115 that is a
   queued save, then `StateError` on mutation-scope supersession (2124),
   then `_publishCurrentChannel`.
8. Superseded after persistence (772-784): clear, roll back the current
   channel, stop conditionally. Identity lost (785-791): roll back and stop.
   Neither path resets `_tuning` or publishes an error.
9. Success (793-807).
10. Catch (808-827): conditional clears, `_stopQuietly` if a request exists,
    error if still current.
11. `finally` clears `_resolvingProgram` if still current (829).

**Invariant.** `_performTune` runs serially through `_tuneOperations`
(644-647, 1232, 1870). A loser's `_stopQuietly` can reach only the pending
stop or a no-op, never the winner's load.

| Transition | Path | Cleanup owner |
| --- | --- | --- |
| Success | 753 → 771 → 793 | Native load live; `_nativeCleanupRequired` true (863) |
| Superseded by a newer tune | Newer `_tune` → `_beginNativeStop` (635) retires the intent (1930); the loser's load gets null → 911 → catch → `_stopQuietly` returns the pending stop | The newer tune's `_beginNativeStop` |
| Stop during load | `stop()` 1223: generation++, forced stop (1230), queued stopped publication (1232) | `stop()` |
| Native load failure | Readiness error 947 → rethrow 955 → `_completePartLoad` catch → rethrow (983) → `_performTune` catch 808 | `_performTune` catch |
| Current-channel persistence failure | 771 throws → 808 | `_performTune` catch (PCT 1995) |
| Auth recovery mid-load | `_event` 474-498 creates the recovery; `_completePartLoad` 950/962/968 → `_completeLoadRecovery` → `_recoverAuthorization` reload (1016) | Replacement failure → catch; non-pending → `_settleActiveAuthorization` → `_failTransition` (1067) |
| Multipart with a pending seek | `_advancePart` 1154 does not touch the triple; `seekTo` 1297-1301 sets `load.target`; the loop at 956 applies the latest target; a cross-part seek starts a new load (1293), and the old load returns null via `_ownsLoad` (937) | Failure → `_failTransition` (1181) |

**Suspected NF-10.** A 401 that arrives while 771 is awaited sees `wasActive`
true (490). Recovery sets `_activePlayback = next` (1028). Line 785 then
detects an identity mismatch, rolls back, and stops, but `_tuning` stays true
and no error is shown. The nearest test, PCT 4838, covers a terminal error
during persistence, where `_event` resets `_tuning` (519).

Failure variation to confirm as well: `_failTransition` (1185) publishes a safe
error but does not clear `_tuning`; the later request-mismatch return can still
leave it true. The owning failed tune must settle, while rollback/cleanup remain
guarded against a newer tune or content scope (plan C revision 3).

### `notifyListeners` override (285-322)

What it does:

1. `_updateDisplaySession()` (287→324). `DM.updateSession` (63) sets
   `session` before `_send()` (68, native `setDisplayMatching`). It may
   create a hold (72), or call `_finish(resume: true)` (76) →
   `player.play()` (268) → `changed()` (270).
2. Computes the busy identity from `displayHoldActive` and sets or cancels a
   2-second timer (288-320). The timer calls `notifyListeners` (317).
3. Calls `super.notifyListeners()`.

`changed: notifyListeners` (49) is invoked from DM `receive` (193) and
`_finish` (270). The path is re-entrant: outer notify → `updateSession` →
`_finish` → inner notify (its `updateSession` returns early at 63) → inner
super notify → outer super notify. **Listeners are notified twice.**

HDR ordering constraints:

- `updateSession` before the busy calculation.
- `session` assigned before `_finish`.
- `_startLoad` runs `cancelLoad` (860) → `_updateDisplaySession` (861) →
  `beginLoad` (862).
- `_event` runs `cancelLoad` (390) and `suppressTransition` (400) before
  mutating status.

Busy state is also mutated in `_clearTransientStatus` (279-281).

Call sites (30: 28 in PC plus DM 193 and 270):

| Category | Lines |
| --- | --- |
| Cursor | 1701, 1708 |
| Progress / native facts | 618 (gated by `_eventVisibleFacts`) |
| Tune / stop / retire | 643, 799, 881, 1064, 1158, 1165, 1231, 1239, 1685 |
| Fullscreen | 1418 |
| Route visibility | 68 |
| Display report | DM 193, DM 270 |
| Overlay | 1495, 1561, 1575, 1730, 1754 |
| Other | constructor 57; notices 268, 270; busy 317; tracks 1328, 1360, 1377; lineup/settings/scope 1853; guide 1862 |

### Consumers

| Consumer | Reads | Filtering |
| --- | --- | --- |
| `_shellPlayerFacts` (`lineup_shell.dart:98-109`) | 9 getters | Equality gate (111-116); telemetry and display report compared only on route 3 |
| `PlayerView._changed` (`player_view.dart:84-137`) | Overlay, presentation generation | None; always calls `setState` (needs every publication) |
| `_eventVisibleFacts` (PC 342-376) | Producer-side gate for native events | Not a consumer |

`PlayerTelemetry` has no `==` (`native_player.dart:419-458`), and the
transport copies it on every property event (`windows_native_player.dart:560-716`).

### Catch clauses in PC

| Lines | Classification |
| --- | --- |
| 686, 947, 961, 1256, 1362, 1409, 1432, 1658 | Deliberate native boundary |
| 976 | Deliberate; rethrows unless an owned transition |
| 1187, 1920 | Deliberate quiet stops (cleanup retried later; no diagnostics) |
| 2031 | Deliberate; replaces the exception with a generic `StateError` |
| 661, 808 | **Questionable**: a programming error becomes "Playback could not start" (`_safePlaybackError` `_` arm, 1983) with no stack |
| 1065, 1311 | **Questionable**: catch the `StateError` supersession signal together with real errors |

The `catchError` handlers at 647, 1241, 1420, 1879, 1890, 1947, and 2022 are
deliberate chain keepers.

### Protecting tests

- **Tune/session (PCT):** 1919, 1973, 1995, 4838, 3726, 3757, 3793, 3821, 3855,
  3903, 3934, 4004, 4042, 4583, 4620, 6083, 6117.
- **Multipart/recovery (PCT):** 4902, 4939, 5021, 5058, 5140, 5188, 5236, 5374,
  5412, 5452, 5654, 5720, 5806, 5850, 5959, 6003, 6038.
- **Live join (PCT):** 640.
- **Tracks (PCT):** 2209, 2254, 2320.
- **Publication/busy/HDR (PCT):** 67, 199 (route visibility 207/224), 240, 289,
  363, 402, 433, 1332, 1464, 3091, 3219, 3331, 3375, 2922.
- **`display_matching_test.dart`:** 8, 50, 68, 99, 169, 201, 220, 298, 318,
  361, 424.
- **View and shell:** `player_view_test.dart` 43, 96;
  `desktop_navigation_test.dart` 648; `lineup_app_test.dart` 466.

---

## T3. Authoring (CQ-05, CQ-06, CQ-07)

### Manual rundown state in SV

| Item | Line | Role |
| --- | --- | --- |
| `_ManualEntry {id, item (mutable), occurrence}` | 35-45 | Occurrence record; `occurrence` used only for the first-row `Key` (2335) |
| `_manualEntries` | 128 | Ordered occurrences |
| `_manualKeyCounts` | 129 | Per-id counter; only increases; cleared only in `_configureSource` (252) |
| `_lastAddedEntries` | 148 | Undo set, by object identity; **never cleared on reload, save, move, or remove** (suspected NF-12) |
| `_rundownFocus` | 149 | Map<_ManualEntry, FocusNode> |
| `_manualRundown` | 153 | Browse vs rundown; removing the last entry switches it (2494) |
| `_browseSelection` / `_browseSelectionItems` | 144-145 | Batch selection with captured metadata |
| `_configureSource` | 238-261 | Rebuilds entries from `ManualSource`; disposes focus after the frame |
| `_draftSignature` | 312-319 | Uses retained snapshots |
| `_addManualItem` | 2019-2031 | Fresh inventory only; no-op if missing |
| `_addBrowseSelected` | 2049-2068 | Dedups against the rundown (2054); captured-metadata fallback (2055) |
| `_undoLastAddition` | 2070-2076 | Undo |
| Move/reorder/remove | 2443-2510 | — |
| `_newManualEntry` / `_removeManualEntriesWhere` | 2512-2530 | — |
| `_manualItems()` | 2815-2823 | Fresh inventory if present, otherwise snapshot (preview and save) |
| Snapshot copy-back after save | 3033-3038 | Skipped when lengths differ (inactive-draft case, test 1134) |
| `_reload` | 3091-3109 | `loadSaved` + `_configureSource` |

Repeated persisted ids are created only by `_configureSource` (254). The
draft signature encodes repeated ids with their snapshot JSON
(`channel_studio_draft.dart:190-201`). The UI disables rows for ids already
added (1938, 1959; 1913).

### Air Check transitions

`_ChannelAirCheckState` fields (AC 55-74):

- Request and debounce: `_debounce`, `_requestVersion`, `_active`,
  `_pending`, `_targetKey`, `_wantedOriginalKey`
- Result: `_preview`, `_error`
- Baseline: `_originalSchedule`, `_originalScheduleKey`,
  `_originalScheduleError`, `_originalScheduleErrorKey`, `_originalOffAirKey`
- Reporting: `_reportedStatus`
- Presentation: `_selectedId`, `_selectionFollowsNow`, `_synopsisExpanded`,
  `_futureHours`
- Lifecycle: `_clockTimer`, `_disposed`

| Event | Mechanism | Result |
| --- | --- | --- |
| Draft edit | `_changed` (SV 306) → build: refresh inventory (355), resolve (362), `_stageScheduleIdentity` (375 → draft 277-281) | Preview uses the candidate anchor and seed (draft 232-233) |
| Child receives new inputs | `didUpdateWidget` (AC 99-116); key = `canonicalScheduleIdentity` + generation (1035-1041; `channel.dart:688`, which excludes name and number) | Key or source-issue change: report unknown, then schedule a load. Name or number only: `withChannel`, no re-verification |
| Source issue | AC 130-140 | Unknown; the `retainedOffAir` branch cannot fire |
| Debounce | AC 141-149 (80 ms); `_pending = null` (129) | Version++ ; the initial load is immediate |
| Request | `_enqueueRequired` (152-181) | Baseline first; one active plus the latest pending (189-197) |
| Result success | AC 215-238 | Baseline stored even when stale (same-key recovery); target published only if key and version are current; valid only when `_comparisonReady` (387-390) |
| Result failure | AC 241-262 | Stale dropped; baseline → off-air key (no content) or error key; target → `retainedOffAir` only for retained manual content with no content (382-385), otherwise unknown |
| Drain | AC 263-276 | Next pending request or follow-up |
| Report | `_reportValidity` (396-406) | Deduplicated; posted after the frame to `onValidityChanged` |
| Studio accepts | SV 490-496; `_isCurrentAirCheckStatus` (2966-2974) | Recomputes the key; valid or `retainedOffAir` |
| Identity commit | `_commitScheduleIdentity` (2983) → draft 283-303 | Commits the exact candidate |
| Save button | `canSave` (SV 780-786) | **Does not check `scheduleIdentityCommitted`** |
| Save | `_save` gate (3012) | Requires both |
| Baseline failed | `_comparisonFailed` (392) | Unknown; "Retry comparison" (599-605) |
| Off-air baseline | AC 245-248 | Comparison ready; on-now warning forced (895) |
| Retry | `retry()` (183-187) | Debounced reload |
| Generation refresh | Both keys change | Baseline, then target (test 1224) |
| Projection failure | Clock tick 321-337; extend 534-556; post-frame callback in `_changesOnNow` 906-916 | Preview and baseline cleared; unknown |
| Disposal | `_disposed` checks (153, 190, 214, 264, 404); Studio `mounted` (491) | Late results ignored |
| Save-as-new | SV 3136-3151 → draft 320-330 | Candidate retired; restaged with a new anchor and `stableChannelSeed(newId)` |
| After save | SV 3039-3040 | Committed; the new expected base reloads the baseline |

The full extraction removes the handshake only if all of these hold:

- Studio owns the controller.
- A single Studio input transition stages identity and updates verification,
  called from `_changed`, reload, save-as-new, save, and `didUpdateWidget`
  (inventory and generation arrive by rebuild via `lineup_app.dart:114`).
- Identity commits in a listener on revision-bound results.
- Projection failures become a synchronous, revision-bound call.

### Setup review (`lib/app/channel_setup_view.dart`)

Fields:

- `_step` (44), `_mode` (58), `_removalConfirmed` (68), `_phase` (69)
- `_filter` and `_search` (70-71), presentation only
- `_plan` (86), `_reviewStrategyBySource` (87), `_reviewBase` (88),
  `_removeSourceIds` (89), `_appliedEntries` (91)
- `_notice` (92), used as a string sentinel `'Updating review…'` at 2523,
  2540, 2749-2753, 2760
- `_firstSetup` (95)

Methods:

- `_allocateReview` (162-173) clears removal choices and the strategy map.
- `_prepareReview` (2479-2490).
- A mode change during review (2745-2754) re-allocates.
- `_applyReview` (3249-3285).
- `_reviewEntries` (3475-3511).

Repeated derivation:

- `composeChannelPlan` runs twice per review build (2493 → 3476, and 2495).
- `_counts` makes four passes (3513).
- `_applyReview` composes again (3253).
- `_missingSources` (2582) runs on every build.

### Widget decomposition map

| State class | Size | Sections and the fields they need |
| --- | --- | --- |
| `ChannelStudioViewState` | 112-3247 | **Title/actions** 565-843 (conflict, base deleted, busy, dirty, air check, pending choice). **Recovery** 845-938. **Station** 2532-2766. **Playlist editor** 1049. **Filter editor** 1111-1423 + **picker** 1428-1665 (`_activeFilterKey`, `_activeFilter*`, `_pendingFilterValues`, `_pickerForBrowse`, `_filterControlFocus`, `_expandedFilterSummaries`). **Manual editor** 1675-2017 (search, manual library/type/filters, browse, rundown, `_settledCountLabel`). Real god-State: the picker is shared through `_pickerForBrowse` (1435, 1455); pending choices gate actions (2977, 780-786); `_selectSource` resets picker and browse (321-333); `_saving` is read everywhere. |
| `_ChannelAirCheckState` | 52-920 | Header 559, facts 632, selection detail 744, schedule list 637. Selection state is shared between list and detail. |
| `_SetupState` | 43-3621 | Library step 402-964; configure step 965-2478 (sources 1252-1631, playback 1632-2136, rules 2137-2331, order 2332-2478); review 2492-3247; result 3287-3473. Mostly long helpers sharing `_mode`, `_notice`, `_error`, `_step`, `_phase`. |

### Protecting tests

- **`channel_studio_view_test.dart`:**
  - Rundown and draft: 1134, 1444, 1505, 650, 2636, 2665, 2838, 2958, 3002,
    3244, 3379, 3482, 3821, 4707.
  - Air Check and identity: 1373, 2776, 3579, 3632, 3690, 3759, 4221, 4251,
    4316, 4369, 4413.
- **`channel_studio_draft_test.dart`:** 28, 58, 87.
- **`channel_air_check_test.dart`:** 19, 58, 103, 297, 329, 354, 752, 784, 882,
  940, 1026, 1097, 1133, 1190, 1224.
- **`desktop_setup_test.dart`:** 315, 363, 376, 1029, 1067, 1095, 1509, 1532,
  1562, 1617, 1649.
- **`channel_setup_projection_test.dart`:** 73, 93, 158, 201, 253.

---

## T4. Native display restoration (CQ-08) and the native protocol

### Live `DisplayMatchingEngine::Release` (`display_dynamic_range.cpp:423-455`)

| # | Condition (in order) | Outcome | Side effect |
| --- | --- | --- | --- |
| L0 | `!owned` | No-op | — |
| L1 | Observed unknown | Target unknown | Report failed/`target_lost`; keep ownership and guardian |
| L2 | `unobserved_attempt && observed==original && attempted!=original` | Unresolved | Report failed/`restore_failed`; keep |
| L3 | `observed!=original && !IsOurState` | External change | `Disarm()` with result ignored; `owned=false`; no report |
| L4 | Pending restart maps to the same target | Keep for restart | — |
| L5 | `observed!=original` (our state) | Restore original | `Write(restoration)` (journal `attempted=original`, guardian `Update` failure tolerated, fenced by `Execute`, polls up to 3 s; unverified → keep and report) |
| L6 | Any pending restart | Keep | — |
| L7 | `Disarm()` fails | Keep | `guardian_lost=true`; report `restore_failed` |
| L8 | Otherwise | Released | `owned=false` |

### Recovery `RestoreDisplayOwnership` (`display_recovery.cpp:246-259`)

The input is the durable `DisplayOwnership`, from the journal via `Recover`
(:380) or from `GuardianSession::ParentLost` (`display_guardian.cpp:326`).

| # | Condition | Returns | Side effect |
| --- | --- | --- | --- |
| R1 | Observed unknown | false | Journal kept; guardian `EXIT_FAILURE` |
| R2 | `observed==original && attempted∉{unknown,original} && verified!=attempted` | false | — |
| R3 | `observed==original` | true | Entry removed |
| R4 | `observed∉{verified,attempted}` | true | No write |
| R5 | Otherwise | Query==original | `Set(original)` (return ignored); one re-query; journal `attempted` not updated |

Duplicated rows: R1≡L1, R3≡L5's no-write path, R4≡L3, R5≡L5's decision.

`Reconcile` (:373-379) applies a third rule. An owned record observing the
original with no outstanding attempt **suspends**, treating it as an external
change.

Cases where the durable flag is true and the live flag is false:

1. `Execute` refused (gate timeout or missing entry, :306-318) after
   `attempted` was journaled.
2. `WindowsGuardianLink::Update` writes the journal, then the pipe send fails;
   `Write` rolls `attempted` back in memory (:290) but not in the journal.
3. `Reconcile` clears the flag and sets `verified` in memory (:380-385), then
   the guardian `Update` fails.

Separate preservation note: restoration sets `attempted=original`, so the
unresolved predicate does not apply even if live `unobserved_attempt` remains
true after an unverified restoration. This is not a fourth durable-true/live-
false divergence. Recovery never journals its own restoration attempt.

### Record (`display_dynamic_range.h:116-129`)

| Field | Written by |
| --- | --- |
| `ownership.{target,route,original}` | `Start` |
| `attempted` | `Write` (rolled back on matching `Update` failure) |
| `verified` | `Write` verified; `Reconcile` late observation |
| `observed` | `Start`, `WriteAndObserve`, `Reconcile`, `Release` |
| `guardian` | `Reconcile` arm; `Write` teardown; `Suspend`; `Release` |
| `owned` | `WriteAndObserve` true; `Suspend`/`Release` false |
| `guardian_lost` | `Start` false; `Write` ×4, `Reconcile` ×3, `Release` (`Disarm` fail) true |
| `unobserved_attempt` | `Start` false; `WriteAndObserve` true; `Write` verified / `Reconcile` false |
| `write_revision` | Report only |
| `failure` | `Process`/`Start`/`Poll` reset; `Write` set |

Repeated bookkeeping:

- Guardian-lost teardown 3× in `Write` (:277-282, :289-296, :311-317).
- Relinquish 3× (:264-266, :438-440, :453-454).
- Observe-attempt 2× (:319-322, :380-385).

### String states and wire

- `session_` and `session_reason_` are `const char*`, compared with
  `std::string("active")` (:213, :484, :486).
- The report strings go to Dart (`native_player.cpp:1359-1373`).
- The journal and guardian pipe are binary `uint32`, with **implicit enum
  ordinals** `DisplayState{unknown,sdr,hdr}` and
  `DisplayRoute{none,hdr_state,advanced_color}` (`display_dynamic_range.h:20-21`),
  checked against the literals 1/2 (`display_recovery.cpp:76,94`;
  `display_guardian.cpp:28-35`).

### CTest wiring (`windows/runner/CMakeLists.txt`)

| CTest | Sources |
| --- | --- |
| `track_list_encoder` | Encoder + test |
| `authenticated_reference` | Test, `native_player`, encoder, `display_*`; via a cmake script and Python |
| `native_playback_state` | Test only |
| `native_player_contract` | Test, `native_player`, encoder, `display_*` |
| `runner_lifecycle` | Test, `flutter_window`, `native_player`, encoder, `win32_window`, utils, registrant, `display_*` |
| `display_dynamic_range` | `display_recovery`, `display_dynamic_range`, test |
| `display_guardian` | `display_guardian`, `display_recovery`, `display_dynamic_range`, guardian test, **`display_admission_process_test`** (no separate target; dispatched at `display_guardian_test.cpp:331-341`) |

Covered:

- Live:
  - Restore: :100-127, :156-160.
  - Failed restore kept armed: :269-279.
  - Restart retention: :244-296.
  - Target unknown at release: :306 (outcome after recovery only).
  - Unresolved (L2): :198, implicit only.
  - Restore after guardian loss: :500-509.
  - `release_external` (:235-241) actually exercises "already original",
    not L3.
- Recovery:
  - `RestoreCases` :46-79, `UnverifiedOriginalRemainsUnresolved` :80-91.
  - `NoActionCases` :92-111 (counts only).
  - Process tests :579-595, :759-762.

**Not covered:**

- Live L3.
- Live L7.
- An explicit L2 assertion.
- Divergence cases 1-3 (the fake `Execute` always runs the action, :51).
- Recovery with `verified==original` and an unverified opposite attempt.
- Recovery with `attempted==original, verified=hdr`.
- R1/R3 return values.

### Native hygiene

- `Handle` RAII is duplicated (`display_recovery.cpp:34`,
  `display_guardian.cpp:12`).
- `Known`/`KnownState` duplicate each other.
- `native_player.cpp`:
  - `command_queue_full` repeated 6× (:504-586).
  - The inline `Find` + `get_if` pattern about 8×.
  - `FindNode` (:163) duplicates `FindTrackNode`.
  - ASCII lowercasing 3× (:89, :238, :1414).
  - Queued events re-parse `"type"` (:407, :1252).
- The `MpvOperations` seam covers 7 calls. Bypassing it: `mpv_set_option`
  (:633), `mpv_request_log_messages`, `mpv_observe_property`,
  `mpv_command_node` (:960), `mpv_set_property_string` (:1006),
  `mpv_wait_event`.
- `loadId` must be ≥0 for `load` but >0 for `selectTrack`.
- Dart: `as String?` casts at `windows_native_player.dart:458, 482`;
  `MissingPluginException` is not mapped.

### `lineup/native_player` protocol inventory

Dart → native. Every method except `initialize`/`dispose` returns
`not_initialized` while the player is not accepting commands.

| Method | Arguments | Result / errors |
| --- | --- | --- |
| `initialize` | — | `{clientApiVersion:int}`; `required_engine_unavailable`, `initialize_failed`. Resets the display revision; purges queued display events |
| `dispose` | — | null after the worker finishes; `dispose_in_progress`; idempotent |
| `setDisplayMatching` | `revision:int≥0` (strictly increasing), `session:bool`, `desired:'hdr'\|'sdr'\|'unknown'` | `invalid_argument` |
| `load` | `uri:String` (1-32768 bytes), `loadId:int≥0`, `plexToken:String?` (0x21-0x7E, ≤8 KiB), `startPaused:bool?` | `invalid_argument`, `insecure_media_uri`, `command_queue_full` |
| `play` / `pause` | — | `command_queue_full` |
| `seek` | `seconds:num` (finite, ≥0) | `invalid_argument`, `command_queue_full` |
| `stop` | `stopId:int>0` | `invalid_argument`, `command_queue_full`; completion via `stopResult` |
| `setVideoRect` | `left`, `top`, `width≥0`, `height≥0` (finite), `scale>0` | `invalid_argument` |
| `setFullscreen` | `fullscreen:bool` | `invalid_argument`, `window_error` |
| `selectTrack` | `type:'video'\|'audio'\|'subtitle'`, `id:int>0\|null`, `loadId:int>0`, `requestId:int>0` | `invalid_argument`, `command_queue_full`; completion via `trackResult` |
| `setVolume` | `volume:num` 0-100 | `invalid_argument`, `command_queue_full` |

Native → Dart, via `invokeMethod("event", map)`. Events from an older player
generation are dropped. The queue holds 256 events. When full, the oldest
queued `property` is evicted if present, regardless of incoming type. Only if
there is no queued property is an incoming `property` dropped, or an incoming
non-property admitted by evicting the oldest event of any type.
Verified against `native_player.cpp:1254-1267`. `setVideoRect` also returns
`invalid_argument` when the host window is missing or `SetWindowPos` fails
(770-777).

| `type` | Keys |
| --- | --- |
| `state` | `state` ∈ idle/loading/playing/ended/stopped/error; `message`; `loadId?` (absent on the ready idle); errors add `failureCode` and `httpStatus?` |
| `property` | `name`, `value` (null when unavailable), `loadId?` |
| `stopResult` | `stopId`, `success` |
| `trackResult` | `loadId`, `requestId`, `success` |
| `display` | `revision`; `session` (inactive/active/suspended/unavailable); `observed` (hdr/sdr/unknown); `outcome` (idle/pending/matched/failed); `wrote`; `owned`; `reason` (null or unsupported_api, not_hdr_capable, ambiguous_target, state_unknown, guardian_unavailable, set_rejected, not_observed, external_change, restore_failed, target_lost); `route` (hdr_state/advanced_color/none); `activeColorMode` (sdr/wcg/hdr/unknown) |

Forwarded mpv properties:

- `pause` (bool); `time-pos` and `duration` (double).
- `track-list`, up to 256 tracks. Each has `id` (int>0), `type`
  (video/audio/**sub**), and `selected`. Optional: `title`, `lang`, `codec`,
  `demux-channels`, `demux-channel-count` (int), and `forced`, `external`,
  `hearing-impaired`, `visual-impaired`, `commentary` (bool).
- `video-format`, `video-codec`, `current-vo`, `hwdec-current`: strings of at
  most 4096 bytes.
- `video-params`: `w`, `h`, `pixelformat`, `hw-pixelformat`, `primaries`,
  `gamma`, `colormatrix`, `sig-peak`.
- `video-target-params`: `gamma`, `primaries`, `pixelformat`, lowercased to
  `[a-z0-9._-]` (≤64 bytes) or null.

Playback `failureCode` values:

- `http_error` (+ `httpStatus` 4xx/5xx), `network_error`
- `audio_decode_error`, `video_decode_error`
- `audio_output_error`, `video_output_error`
- `source_open_error`, `container_error`
- `correlation_error`, `command_error`
- `event_queue_overflow`, `mpv_error`

Codes Dart synthesizes: `native_command_error`, `native_error`,
`load_timeout`, `stop_timeout`, `stop_failed`, `wait_timeout`,
`native_playback_error`.

Windows-specific parts:

- The DirectComposition engine marker.
- The `wid` child window.
- Display `route` and `activeColorMode`.
- Fullscreen implemented by changing the window style.

---

## T5. macOS readiness and repository hygiene

### Dart Windows coupling

| Item | Anchor | Classification |
| --- | --- | --- |
| Player selection | `main.dart:55-57`; `unsupported_native_player.dart:6,10,42` | Change: platform factory (plan M) |
| Interface doc comment states Windows libmpv behavior | `native_player.dart:35-37` | Change: platform-neutral token-safety contract (M) |
| `DisplayMatchingRoute`, `wcg`, `guardianUnavailable` | `native_player.dart:80,88,90,256-260` | Windows concepts in the interface; only diagnostics read them; macOS can report `unavailable`; not blocking |
| HDR setting copy "Switch Windows HDR…" | `lineup_shell.dart:1329-1342`; `desktop_settings_test.dart:134` | UI copy decision (§9) |
| Diagnostics "Windows display" row | `diagnostics.dart:153,156,200`; `diagnostics_view.dart:443-444,472` | UI copy decision (§9) |
| Diagnostics allowlists | `diagnostics.dart:492-493` | Revisit only for a non-mpv backend |
| Ctrl-only navigation | `navigation_shortcuts.dart:4`; Guide search accepts Meta (`guide_view.dart:528-529`) | Interaction decision (§9) |
| Fullscreen | `player_view.dart:375`; PC 1400-1418; macOS menu `toggleFullScreen:` (`MainMenu.xib:295`) bypasses Dart | Protocol decision (§9) |
| Unsupported Player state | `player_view.dart:232-254, 611-640, 3420-3453` | Fine as a fallback |
| Media path parsing, browser launch, credentials | `lineup_shell.dart:881-890`; `plex_link_launcher.dart:5-12`; `app_store.dart:161-165, 326-358` | Fine; sandbox behavior unverified |

### Presentation contract for any platform

`NativeVideoSurface` paints nothing. After every frame it reports the global
rect, after transforms, with device pixel ratio as `scale`. It skips
duplicates, re-reports on metrics changes, sends a zero rect on dispose, and
retries on failure. The shell makes Player routes transparent
(`lineup_shell.dart:805, 815-821`).

Obligations for a macOS implementation:

1. **Alpha compositing.** Real compositing over the video layer, matching the
   exact Guide alpha.
2. **Coordinates.** The rect is in logical units with a top-left origin.
   Windows multiplies by `scale`. AppKit uses points and a bottom-left origin
   unless the view is flipped.
3. **Rect lifetime.** Keep the rect across load and stop. Hide on a zero rect
   or when minimized.
4. **Passive video.** The video takes no hit-testing, focus, or accessibility.
5. **Fullscreen completion.** `setFullscreen` completes after the transition.

### Test doubles

| Group | Plain duplicates | Keep local | Removable |
| --- | --- | --- | --- |
| AppStore | `guide_view_test:3992`, `guide_controller_test:2287`, `player_coordinator_test:7139`, `player_view_test:6494`, `lineup_app_test:2087`, `cast_portrait_test:193` | `_RetryStore`/`_FailingStore` (re-base); `lineup_controller_test:8670`, `_ConcurrentStore:8892` | ~60 |
| CredentialStore | 6 always-null; 3 constant-token (`cast_portrait:207`, `lineup_restore_view:584`, `desktop_onboarding:1406`); 2 map stores (`product_spine:527`, `lineup_controller:8699`) | `_AmbiguousWriteCredentials` (`lineup_controller_test:8727`) | ~130 |
| NativePlayer | `lineup_app_test:2112`, `native_video_surface_test:113`, `player_coordinator_test:6518` (base), `product_spine:426`; base on `FixturePlayer` (`ui_fixture:103`) | `player_view_test:6331`; `display_matching_test:494` (`noSuchMethod`); 26 coordinator scenario subclasses | ~270 |
| PlexClient | Constructor boilerplate only | All overrides | ~0-20 |

Risk: client ids differ between stores (`'test'` vs `'lineup-desktop-test-…'`).

### Tooling

- `pubspec.yaml:7` constrains only `sdk: ^3.13.0`.
- `Assert-PinnedFlutterCheckout` (`tool/windows/build-inputs.ps1:125-141`)
  runs only for `run.ps1` and `build-release.ps1`.
- Flutter 3.47.6 and 3.47.7 both ship Dart 3.13.5.
- CI on macOS (`ci.yml:37-54`) runs only the Guide alpha test and
  `flutter build macos`.
- macOS Runner:
  - Bundle id `com.tjzine.lineupDesktop`.
  - Minimum OS 12.0.
  - Release entitlements: sandbox + network client.
  - `MainFlutterWindow.swift` is the template default.
  - No signing or hardened-runtime setup.
- Version sources: `X-Plex-Version '0.1.0'` (`plex_client.dart:57`),
  `pubspec.yaml:4`, and `LINEUP_VERSION` (`diagnostics_view.dart:79-86`,
  `build-inputs.ps1:330`).

### Documentation classification (about 21.9k lines, 50 Markdown files)

| Class | Documents |
| --- | --- |
| Current authority | `README`, `DEVELOPMENT`, `architecture`, `user-guide`, `windows-runtime`, `windows-native-validation`, `desktop-ui-design-spec`, `desktop-ui-surface-approvals`, `desktop-ui-second-pass`, `fullscreen-hdr-spec` |
| Active, with open obligations | `plex-transcoding-implementation-plan`, `schedule-continuation-plan`, `osd-autohide-and-collection-membership-plan`, `fullscreen-hdr-implementation-plan`, `audio-subtitle-track-label-implementation-plan`, `guide-freshness-collection-investigation`, `libmpv-authenticated-reference-investigation`, `ux-functionality-audit`, `feature-validation-findings` |
| Completed or historical | `desktop-ui-implementation-plan`, `desktop-ui-execution`, `desktop-ui-readiness-review`, `desktop-ui-scaling-progress`, `ui-parity`, `fullscreen-hdr-discovery-plan`, `windows-collaborative-acceptance-handoff`, `opus-feature-research-request`, `feature-opportunity-report`, `code-quality-refactor-planning-handoff` (after the plan completes), most of `docs/reviews/*` |
| Stale status headings | `setup-reentry-startup-plan:3`, `player-guide-polish-plan:3` (landed per `reviews/comprehensive-review-2026-10-07/REPORT.md:37`) |
| References to absent files | `README.md:17,20,88-92,96-98`; `REMEDIATION.md:137` (10-07) |

Most misleading for macOS work:

- `.agents/project.md:73-76` and its Windows-only verification table at
  146-166.
- `architecture.md:38-41`.
- `README.md:180-184`.
- `DEVELOPMENT.md:339-350`.
- `user-guide.md:3`.
- `product-parity.md`, labeled "authoritative current" although it is the
  2026-08-23 audit.

---

## T6. Plex client, domain, and persistence (gap sweep)

The gap sweep did not reproduce additional defects; its new failure candidates
remain suspected. CQ-09's actual parser reproduction is separately recorded in
the assessment handoff. Line numbers below refer to `lib/`.

### Suspected defects

| ID | Location | Problem | Confirming test |
| --- | --- | --- | --- |
| NF-15 | `plex_client.dart:1367-1384` | `TlsException` and `HandshakeException` are not mapped; the http 1.6 `IOClient` wraps only `SocketException` and `HttpException` | A `MockClient` that throws `HandshakeException`; expect `network-unavailable` |
| NF-16 | `app_store.dart:233-239` | `catch (_) {}` regenerates the client identifier on any read error | A valid ID file made unreadable (`chmod 000`); expect an error and the file unchanged |
| NF-17 | `plex_client.dart:1981-1997` | `_findTokenInXml` accepts an empty `authToken` | XML with an empty token followed by `"t"`; expect `'t'` |
| NF-17 | `plex_client.dart:74` | `DateTime.parse` on the PIN expiry | `expiresAt: 'x'`; expect a typed `parse-error` |

### Recommended changes

- **Pagers (NF-18).** Four pagers repeat the same logic:
  - `libraryItems` 398-461
  - `_libraryMetadata` 769-851
  - `_playlistCatalogRaws` 986-1064
  - `_playlistItemRaws` 1075-1142

  Three hard-code `page < 1000`; `maximumLibraryMetadataPages` is also **1000**
  (not 50). Preserve endpoint limits, oversized-complete envelope options, and
  limit exception subtypes during consolidation. Cancellation joins repeat at
  565, 779, 875, and 1302. The `'cancelled'` literal appears at 400, 413,
  443, 862, 897, and 1374, although `_scanCancelledException` (1445)
  exists. Protected by `plex_transport_test.dart` and the bad-page matrix in
  `plex_library_scan_test.dart` (400-430).
- **Authorization codes and the item copy (NF-19).** The authorization
  codes are listed at 276, 626, and 913, and at LC 2658.
  `_annotateLibraryItem` (1492-1541) and `_immutable`
  (`plex_models.dart:271-305`) each copy 33 fields by hand.
- **Diagnostics events (NF-20).** `diagnostics.dart:331-349` holds 17
  `(area, message)` pairs used by about 30 producer calls. Context policy has two
  distinct operations: ingest retains safe token spelling and substitutes
  `unexpected` for unsafe strings (86-99); export normalizes recognized
  categories and omits unknowns (303-328). Share definitions, not one identical
  validation result. The UI reads stored values, and forged snapshots still
  require export filtering. Protected by `diagnostics_test.dart` (329 and the
  ingest/export boundary cases).
- **Schedule worker (NF-21).** `schedule_worker.dart:111-130, 174-199`:
  positional lists with casts. A cast that fails after `_pending.remove`
  leaves `build()` hanging. The worker's `catch (_)` loses the error's
  message and stack. Protected by 9 tests in `schedule_worker_test.dart`.
- **Duplicated rules (NF-22).**
  - The series rule appears twice: `scheduler.dart:166-170` and 475-479.
  - `channel_builder.dart:100, 188, 224, 261-302, 690` passes filter names
    as strings and duplicates the facet mapping in
    `library_facets.dart:18-29`.

### PlexClient verdict

Neither an interface nor a file split. There is one production consumer
(`LineupController`). The fakes subclass `PlexClient` and use the inherited
"unexpected HTTP" tripwire. The transport is already cohesive and the
decoders are already top-level functions. Revisit a split only if the file
remains hard to navigate after NF-18.

### Checked and sound

- `_send` and `_readBounded`: the timeout, size limits, no redirects,
  draining late responses
- Artwork pinned to the server; redaction
- `selectConnection`
- `_CollectionRequestPool`
- The home-users fallback
- `channel.dart` decoding: casts sit inside `try` and become
  `FormatException`
- The worker lifecycle
- The `FileAppStore` queue and quarantine
- Diagnostics redaction
- `PlexClient.close` on dispose

---

## T7. UI views (gap sweep)

| ID | Location | Problem | Protecting tests |
| --- | --- | --- | --- |
| NF-23 | `player_view.dart:1434-1441, 3579-3602` vs `guide_view.dart:2967-2986`; values come from `DynamicRange.name` | Now Playing upper-cases values it doesn't recognise, so `unknown` shows as an "UNKNOWN" badge (suspected). The Guide drops `sdr`/`unknown`. Channel label "3ch" vs "3 CH" | `player_view_test` 5198, 5836; `guide_view_test` 487, 1880 |
| NF-24 | `lineup_shell.dart:42-43, 167-192, 256-263, 743-747, 794-822`; `navigation_shortcuts.dart:3-12` | Route ints, Ctrl-only shortcuts | `desktop_navigation_test` 34, 378; `lineup_app_test` 507, 572 |
| NF-24 | `lineup_shell.dart:63-66` (written together at 128-130, 203-205, 270-277, 303-307) | Three correlated app-menu fields | Same as above |
| NF-24 | `lineup_shell.dart:939-944`; each key written 3× (e.g. 1180, 1183, 1188) | Settings use string keys across five collections | `theme_shell_test` 299; `ui_review_regression_test` 675; `desktop_settings_test` 119 |
| NF-25 | `lineup_focus.dart:20-62`; `player_view.dart:48, 59, 164-181, 450`; `lineup_shell.dart:64, 75, 393-402` | Three modality handlers with different reset rules | `player_view_test` 844, 1601, 3057; PCT 3419 |
| NF-26 | `player_view.dart:183-412` | Repeated key lists (213-219, 241-245, 386-404); about 18 `closeSleepPicker` calls | `player_view_test` 920, 1237, 1416, 1601, 1693, 2000 |
| NF-26 | `player_view.dart:425`; `guide_controller.dart:305-312` equal to `player_view.dart:3541-3548` | `LayerLink` recreated each build; poster path duplicated | `player_view_test` 671 |
| NF-27 | Shell 705-715 vs `_MiniGuideRow` 2462-2471; `displayHoldActive ? loading : state` at 797, 810, 953-955, 1228-1230, 1247-1249; status `Text` repeated at 1223-1232 and 1242-1251 | The watching and presented-state rules are written in several places | `guide_view_test` 1048; `player_view_test` 2000 |
| NF-28 | `channels_view.dart:44-71, 1155-1256`; started from `itemBuilder` (441); reset and pruned in `build` (251, 271-278) | The State owns a health job queue | `channel_studio_view_test` 4079-4217; `channels_view_test` |
| NF-29 | `guide_controller.dart:797, 817, 822` | Changed rows publish in try/catch and again after bookkeeping. Stale completion still changes observable active load/queue state and can require one publication; do not discard it categorically | `guide_controller_test` 16, 55, 101; add stale-final-load/activity coverage |
| NF-29 | `guide_controller.dart:222-256`, called from `build` (`player_view.dart:2473`, `guide_view.dart:946`) | `currentProgram`/`nextProgram` call `_failProjection` without notifying | Same as above |
| NF-29 | `guide_controller.dart:144-149` | Correlated selection pairs | `guide_controller_test` 353 |
| NF-29 | `guide_view.dart:644-663` | Viewport scheduled on every layout | `guide_view_test` |
| NF-30 | `onboarding_view.dart:49-52, 919-928, 952`; PIN expiry at 322 and 385-388 vs LC 625 | `_serverError` has two meanings; expiry rule duplicated and uses `DateTime.now()` | `desktop_onboarding_test` 779, 830, 869; `lineup_app_test` 938 |
| NF-05 | `lineup_app.dart:190-194` | The engine failure is recognised through two types | `lineup_app_test` |

**Not worth doing:**

- measuring text per rebuild;
- reworking the guide inspection triple;
- a sealed type for the ChannelsView mode;
- adding `didUpdateWidget` to PlayerView, GuideView, or ChannelsView (their
  controllers are `late final`);
- extracting the artwork cache;
- navigation-only file splits.

**Checked and sound:**

- disposal across all States;
- the async currentness guards (ChannelsView, onboarding, Guide, the shell's
  logout);
- the `lib/ui` primitives;
- `lineup_app` settings filtering.
