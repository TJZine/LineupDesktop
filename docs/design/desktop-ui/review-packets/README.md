# Portable desktop review packets

Frozen starting baseline for the September 2026 collaborative correction
campaign. Later approvals are recorded in the
[approval ledger](../../../desktop-ui-surface-approvals.md).

| Packet | Implementation source | Captures |
| --- | --- | --- |
| [1080p offline viewer](lineup-1080p-cbf3dbd5/comparison.html) | `cbf3dbd580d7c8147c1327342811c56fa4af6bfb` | 45 real1920×1080 PNGs; DPR1/text100%; 39 paired HTML references |

Open `lineup-1080p-cbf3dbd5/comparison.html` in a browser at 100% zoom. No Flutter,
Plex, server, network or dependency installation is needed to view the packet.
The viewer starts at1:1; Fit preview is optional.

The retained folder contains the self-contained viewer, manifest, portable instructions,
optional standard-library PNG extraction helper and a historical macOS snapshot
capture harness. It omits duplicate raw PNGs, generated logs and personal SDK
paths. The 45 original PNGs can be extracted losslessly when needed.

The locked left-hand HTML is embedded unchanged apart from host wrappers,
comparison-control visibility and selection of documented variants/states.
Component-only references and responsive design canvases are labeled; they are
not invented authored1080p mocks. Some synthetic content/states differ. Six
surfaces intentionally have no paired standalone mock.

Original validation: archive integrity checked; extracted viewer was byte-identical to the
reviewed packet; all45 extracted PNGs matched manifest SHA-256 and1920×1080
dimensions; bundled Python parses. No production code or platform test was run
for that documentation/package commit. The packet is immutable historical
evidence; later changes require fresh affected-surface captures, not relabeling
this packet as current. See the [approval ledger](../../../desktop-ui-surface-approvals.md).

The former ZIP duplicated all five retained files byte for byte and is available
in [Git history](../../../README.md#historical-material-in-git). The viewer,
manifest and original PNG extraction helper remain usable in this folder.
