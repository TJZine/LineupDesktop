# Muse Spark visual findings — adjudication

September 9, 2026. Reviewed baseline `ae48acb2`; Muse reviewed `446ee663` using
captures from `bc0c907e`. The old captures remain historical evidence, not a
pixel-level acceptance certificate for later source. Root obtained fresh synthetic
Flutter captures at the baseline, then limited correction captures to changed
onboarding/setup surfaces. No physical Windows acceptance is implied.

Authority: [active specification](desktop-ui-design-spec.md),
[locked mock manifest](design/desktop-ui/README.md), and
[interface system](../.interface-design/system.md). Production typography and
protected Player boundaries remain authoritative over illustrative HTML styling.

| Muse finding | Adjudication |
| --- | --- |
| 1. Linking footer alignment | Accept. Status and Cancel should occupy opposite footer edges, with safe wrapping. |
| 2. Studio Updating label length | Reject as a demonstrated defect. Current normal-scale capture fits the longer label; it explicitly identifies retained stale results. Shortening solely to match a mock must not remove that information. Enlarged-text status layout remains a separate visual check. |
| 3. Expired linking geometry | Accept with corrected evidence. The cited terminal failure capture is not an expired-code fixture. Source independently confirms that an expired existing code loses QR geometry; retain a non-scannable expired placeholder and disabled Copy. Do not fabricate these for no-code terminal failure. |
| 4. Linking code-row grouping/caption | Accept. Copy belongs beside the code, Open browser below; restore the QR caption. This is a composition discrepancy, not merely optional copy. |
| 5. Server Switch profile | Reject unconditional addition. Existing implementation shows it when more than one profile exists, as the final behavior contract requires. |
| 6. Source controls/disclosures | Accept checkbox presentation; reject disclosures. The locked rich-row direction keeps details visible, and later prose explicitly rejects expanding rows. Keep real counts and meaningful grouping behavior. |
| 7. Playback cards/illustration | Accept. The changing illustrative episode strip is explicitly required by the active specification. Its absence is a substantive missing design element, not a speculative polish request. |
| 8. Default source priority | Reject changing allocation defaults from illustrative ordering. Saved priority controls real build results; visual source ordering and build priority are separate. |
| 9. Review change-label case | Accept as minor polish. Capitalize displayed change labels without altering enum or filter semantics. |

Additional root finding: setup stacks all configuration sections vertically and
omits the persistent section navigation shown by the approved full-window mock.
Restore the rail/detail composition with a wrapping navigation row at constrained
width/text scale. Retain one state owner and the shared footer; navigation must
not reset entered configuration.

The blanket “match at 720p” verdict is not supported. In particular, the missing
playback illustration and section composition require correction before visual
sign-off. No new scheduling, authentication, server-selection or Player behavior
is authorized by these visual differences.

## Dispatch and verification ledger

- `worker_luna` (configured Luna/xhigh), `linking_mock_correction`: exclusive
  `lib/app/onboarding_view.dart`; linking composition only.
- `worker_luna` (configured Luna/xhigh), `setup_mock_correction`: exclusive
  `lib/app/channel_setup_view.dart`; source controls, playback presentation and
  review-label casing. File then transfers to root for section navigation.
- Root: personal visual adjudication, navigation integration, existing behavior
  fixture adaptations, targeted captures and final evidence/commit review.
- No new layout test suite, dependencies, independent reviewer swarm or native
  Player edits. Verification results and final commit follow in the execution log.

Exact cross-renderer pixel equivalence is not claimed: matching composition,
spacing, roles and interaction states does not authorize replacing the approved
production font with the HTML example font. Final user visual acceptance and
physical Windows checks remain outstanding.
