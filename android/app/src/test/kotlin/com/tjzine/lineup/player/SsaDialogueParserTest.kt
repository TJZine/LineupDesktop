package com.tjzine.lineup.player

import android.text.Spanned
import android.text.Annotation
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.text.Cue
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.extractor.*
import androidx.media3.extractor.mkv.MatroskaExtractor
import androidx.media3.extractor.text.*
import androidx.media3.extractor.text.ssa.SsaParser
import java.io.ByteArrayOutputStream
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28, 34])
class SsaDialogueParserTest {
    private val format = Format.Builder().setId("ssa-fixture").setSampleMimeType("text/x-ssa").build()
    private val header = """[Script Info]
PlayResX: 640
PlayResY: 360

[V4+ Styles]
Format: Name, Fontsize, PrimaryColour, Bold, Italic, Underline, Alignment
Style: Default,32,&H8000FF00,0,0,0,2

[Events]
Format: Layer, Start, End, Style, Text
"""
    private fun script(events: List<String>) = (header + events.joinToString("\n", postfix = "\n") {
        "Dialogue: 0,0:00:00.50,0:00:10.00,Default,$it"
    }).toByteArray()
    private fun parse(parser: SubtitleParser, data: ByteArray): List<Cue> =
        parser.parseToLegacySubtitle(data, 0, data.size).getCues(1_000_000)
    private fun roundTrip(cues: List<Cue>): List<Cue> {
        val bytes = CueEncoder().encode(cues, 9_500_000)
        return CueDecoder().decode(500_000, bytes, 0, bytes.size).cues
    }
    private fun text(cues: List<Cue>) = cues.joinToString("\n") { it.text.toString() }

    @Test fun sharedDesktopWholeEventCasesAndInlineFlagsMatchAfterSerialization() {
        val cases = JSONArray(javaClass.getResourceAsStream("/ssa-dialogue-cases.json")!!.reader().readText())
        repeat(cases.length()) { index ->
            val case = cases.getJSONObject(index)
            val factory = SsaDialogueParser.Factory()
            val data = script(case.getString("input").split('\n'))
            val cues = roundTrip(parse(factory.create(format), data))
            parse(SsaParser(), data).zip(cues).forEach { (a,b) -> equivalent(a,b) }
            assertFalse("case $index fell back", factory.nativeFallback(format, cues))
            val lineup = SsaDialogueParser.lineupCues(cues)
            assertEquals("case $index", case.getString("expectedText"), text(lineup))
            if (case.has("expectedSegments")) {
                val expected = case.getJSONArray("expectedSegments")
                val segments = (SubtitleCues.encode(lineup).single()["lines"] as List<*>).single() as List<*>
                assertEquals(expected.length(),segments.size)
                repeat(expected.length()) { position ->
                    val spec = expected.getJSONObject(position)
                    val segment = segments[position] as Map<*,*>
                    assertEquals(spec.getString("text"),segment["text"])
                    for(key in listOf("bold","italic","underline")) assertEquals(spec.optBoolean(key,false),segment[key]==true)
                }
            }
            if (case.has("expectedAlign")) {
                val encoded = SubtitleCues.encode(lineup).single()
                assertEquals(case.getInt("expectedAlign"), encoded["align"])
                val segment = ((encoded["lines"] as List<*>).single() as List<*>).single() as Map<*, *>
                assertEquals(true, segment["italic"])
                assertEquals(true, segment["bold"])
                assertEquals(true, segment["underline"])
            }
        }
    }

    private fun equivalent(expected: Cue, decorated: Cue) {
        val actual = SsaDialogueParser.nativeCue(decorated)
        assertEquals(expected, actual)
        assertEquals(expected.textSizeType, actual.textSizeType)
        assertEquals(expected.textSize, actual.textSize)
        assertEquals(expected.windowColorSet, actual.windowColorSet)
        assertEquals(expected.windowColor, actual.windowColor)
        fun spans(cue: Cue): List<String> {
            val text = cue.text as? Spanned ?: return emptyList()
            return text.getSpans(0, text.length, Any::class.java).map {
                val value = when (it) {
                    is android.text.style.ForegroundColorSpan -> it.foregroundColor.toString()
                    is StyleSpan -> it.style.toString()
                    is UnderlineSpan -> "underline"
                    else -> it.javaClass.name
                }
                "${it.javaClass.name}:${text.getSpanStart(it)}:${text.getSpanEnd(it)}:${text.getSpanFlags(it)}:$value"
            }.sorted()
        }
        assertEquals(spans(expected), spans(actual))

    }

    @Test fun stockEquivalenceForOverlapIdenticalTextUnicodeTagsEmptyAndFormats() {
        val data = script(listOf("Same", "{\\pos(12,24)}Same", "{\\p1}Same", "{\\p0\\i1}😀界\\NSecond\\hline", "", "{\\unknown}Unknown"))
        val stock = parse(SsaParser(), data)
        val factory = SsaDialogueParser.Factory()
        val parser = factory.create(format)
        val marked = roundTrip(parse(parser, data))
        assertEquals(stock.size, marked.size)
        stock.zip(marked).forEach { (a, b) -> equivalent(a, b) }
        assertFalse(factory.nativeFallback(format, marked))
        assertEquals(4, SsaDialogueParser.lineupCues(marked).size)
        parser.reset()
        parse(parser, data).zip(stock).forEach { (a,b) -> equivalent(b,a) }
        for (charset in listOf(Charsets.UTF_8, Charsets.UTF_16LE, Charsets.UTF_16BE)) {
            val bom = when (charset) { Charsets.UTF_16LE -> byteArrayOf(-1,-2); Charsets.UTF_16BE -> byteArrayOf(-2,-1); else -> byteArrayOf(-17,-69,-65) }
            val encoded = bom + data.toString(Charsets.UTF_8).toByteArray(charset)
            val current = parse(SsaDialogueParser.Factory().create(format), encoded)
            parse(SsaParser(), encoded).zip(current).forEach { (a,b) -> equivalent(a,b) }
        }
    }

    @Test fun inlineTransitionsKeepAndClearFlagsAndAlignmentWithoutChangingNativeCue() {
        val data = script(listOf("{\\an9\\i1\\b1\\u1}One{\\i0\\b0\\u0}Two"))
        val cues = roundTrip(parse(SsaDialogueParser.Factory().create(format), data))
        equivalent(parse(SsaParser(), data).single(), cues.single())
        val output = SubtitleCues.encode(SsaDialogueParser.lineupCues(cues)).single()
        assertEquals(9, output["align"])
        val segments = (output["lines"] as List<*>).single() as List<*>
        assertEquals(mapOf("text" to "One", "bold" to true, "italic" to true, "underline" to true), segments[0])
        assertEquals(mapOf("text" to "Two"), segments[1])
    }

    @Test fun failureIsStickyOnTrackAndReroutesAlreadyDecodedCuesToUnmodifiedStock() {
        for (bad in listOf("Literal \uE000LN: collision", "x".repeat(65537), "{\\i1}".repeat(257))) {
            var failures = 0
            val factory = SsaDialogueParser.Factory(changed = { failures++ })
            val parser = factory.create(format)
            val current = roundTrip(parse(parser, script(listOf("{\\i1}Current"))))
            assertFalse(factory.nativeFallback(format, current))
            val data = script(listOf(bad))
            val fallback = parse(parser, data)
            assertTrue(factory.nativeFallback(format, current))
            assertEquals(1, failures)
            parse(SsaParser(), data).zip(fallback).forEach { (a,b) -> equivalent(a,b) }
            val later = script(listOf("{\\p1}Native after failure"))
            parse(SsaParser(), later).zip(parse(parser, later)).forEach { (a,b) -> equivalent(a,b) }
        }
    }

    /** Real Matroska track -> real parser factory -> real cue codec, including SSA initialization. */
    private fun extract(factory: SubtitleParser.Factory): List<CuesWithTiming> {
        val bytes = javaClass.getResourceAsStream("/ssa-authored.mkv")!!.readBytes()
        var position = 0
        val reader = DataReader { buffer, offset, length ->
            if (position == bytes.size) -1 else minOf(length, bytes.size - position).also {
                bytes.copyInto(buffer, offset, position, position + it); position += it
            }
        }
        var input = DefaultExtractorInput(reader, 0, bytes.size.toLong())
        val groups = mutableListOf<CuesWithTiming>()
        val samples = ByteArrayOutputStream()
        val extractor = MatroskaExtractor(factory)
        extractor.init(object : ExtractorOutput {
            override fun endTracks() {}
            override fun seekMap(map: SeekMap) {}
            override fun track(id: Int, type: Int) = object : TrackOutput {
                override fun format(format: Format) { assertEquals("application/x-media3-cues", format.sampleMimeType) }
                override fun sampleData(source: DataReader, length: Int, allowEnd: Boolean, part: Int): Int {
                    val buffer = ByteArray(length); val count = source.read(buffer, 0, length)
                    if (count > 0) samples.write(buffer, 0, count)
                    return count
                }
                override fun sampleData(data: ParsableByteArray, length: Int, part: Int) {
                    val buffer = ByteArray(length); data.readBytes(buffer, 0, length); samples.write(buffer)
                }
                override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, crypto: TrackOutput.CryptoData?) {
                    val all = samples.toByteArray(); val end = all.size-offset
                    val packet = all.copyOfRange(end-size, end)
                    groups.add(CueDecoder().decode(timeUs, packet, 0, packet.size))
                }
            }
        })
        val seek = PositionHolder()
        var budget = 10000
        while (--budget > 0) {
            when (extractor.read(input, seek)) {
                Extractor.RESULT_END_OF_INPUT -> break
                Extractor.RESULT_SEEK -> { position = seek.position.toInt(); input = DefaultExtractorInput(reader, seek.position, bytes.size.toLong()) }
            }
        }
        assertTrue(budget > 0)
        extractor.release()
        return groups
    }

    @Test fun actualFixtureTrackEqualsStockIncludingTimingAndMetadataSurvivesPreparsedCues() {
        val stock = extract(DefaultSubtitleParserFactory())
        val actual = extract(SsaDialogueParser.Factory())
        assertTrue(stock.isNotEmpty())
        assertEquals(stock.size, actual.size)
        stock.zip(actual).forEach { (a,b) ->
            assertEquals(a.startTimeUs, b.startTimeUs); assertEquals(a.durationUs, b.durationUs)
            assertEquals(a.cues.size, b.cues.size)
            a.cues.zip(b.cues).forEach { (x,y) -> equivalent(x,y) }
        }
        assertTrue(actual.flatMap { it.cues }.any { cue ->
            (cue.text as Spanned).getSpans(0, cue.text!!.length, Annotation::class.java).isNotEmpty()
        })
    }
    @Test fun rewrittenBytesAreNotRetainedAndCleanupDoesNotChangeSequentialStockOutput() {
        val parser = SsaDialogueParser.Factory().create(format)
        for (data in listOf(script(listOf("{\\i1}First")), script(listOf("{\\p0}Second")))) {
            val expected = parse(SsaParser(), data)
            expected.zip(parse(parser, data)).forEach { (a,b) -> equivalent(a,b) }
            val delegate = parser.javaClass.getDeclaredField("stock").apply { isAccessible = true }.get(parser)
            val input = SsaParser::class.java.getDeclaredField("parsableByteArray")
                .apply { isAccessible = true }.get(delegate) as ParsableByteArray
            assertEquals(0, input.data.size)
        }
    }

    @Test fun failureAfterDeliveryReplaysStockWithoutDuplicatingEarlierCallbacks() {
        val data = (header + "Dialogue: 0,0:00:00.50,0:00:01.00,Default,First\nDialogue: 0,0:00:02.00,0:00:03.00,Default,Second\n").toByteArray()
        val expected = mutableListOf<CuesWithTiming>()
        SsaParser().parse(data, 0, data.size, SubtitleParser.OutputOptions.allCues()) { expected.add(it) }
        val factory = SsaDialogueParser.Factory()
        val actual = mutableListOf<CuesWithTiming>()
        var injected = false
        factory.create(format).parse(data, 0, data.size, SubtitleParser.OutputOptions.allCues()) {
            if (actual.size == 1 && !injected) { injected = true; throw IllegalStateException("fixture") }
            actual.add(it)
        }
        assertTrue(injected)
        assertEquals(expected.size, actual.size)
        expected.zip(actual).forEach { (a,b) ->
            assertEquals(a.startTimeUs, b.startTimeUs); assertEquals(a.durationUs, b.durationUs)
            a.cues.zip(b.cues).forEach { (x,y) -> equivalent(x,y) }
        }
        assertTrue(factory.nativeFallback(format, actual.first().cues))
    }

    @Test fun previousPlainCueDuringTrackDeliveryCannotPoisonNewSsaTrack() {
        val factory = SsaDialogueParser.Factory()
        val parser = factory.create(format)
        assertTrue(factory.nativeFallback(format, listOf(Cue.Builder().setText("Previous plain cue").build())))
        val current = roundTrip(parse(parser, script(listOf("Current SSA"))))
        assertFalse(factory.nativeFallback(format, current))
        assertEquals("Current SSA", text(SsaDialogueParser.lineupCues(current)))
    }

    @Test fun outputOptionsOffsetsAndAlternateEventColumnsStayStockEquivalent() {
        val alternate = header.substringBefore("Format: Layer, Start, End, Style, Text") +
            "Format: Text, Start, End, Style\nDialogue: {\\an8\\i1}Alternate,0:00:00.50,0:00:03.00,Default\n"
        for (raw in listOf(script(listOf("First", "{\\p0}Second")), alternate.toByteArray())) {
            val data = byteArrayOf(9,8,7) + raw + byteArrayOf(6,5)
            for (option in listOf(SubtitleParser.OutputOptions.onlyCuesAfter(1_500_000), SubtitleParser.OutputOptions.cuesAfterThenRemainingCuesBefore(1_500_000))) {
                val expected = mutableListOf<CuesWithTiming>()
                val actual = mutableListOf<CuesWithTiming>()
                SsaParser().parse(data, 3, raw.size, option) { expected.add(it) }
                SsaDialogueParser.Factory().create(format).parse(data, 3, raw.size, option) { actual.add(it) }
                assertEquals(expected.size, actual.size)
                expected.zip(actual).forEach { (a,b) ->
                    assertEquals(a.startTimeUs, b.startTimeUs);assertEquals(a.durationUs, b.durationUs)
                    assertEquals(a.cues.size,b.cues.size)
                    a.cues.zip(roundTrip(b.cues)).forEach { (x,y) -> equivalent(x,y) }
                }
            }
        }
    }

    @Test fun malformedKnownCarrierFallsBackForTheWholeTrack() {
        val factory = SsaDialogueParser.Factory()
        val current = roundTrip(parse(factory.create(format), script(listOf("Current"))))
        val text = android.text.SpannableString(current.single().text)
        val kind = text.getSpans(0, text.length, Annotation::class.java).single { it.key.endsWith("kind.v1") }
        text.removeSpan(kind)
        assertTrue(factory.nativeFallback(format, listOf(current.single().buildUpon().setText(text).build())))
        assertTrue(factory.nativeFallback(format, current))
    }


}
