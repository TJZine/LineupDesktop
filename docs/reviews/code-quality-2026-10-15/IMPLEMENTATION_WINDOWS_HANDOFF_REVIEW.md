# F merged-candidate and Windows handoff review

Independent read-only reviewer: `gpt-6.1-sol`, high, reused F reviewer chat
`01a13ef0-549f-7322-a638-693ccac00bdb`, local host, October 15, 2026.

Reviewed portable closeout `952f321accfdc7b2e640f63938506023ba0acd75` through
F merge `4f3b144a7989a0ba9f0096bf88bb265dd817bf7f` and handoff/status HEAD
`32e68e4c44e831680ab661bc88a8d8dfd63e4104`. HEAD and clean tree remained
stable. The reviewer retrieved actual human authorization for the task-branch
merge/push override; original parent-only callback consent remained verified.

## Verdict and controller disposition

No material actionable finding was established. The controller accepts the
composition/handoff review and the authorized task-branch push recommendation,
with F **merged for testing, Windows validation pending**. Source review is not
native validation; the full plan remains incomplete.

## Reviewed evidence

- Raw merge parents are the portable closeout and F candidate
  `040e4a64bdc667bae9673d61a39a8d15261959c3`. Original and integrated binary
  patches independently match SHA-256
  `e46a6521662382bd68f3e33308f42e95a0e844f5349e147fbea03a4261395142`.
  All Windows files equal the original F candidate; no intervening portable
  Windows source delta exists from F's M base to closeout. The earlier full
  12-file source review and retained fixture/test obligations carry forward.
- Relevant display matching, Dart/native interface and protocol inputs remain
  compatible. Current request/revision guards, CMake targets and runner asset
  inputs were inspected; no new composition defect was established.
- Handoff includes correct four-suite names/targets, patched release-engine
  build, matching installed assets, prepared runtime/SDK requirements, explicit
  four-distinct-tests/no-skip requirement and `--no-tests=error`. Checkout uses
  fast-forward-only updates, preserves unrelated work, verifies merge ancestry
  and freezes the actual pulled full SHA.
- Local handoff links resolve. Setup matches current Development and release
  scripts; H's CI entry invokes `verify-release-policy.ps1`, where its assertion
  lives. Compilation, constexpr assertions, journal parsing and Windows CTests
  remain explicitly unobserved. Other native obligations and individual physical
  W1–W12 rows remain distinct, with operator/privacy controls.
- Actual scope after the earlier portable-tested `476750d9` is F's 12 Windows
  paths and four documentation paths. Portable product/test/tool/macOS/config
  inputs are unchanged. Historical unmerged/no-push wording is expressly
  superseded only for this authorized testing branch.

Reviewer observed source/doc/script/CMake/Git inspection, matching patch hashes,
clean HEAD, link-target checks and `git diff --check` exit 0. No reviewer builds,
tests, formatter, analyzer, pub, writes, delegation or publication occurred.

## Separate controller verification

P0 chat `01a13eaa-0f77-7ef1-a805-cbad67a3714a`, `gpt-5.6-luna`/xhigh,
ran the exclusive combined portable gate at the same unchanged clean `32e68e4c`:
pin check, formatter 144 files/0 changed, analysis clean and all 1,690 tests
passed, all exit 0. Full suite wall time was 327.61 seconds, slower than earlier
runs; no cause or performance conclusion is established. Controller inspected
the actual logs in `/tmp/lineup-cq-integration/windows-handoff/`.

No Windows compile/CTest/physical result is inferred. Prior macOS build evidence
is carried as attributed evidence because all macOS build inputs are unchanged.
Later recording commits change documentation only.
