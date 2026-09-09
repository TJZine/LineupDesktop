# Portable desktop review packets

Frozen baseline for the [collaborative correction workflow](../../../desktop-ui-collaborative-handoff.md).

| Packet | Implementation source | Captures | Archive size |
| --- | --- | --- | --- |
| [cbf3dbd5-1080p.zip](cbf3dbd5-1080p.zip) | `cbf3dbd580d7c8147c1327342811c56fa4af6bfb` | 45 real1920×1080 PNGs; DPR1/text100%; 39 paired HTML references | 5,350,871 bytes |

SHA-256: `62dffa193c20057aabaa1032f4f6e478eec5af951086599a8db83408ed8c32e4`

After this commit is pushed by the user or under separate authorization, pull
`dev/desktop-ui-refinement` on the other machine. Extract the ZIP with the
platform archive tool and open `lineup-1080p-cbf3dbd5/comparison.html` in a browser
at 100% zoom. No Flutter, Plex, server, network or dependency installation is
needed to view the packet. The viewer starts at1:1; Fit preview is optional.

The ZIP contains the self-contained viewer, manifest, portable instructions,
optional standard-library PNG extraction helper and a historical macOS snapshot
capture harness. It omits duplicate raw PNGs, generated logs and personal SDK
paths. The 45 original PNGs can be extracted losslessly when needed.

The locked left-hand HTML is embedded unchanged apart from host wrappers,
comparison-control visibility and selection of documented variants/states.
Component-only references and responsive design canvases are labeled; they are
not invented authored1080p mocks. Some synthetic content/states differ. Six
surfaces intentionally have no paired standalone mock.

Validation: archive integrity checked; extracted viewer is byte-identical to the
reviewed packet; all45 extracted PNGs match manifest SHA-256 and1920×1080
dimensions; bundled Python parses. No production code or platform test was run
for this documentation/package commit. The archive is immutable historical
evidence; later changes require fresh affected-surface captures, not relabeling
this packet as current. See the [approval ledger](../../../desktop-ui-surface-approvals.md).
