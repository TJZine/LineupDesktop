# Lineup 1080p manual review packet

Implementation baseline: cbf3dbd580d7c8147c1327342811c56fa4af6bfb.

Extract the archive and open comparison.html in a desktop browser. It is
self-contained and works offline. No Flutter installation, Plex account, local
server or package installation is needed to view it. Use browser zoom 100%.
The viewer defaults to 1:1; scroll, switch Mock/Result, or choose the explicitly
labeled Fit preview for an overview. Fit affects display only.

45 real Flutter captures: physical1920x1080, DPR1, text scale1. PNGs were never
resized, retouched or created from HTML. The application's own resolution-aware
layout remains active. 39 entries pair these with original locked HTML; six are
current-only because no matching standalone mock exists. The left side is live
HTML, not a raster mock screenshot. Labels distinguish original1080 modes,
natural-size component mocks, and original responsive1280-canvas references.
Do not infer exact full-window pixel parity from component references.

Different synthetic names/counts, media backgrounds and some states are noted
per surface. This is a frozen starting reference, not a current screenshot after
later implementation edits and not a physical Windows acceptance certificate.

Files:
- comparison.html: the complete offline viewer, including all PNGs and mocks.
- manifest.json: capture settings, reference variants and image/source hashes.
- extract_pngs.py: optional Python standard-library helper; extracts the original
  45 PNGs from the viewer with SHA-256 and dimension checks. Run from this folder
  using `python3 extract_pngs.py` (or `py extract_pngs.py` on Windows).
- capture-harness.py: historical snapshot-reproduction helper. This uses the
  existing macOS-only Flutter golden fixture suite; it is NOT a Windows capture
  tool or a direction to rerun all surfaces during each correction. Run from the
  repository root with its documented Flutter3.47.2 SDK on PATH, or set
  FLUTTER_BIN to that SDK's executable. An optional first argument restricts
  fixture test names. It restores the tracked test after running and writes
  evidence below build/desktop-ui/comparison-1080/.

The viewer retains the original QR generator copyright/MIT notice and embeds the
exact qrcode-generator1.4.4 script referenced by the linking mock for offline use.

The main repository's current workflow starts at [AGENTS.md](../../../../../AGENTS.md).
The [manual approval ledger](../../../../desktop-ui-surface-approvals.md) records
later surface approvals, and the [visual manifest](../../README.md) identifies
the original mocks. This packet predates those approvals and remains a frozen
starting reference. The former collaborative handoff is available in Git history.
