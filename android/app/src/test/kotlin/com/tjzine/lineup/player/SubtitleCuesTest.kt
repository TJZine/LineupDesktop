package com.tjzine.lineup.player

import android.graphics.Bitmap
import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import androidx.media3.common.Format
import androidx.media3.common.text.Cue
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class SubtitleCuesTest {
    @Test fun presentationAcceptsCodecNumbersAndRejectsWithoutMutation() {
        for (scale in listOf(1, 1L, 0.25, 4.0)) {
            assertEquals((scale as Number).toFloat(), PlayerProtocol.subtitlePresentation(
                mapOf("scale" to scale, "imageRaise" to 0L, "lineupDrawsStyled" to false, "extra" to true)).scale)
        }
        for (bad in listOf(-1, 0.24, 4.01, Double.NaN, Double.POSITIVE_INFINITY, "1", true, null)) {
            try { PlayerProtocol.subtitlePresentation(mapOf("scale" to bad, "imageRaise" to 0, "lineupDrawsStyled" to false)); fail() }
            catch (e: ProtocolError) { assertEquals("invalid_argument", e.code) }
        }
        for (bad in listOf(-0.1, 0.251, Double.NaN, null)) {
            try { PlayerProtocol.subtitlePresentation(mapOf("scale" to 1, "imageRaise" to bad, "lineupDrawsStyled" to false)); fail() }
            catch (e: ProtocolError) { assertEquals("invalid_argument", e.code) }
        }
        try { PlayerProtocol.subtitlePresentation(mapOf("scale" to 1, "imageRaise" to 0)); fail() }
        catch (e: ProtocolError) { assertEquals("invalid_argument", e.code) }
    }

    @Test fun classificationIncludesPreparsedDecoderMimeAndUnknownText() {
        for (mime in listOf("application/pgs", "application/vobsub", "application/dvbsubs", "text/x-ssa",
            "application/x-subrip", "text/vtt", "application/x-quicktime-tx3g", "application/cea-608", "application/cea-708", "text/unknown")) {
            val expected = mime in listOf("application/pgs", "application/vobsub", "application/dvbsubs", "text/x-ssa")
            for (preparsed in listOf(false, true)) {
                val format = Format.Builder().setSampleMimeType(if (preparsed) "application/x-media3-cues" else mime)
                    .setCodecs(if (preparsed) mime else null).build()
                assertEquals(mime, expected, SubtitleCues.engineDraws(format, SubtitlePresentation()))
                assertEquals(mime, expected && mime != "text/x-ssa", SubtitleCues.engineDraws(format, SubtitlePresentation(lineupDrawsStyled = true)))
            }
        }
    }

    @Test fun spansAndAlignmentAreEncodedWithoutEmbeddedColorsOrFonts() {
        val text = SpannableString("One\nTwo")
        text.setSpan(StyleSpan(Typeface.BOLD_ITALIC), 0, 3, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        text.setSpan(UnderlineSpan(), 4, 7, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        val encoded = SubtitleCues.encode(listOf(Cue.Builder().setText(text).setLine(0.1f, Cue.LINE_TYPE_FRACTION)
            .setTextAlignment(Layout.Alignment.ALIGN_OPPOSITE).build())).single()
        assertEquals(9, encoded["align"])
        assertEquals(listOf(listOf(mapOf("text" to "One", "italic" to true, "bold" to true)),
            listOf(mapOf("text" to "Two", "underline" to true))), encoded["lines"])
        for ((line, expected) in listOf(0f to 8, 4f to 8, 5f to 2, 14f to 2, -1f to 2, -10f to 2)) {
            assertEquals(expected, SubtitleCues.alignment(Cue.Builder().setText("row").setLine(line, Cue.LINE_TYPE_NUMBER).build()))
        }
        for ((position, column) in listOf(0.1f to 1, 0.5f to 2, 0.9f to 3))
            for ((line, row) in listOf(0.1f to 2, 0.5f to 1, 0.9f to 0))
                assertEquals(row * 3 + column, SubtitleCues.alignment(Cue.Builder().setText("row")
                    .setPosition(position).setLine(line, Cue.LINE_TYPE_FRACTION).build()))
        for ((line, expected) in listOf(0.1f to 7, 0.5f to 4, 0.9f to 1))
            assertEquals(expected, SubtitleCues.alignment(Cue.Builder().setText("row").setPosition(0.1f).setLine(line, Cue.LINE_TYPE_FRACTION).build()))
    }

    @Test fun encodingEnforcesAllBoundsAndKeepsUnicodeCodePoints() {
        fun cue(text: CharSequence) = Cue.Builder().setText(text).build()
        val encoded = SubtitleCues.encode(listOf(cue("😀".repeat(2000))))
        val lines = encoded.single()["lines"] as List<*>
        val text = ((lines.single() as List<*>).single() as Map<*, *>)["text"] as String
        assertEquals(4096, text.toByteArray(Charsets.UTF_8).size)
        assertEquals("😀".repeat(1024), text)
        assertEquals(8, SubtitleCues.encode(List(9) { cue("x") }).size)
        assertEquals(8, (SubtitleCues.encode(listOf(cue(List(9) { "x" }.joinToString("\n")))).single()["lines"] as List<*>).size)
        val spanned = SpannableString("a".repeat(40))
        repeat(40) { spanned.setSpan(StyleSpan(if (it % 2 == 0) Typeface.BOLD else Typeface.ITALIC), it, it+1, 33) }
        assertEquals(32, ((SubtitleCues.encode(listOf(cue(spanned))).single()["lines"] as List<*>).single() as List<*>).size)
    }

    private fun bitmap() = Cue.Builder().setBitmap(Bitmap.createBitmap(20, 10, Bitmap.Config.ARGB_8888))
        .setSize(0.4f).setBitmapHeight(0.1f).setPosition(0.3f).setPositionAnchor(Cue.ANCHOR_TYPE_START)
        .setLine(0.8f, Cue.LINE_TYPE_FRACTION).setLineAnchor(Cue.ANCHOR_TYPE_START).build()

    @Test fun bitmapScalesAtBottomCenterRaisesAndClampsWithUnsupportedGeometryPassedThrough() {
        val original = bitmap()
        for (scale in listOf(0.5f, 1f, 1.5f, 3f)) {
            val result = SubtitleCues.transform(original, SubtitlePresentation(scale, 0.1f))
            val width = (0.4f * scale).coerceAtMost(1f)
            assertEquals(width, result.size, 0.0001f)
            assertEquals((0.5f - width / 2).coerceIn(0f, 1f-width), result.position, 0.0001f)
            assertEquals(0.8f - 0.1f * scale, result.line, 0.0001f)
            assertTrue(result.line + result.bitmapHeight <= 1f)
        }
        val unchanged = SubtitleCues.transform(original, SubtitlePresentation())
        assertEquals(original.position, unchanged.position, 0.0001f)
        assertEquals(original.line, unchanged.line, 0.0001f)
        val corner = original.buildUpon().setPosition(0.99f).setLine(0.99f, Cue.LINE_TYPE_FRACTION).build()
        val clamped = SubtitleCues.transform(corner, SubtitlePresentation(1.5f))
        assertEquals(1f, clamped.position + clamped.size, 0.0001f)
        assertEquals(1f, clamped.line + clamped.bitmapHeight, 0.0001f)
        for (cue in listOf(original.buildUpon().setPositionAnchor(Cue.ANCHOR_TYPE_MIDDLE).build(),
            original.buildUpon().setBitmapHeight(Cue.DIMEN_UNSET).build(),
            original.buildUpon().setLine(1f, Cue.LINE_TYPE_NUMBER).build()))
            assertSame(cue, SubtitleCues.transform(cue, SubtitlePresentation(3f)))
        assertTrue(SubtitleCues.encode(listOf(original)).isEmpty())
    }

    @Test fun ssaSizeUsesItsAuthoredFractionAndLeavesAbsoluteSizeAlone() {
        for (type in listOf(Cue.TEXT_SIZE_TYPE_FRACTIONAL, Cue.TEXT_SIZE_TYPE_FRACTIONAL_IGNORE_PADDING, Cue.TEXT_SIZE_TYPE_ABSOLUTE)) {
            val cue = Cue.Builder().setText("SSA").setTextSize(0.1f, type).build()
            assertEquals(if (type == Cue.TEXT_SIZE_TYPE_ABSOLUTE) 0.1f else 0.3f,
                SubtitleCues.transform(cue, SubtitlePresentation(3f)).textSize, 0.0001f)
        }
    }

    @Test fun pendingCuesReplaceInPlaceAndSurviveEveryEvictionPath() {
        val queue = PlayerEventQueue()
        fun event(name: String, value: Any? = null, type: String = "property") =
            QueuedEvent(1, 1, mapOf("type" to type, "name" to name, "value" to value))
        queue.add(event("a")); queue.add(event("subtitle-cues", "first")); queue.add(event("b"))
        queue.add(event("subtitle-cues", "clear"))
        assertEquals("a", queue.take()!!.value["name"])
        assertEquals("clear", queue.take()!!.value["value"])
        queue.clear()
        queue.add(event("subtitle-cues", "clear"))
        repeat(300) { queue.add(event("property$it")) }
        assertEquals(256, queue.size)
        assertEquals("clear", queue.take()!!.value["value"])
        queue.clear()
        queue.add(event("subtitle-cues"))
        repeat(300) { queue.add(event("state$it", type = "state")) }
        assertEquals(256, queue.size)
        assertEquals("subtitle-cues", queue.take()!!.value["name"])
    }
    @Test fun actualSsaDecoderRetainsAuthoredFractionalSizeAndColor() {
        val script = """[Script Info]
PlayResX: 640
PlayResY: 360

[V4+ Styles]
Format: Name, Fontsize, PrimaryColour, Bold, Italic, Underline, Alignment
Style: Default,32,&H8000FF00,0,0,0,2

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.50,0:00:29.00,Default,Fixture
""".toByteArray()
        val subtitle = androidx.media3.extractor.text.ssa.SsaParser().parseToLegacySubtitle(script, 0, script.size)
        val cue = subtitle.getCues(1_000_000).single()
        assertEquals(32f / 360f, cue.textSize, 0.0001f)
        val text = cue.text as Spanned
        assertEquals(0x7f00ff00, text.getSpans(0, text.length, android.text.style.ForegroundColorSpan::class.java).single().foregroundColor)
    }

}
