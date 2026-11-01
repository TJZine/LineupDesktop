# Public extraction oracle

These are generated color/sine fMP4 fixtures, never private media. They preserve
the accepted public corpus from the `54caf2e1` evidence lineage. Its generation
encoded synthetic H.264/HEVC video and AAC audio, then shifted fragment `tfdt`
clocks by +10 s. An independent ffprobe packet pass produced the video PTS ledger
and per-fragment first-PTS/count facts in `corpus.json`; the manifest hashes bind
the initialization and fragment bytes.

Tests require these files without an optional environment or skip. They compare
stock MODE_NO_OFFSET extraction with the independent ledger, then compare stock
and wrapped sample metadata after subtracting the actual TimestampAdjuster A.
This proves extraction/clock parity, not decoder, display, HDR or private-source
acceptance. Regeneration must refresh both hashes and the independently obtained
packet oracle; do not rewrite the expected ledger from the implementation under
test. Keep the preserved original evidence immutable.
