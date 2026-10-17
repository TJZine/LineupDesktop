# Windows and live acceptance handoff

This is a **self-contained prompt for a separately invoked Windows session**. It was not executed during the general review. It authorizes nothing until the user invokes that session and resolves its target/setup. Do not implement the remediation plan as part of observation work.

## Task and inherited conclusions

Continue the completed general production review of Lineup Desktop from:

docs/reviews/comprehensive-review-2026-10-10/REPORT.md  
docs/reviews/comprehensive-review-2026-10-10/REMEDIATION.md  
docs/reviews/comprehensive-review-2026-10-10/EVIDENCE.md

Original absolute location: /Users/tristan/Software/LineupDesktop/docs/reviews/comprehensive-review-2026-10-10.

General source: 4fb7758034f4f47290fae13a4ea8275860ba1284, branch codex/desktop-ui-second-pass. Resolve the human-requested Windows candidate, full SHA and any included changes; do not assume this historical SHA is the requested new checkout. Revalidate only affected conclusions when code differs. Preserve unrelated work. Do not switch/reset/stash/commit the user's checkout to make packaging clean; use a separately authorized clean candidate location and retain the review artifacts outside it if needed.

Read AGENTS.md, .agents/project.md and current docs/windows-native-validation.md, docs/windows-runtime.md, docs/windows-collaborative-acceptance-handoff.md, docs/DEVELOPMENT.md. The current candidate's source/contracts govern. Do not repeat the whole general review, run Docker, change security options, publish a package or implement fixes.

Carry forward:

- F-001 protected-profile PIN recovery, F-002 Guide focused-control activation, F-003 search edit replacement, F-004 worker startup disposal, F-005 oversized duration projection, F-006 reference harness terminal mismatch and F-007 multipart seek are confirmed at their stated portable/static tiers.
- F-008 build-ancestor containment is LIKELY/S3 with Windows and policy gates.
- CAND-009 precommit EOF is a normal-Windows-ordering HYPOTHESIS despite synthetic sequence reproduction.
- Existing F15 buffering projection and H1 live Plex response shape remain evidence work.
- Portable baseline: formatter/analyzer pass and 1,364 tests pass, including macOS Guide alpha, pinned Flutter/Dart and New York timezone. Do not count them twice or call them physical Windows proof.
- No native CTests, actual Windows filesystem/credential behavior, current GPU/display/input or exact-package acceptance were executed.
- macOS media playback is intentionally unsupported. Server transcoding and automatic fullscreen HDR switching are planned; do not treat them as newly failing implemented features.

## Source/runtime identity and prerequisites

Retain INPUT_IDENTITY.json and FINAL_IDENTITY.json with the review. Record candidate full SHA, dirty status and relevant file hashes; runtime/prepared/copied DLL hashes; package archive hash; build marker; engine revision/patch/output identity; Windows edition/build; CPU/GPU/driver; monitor models/resolutions/scales/HDR state; audio endpoint; input device; timezone; selected Plex route class. Sanitize hardware/account identifiers and never retain tokens, headers, private media titles/paths, full private URLs or raw diagnostics.

Reviewed pins (verify against candidate metadata, never silently substitute):

| Input | Identity |
|---|---|
| Flutter | 3.47.6, framework 5fc346839b5d0eef006ed8404392afb4dfae428d |
| Dart | 3.13.5 at general review |
| Engine | 692136cb6582dbfc5af3fb33c2515a069f2f66d0 |
| Engine patch SHA-256 | A9D057E127F32E5A82B635F8B53ACFB00C8827D47AA205FDA086A75411E6522F |
| Patched manager SHA-256, LF normalized | 3D3AE9116C0F662D55EE323AE1723EEB35123920E8380379207D29EB485B5C7E |
| depot_tools | 13febbee9ece9e03df923f69d540afc63c6db93e |
| libmpv source | 3186d369f9f090cd1363be0ac46a037824b702c6, v0.41.0-1092-g3186d369f |
| Asset | mpv-dev-lgpl-x86_64-20261002-git-3186d369f9.7z |
| Asset SHA-256 | 322CB0040B97B15F97069F631F665FD63DA331CED92705F757DA13B99380DA5F |
| libmpv DLL SHA-256 | 4BA364226FD2EA5DD2C6F2333F0118462DA549FEED92360FB766A3924E313A51 |
| mpv client header SHA-256 | 1ACF99EE77C8C2A6F1D1993BD81BBC8A91D27FB5924E80171670E6139A4BD353 |
| FFmpeg / libplacebo | N-127094-gf68e1afc1 / 7.374.0 |

Require Windows x64, PowerShell >=7.4, Git, Visual Studio 2022 C++ desktop toolchain and Windows SDK, CMake/Ninja, pinned Flutter/local engine, 7-Zip/runtime preparation prerequisites. For authenticated-reference CTest: Python 3, FFmpeg with libx264 encoder and DASH muxer, OpenSSL on PATH (Git's bundled OpenSSL is recognized), new/empty operation-owned runtime destination. No Python packages or system trust-store change is needed. The test CA/null presentation overrides remain test-local.

Physical campaign needs non-sensitive authorized SDR/HDR/codec/subtitle/multipart samples, supported display/audio/input and explicit live-account authorization. Missing account/hardware means Blocked/not run, not failure. Do not change drivers/display HDR/timezone/account configuration automatically; propose the bounded change and obtain authorization where necessary. Windows TZ alone does not change Dart's Windows timezone. Record actual timezone; only change OS timezone with explicit permission and restoration instructions.

Already source-reviewed: all seven playback owners, adapter/coordinator/view; native player/header/encoder/harness/CMake/manifest; Dart/native codec and event vocabulary; engine DirectComposition patch/notice/apply; PowerShell provisioning/run/release/package/shared policy; runtime/license pins; CI; macOS unsupported branch. Execution is the remaining responsibility.

## Command surface

Use actual selected machine paths below; these are placeholders, not a command to create/check out a candidate automatically. Run commands sequentially with checked exit codes and stable source identity.

~~~powershell
$Repo = 'C:\src\LineupDesktop'
$TargetCommit = '<human-selected-full-40-character-sha>'
$FlutterRoot = 'C:\src\flutter'
$EngineSource = Join-Path $FlutterRoot 'engine\src'
$MpvRoot = 'C:\local\lineup-mpv-review' # New or empty operation-owned directory.
$SdrSample = 'C:\test-media\synthetic-sdr.mp4'
Set-Location $Repo
git status --porcelain
git rev-parse HEAD
flutter --version
flutter doctor -v
pwsh -File .\tool\windows\verify-release-policy.ps1
~~~

Match resolved flutter executable and framework/engine metadata. Follow DEVELOPMENT's exact provisioning (pinned depot_tools, standard.gclient, repository apply.ps1, host_debug/host_release), if explicitly authorized and not already current. Do not replace stock SDK cache outputs. Relevant commands after prerequisites:

~~~powershell
& .\tool\windows\prepare-mpv.ps1 -Destination $MpvRoot
$env:LINEUP_MPV_ROOT = $MpvRoot
& .\tool\windows\run.ps1 -EngineSource $EngineSource -MpvRoot $MpvRoot -MediaPath $SdrSample
~~~

For configured Windows CMake output:

~~~powershell
cmake --build .\build\windows\x64 --config Release --target track_list_encoder_test
ctest --test-dir .\build\windows\x64 -C Release -R '^track_list_encoder$' --output-on-failure --timeout 30
cmake --build .\build\windows\x64 --config Release --target authenticated_reference_test
ctest --test-dir .\build\windows\x64 -C Release -R '^authenticated_reference$' --repeat until-fail:3 --verbose --timeout 180
~~~

Plex app launch uses run.ps1 without MediaPath. Direct documented local-engine equivalent:

~~~powershell
flutter run -d windows --local-engine=host_debug --local-engine-host=host_debug --local-engine-src-path=$EngineSource
~~~

Release/package, only with a clean exact candidate and valid prepared engine/runtime:

~~~powershell
& .\tool\windows\build-release.ps1 -EngineSource $EngineSource
& .\tool\windows\package.ps1 -Destination 'build/package/LineupDesktop-review-unique'
~~~

Use a genuinely unused destination. These commands do not publish. Stock Flutter compile is a separate tier and cannot establish patched-engine composition. Existing current portable results may be reused under DEVELOPMENT's currentness rules; rerun affected/Windows-specific tests when candidate/environment differs. When needed use resolved packages and --no-pub; never update lockfiles or goldens for this observation task.

## Session method and evidence

Execute one bounded human-observed step at a time. Explain the action, wait for the user's visible/audible result, record neutral facts, then choose the next step. Do not send a long physical checklist and infer completion from silence.

For every W-ID record candidate/runtime/package identities, prerequisites, exact action, expected versus actual, pass/fail/block status, sanitized evidence location, whether observation is headless/physical/live, cleanup and classification change. Use Pass / Fail—blocker / Fail—non-blocking / Blocked-not-run. A headless null-output pass says nothing about visible video, audible sound, HDR or composition.

### W-001 — Windows policy and preparation

Links: J12, F-008 context. Setup: selected exact candidate and PowerShell 7.4+. Action: run verify-release-policy.ps1; verify framework, engine patch and runtime preparation checks, including paths with spaces through existing fixtures. Record command/exit and safe failure ID, resolved tool versions and hashes. Expected: real policy checks run and reject their negative controls; any missing tool is a prerequisite gap. Cleanup: restore only session environment and remove operation-owned temporary preparation files when no longer needed. Outcome: closes E-006 execution gap at this identity; does not close package/physical gates.

### W-002 — Native CTests and authenticated reference containment

Links: F-006, C03/C07/C13, J07/J11. Setup: real configured Release targets, exact prepared/copied DLL, FFmpeg/OpenSSL/Python. Action: run both commands above; reference CTest three repeats, retaining positive MP4/MKV and all rejection/untrusted-CA/required-option controls. Original candidate is expected to time out after ended positive completion per F-006; observe rather than fix it. If a separately approved P-005 candidate is supplied, expect positives complete and negatives still reject. Record events using fixed states/load IDs, progress/rejection/timeout/exit, never credentials or full URLs. Cleanup: harness-owned HTTPS servers, processes, generated media/CA. Outcome: confirm/refute F-006 runtime manifestation; passing repaired harness establishes headless containment only. Do not weaken TLS/options or force Stop to make success.

### W-003 — Multipart, live join and scheduled continuation

Links: F-007, J07/J08. Setup: authorized synthetic two-part item, first known 60 s and second missing Plex duration but playable 90 s; full-metadata control; DVR on. Action: play into part two, note displayed 10/90 local timing, +30 s, backward and slider seeks; repeat complete map and seeks during readiness. Then natural part/program EOF, unknown duration, short/premature end, next-program boundary and lateness just below/above 30 s. Record active part ordinal, local/aggregate display/target, loaded identity versus wall-clock Guide, load count and visible/audible continuity. Expected current F-007: earlier part reload; corrected candidate: local seek remains active part, complete map cross-part behavior preserved. Cleanup: stop playback, restore DVR only if changed with consent. Outcome: physical F-007 acceptance and continuation results; never infer from simulated native player.

### W-004 — Precommit EOF ordering

Links: CAND-009, C01/C07, J07. Setup: exact native adapter/engine/runtime; non-sensitive very short/near-EOF media, controlled load/seek acknowledgement observation if available without product edits. Action: capture neutral ordering of command reply, playing readiness, ended event and committed load identity during initial tune and pending seek. Compare normal postcommit EOF. Expected discriminant: ended before commit with no successor and retained ended intent supports promotion; no such ordering across bounded trials leaves hypothesis unconfirmed, not disproven universally. Record relative sequence/IDs only. Cleanup: stop/drain and close fixture processes. Do not add permanent instrumentation or invent native ordering from a mock. Outcome: only promote if actual adapter/native ordering makes the susceptible sequence reachable; otherwise park.

### W-005 — Buffering versus explicit pause

Links: historical F15, J07/J08/J11. Setup: authorized controllable media/server route and non-sensitive stream; user permission for scoped network interruption. Action: observe normal playback, deliberate user Pause, then reproducible cache starvation without pressing Pause and recovery. Record elapsed time, visible status/spinner, pause state, neutral native property/event facts and audible/video behavior. Expected: distinguish user pause from starvation; current absence of cache producer may leave misleading status. Cleanup: restore network condition, resume/stop. Outcome: calibrate existing deferred gap and operational severity; do not create duplicate new finding or modify buffering behavior here.

### W-006 — Replacement, authorization, Stop, tracks and shutdown

Links: J04/J07/J11, C01/C03/C07. Setup: authorized local/Plex samples with distinct parts/tracks; exact runtime. Action one at a time: rapid tune/surf/number input; repeated seeks during load; recoverable PMS authorization refresh; Stop/sleep/logout/content change superseding pending load; audio/subtitle selection followed by observed selection; close app with pending work. Record generation/request IDs, accepted versus confirmed track state, safe failure code, cleanup completion and retained process/window count. Expected: no stale tune/track resurrection, no premature confirmation, no credential crossover; failed Stop keeps truthful retry/cleanup. Cleanup: stop fixture server and verify no retained app process. Outcome: physical lifecycle acceptance; isolate failures before any proposed fix. Preserve account privacy and avoid unauthorized account revocation.

### W-007 — Decode, audio, subtitles, SDR/HDR output

Links: J11. Setup: supported GPU/driver/display/audio endpoint and authorized representative codec/container/bit-depth/subtitle samples. Begin local SDR; stop broader Plex campaign if basic video/audio fails. Action: verify visible video, audible audio, pause/seek, hardware decode/output facts; representative audio/subtitle selection; HDR source on already agreed display/HDR state. Record source category rather than private name, telemetry separately from observed panel output, drop/stutter/color/subtitle symptoms and route. Expected: current direct playback requirements; telemetry alone is not physical HDR proof. Unsupported formats/transcoding and automatic OS HDR switching are not newly implemented promises. Cleanup: restore only explicitly changed settings and stop. Outcome: codec/hardware acceptance or bounded compatibility finding, not blanket media support.

### W-008 — Composition, Player/PiP, fullscreen, monitors and DPI

Links: J06/J11, C10. Setup: exact patched engine with marker, representative window/display scales and approved current layout. Action: Player↔Guide/PiP, resize/maximize, minimize/restore, fullscreen toggle, move between available mixed-DPI monitors; check overlay z-order, transparency, video aperture and clickable alignment after each bounded action. Record engine marker, client size/scale, monitor class, observed clipping/black regions/focus/hit alignment; sanitized captures where useful. Expected: native surface follows Flutter aperture without stale window placement or invisible controls. Cleanup: return original window/display state. Outcome: physical composition/input alignment acceptance; stock compile or macOS alpha cannot substitute. Changing OS display/HDR configuration needs explicit permission.

### W-009 — Keyboard, remote, accessibility and active editing

Links: F-002/F-003, J05/J06/J08, C08–C10. Setup: packaged/development identity, keyboard and supported remote, screen reader if available; known airing grid and loading row. Action: Tab to Guide menu/hours/row Retry then Enter/Space/Select; grid activation control; type a multiword query with a pause after space while schedules update. Separately check Studio editors/dirty exits, shell chords, Player Mini Guide/track/Now Playing/sleep/error overlays, focus restoration and text scaling/AT; IME only with an available authorized configuration. Record actual focus, expected action, unintended tune count, raw text/caret/composition, accessible label/action and escape route. Cleanup: dismiss overlays/restore settings. Outcome: F-002/F-003 physical confirmation or corrected acceptance. Do not claim IME failure from the portable raw-text probe.

### W-010 — Live Plex accounts, inventories, recovery and scale

Links: F-001/F-005 limits, H1, CAND-010/011, J01–J05. Setup: explicit account/data authorization, owned/shared/managed/protected profiles and direct/remote/relay routes actually available. Action: link/cancel/retry and protected PIN→saved unreachable server recovery; restore library/collection/playlist scopes; ordinary/smart/recreated membership; targeted retry and ready subset. For H1 record response shape/key/types/counts only, not raw body; for scale record counts/page/concurrency/time/memory and typed budget result. Test content refresh while Air Check remains mounted only if a real supported route reaches it; compare same-path artwork before/after. Expected: complete inventories or actionable failure preserve saved data; F-001 may retain PIN; unknown shape/latency/artwork becomes finding only on actual supported path. Cleanup: stop/logout only as authorized, retain user's data and restore any fixture route changes. Outcome: classify H1, CAND-010/011; no speculative OOM or parser incompatibility.

### W-011 — Windows persistence, credentials and relaunch

Links: J02/J04/J10, C02/C03. Setup: isolated test account/app-data profile or backed-up operation-owned fixture location; no inspection/export of real secure-store contents. Action: save profile/server/settings/channels, relaunch; synthetic malformed bytes/quarantine collision and IO/rename/locked-file failure through documented boundaries; blocked save during scope change/logout; secure write/delete failure where safely injectable without weakening security. Record stage, durable semantic result, backup/original byte hashes and safe error category, not secrets/paths. Expected: save before publication, preserved original bytes, clear recovery, truthful secure cancellation. Cleanup: restore operation-owned fixture data/locks; do not clear real credentials automatically. Outcome: Windows IO/credential acceptance; existing known compensation residue is not rediscovered as new.

### W-012 — Ancestor junction evidence and link-policy decision

Links: F-008, D-001, J12. Setup: disposable clean exact checkout, valid prepared artifact/provenance, new operation-owned external target. Never replace the user's existing build directory. Action: compare ordinary paths, descendant junction already rejected by CI, and a junction at build with ordinary package/Release descendants. Invoke real walker then real package/release path as authorized. Snapshot external directory entries/hashes first; include an operation-owned provenance marker for release-wrapper removal timing. Expected current omission: potential new external package/ZIP or generated-marker mutation; strict-policy candidate must reject before writes. Record path class and safe failure ID, before/after hashes, no-overwrite control. Cleanup: unlink only owned junctions before deleting owned targets; retain evidence. Outcome: confirm/refute operational consequence and resolve D-001; no arbitrary overwrite/provenance-bypass claim absent evidence.

### W-013 — Exact package, provenance, clean-system and Vulkan loader

Links: J09/J12, C12/C13. Setup: clean candidate, release engine/runtime/pins, unique package; suitable clean Windows system or authorized disposable VM/snapshot. Action: build/package with documented wrappers; verify marker source/build/engine/runtime/artifact identities, archive hash, notices/licenses and app-local retail CRT; launch outside checkout and development PATH with --media or normal startup. Inspect displayed diagnostic version/build and clipboard safe export. Verify visible/audible SDR and essential input. Missing vulkan-1.dll case only in disposable snapshot: observe loader failure/preflight message then restore snapshot/runtime; never remove a real driver file or copy machine-specific DLL into package. Expected: exact package starts with documented system prerequisite; clean system must supply Vulkan loader despite D3D11 rendering. Cleanup: remove owned package extraction/VM snapshot artifacts as authorized and restore environment. Outcome: exact-package acceptance at recorded identity; never generalize developer launch to distributable readiness.

## Deliverables and stopping point

Write a Windows evidence report in an agreed new review directory, linking W-IDs to general findings and exact candidate/runtime/package identity. State what passed, failed, was blocked, or remains ambiguous. Separate headless CTest, development runtime and packaged physical observations. Propose classification changes with evidence; keep implementation suggestions in a planning section.

Do not modify the general report's historical evidence to imply later results ran on its original source. Do not implement P-packages, weaken reference security, change platform support, publish or begin an unrelated campaign. Stop after the bounded Windows/live review unless the user explicitly authorizes subsequent work.

