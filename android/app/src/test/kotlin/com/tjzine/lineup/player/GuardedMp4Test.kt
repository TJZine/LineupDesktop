package com.tjzine.lineup.player

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.extractor.*
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test

class GuardedMp4Test {
    private fun box(type: String, payload: ByteArray) =
        ByteBuffer.allocate(4).putInt(payload.size + 8).array() + type.toByteArray() + payload

    private fun moov() =
        box(
            "moov",
            listOf("vide", "soun").fold(byteArrayOf()) { a, t ->
                a + box("trak", box("mdia", box("hdlr", ByteArray(8) + t.toByteArray())))
            },
        )

    private class Input(val bytes: ByteArray) {
        var position = 0
        val value =
            Proxy.newProxyInstance(
                ExtractorInput::class.java.classLoader,
                arrayOf(ExtractorInput::class.java),
            ) { _, method, args ->
                when (method.name) {
                    "getPosition",
                    "getPeekPosition" -> position.toLong()
                    "getLength" -> bytes.size.toLong()
                    "readFully" -> {
                        val target = args[0] as ByteArray
                        val offset = args[1] as Int
                        val count = args[2] as Int
                        bytes.copyInto(target, offset, position, position + count)
                        position += count
                        if (method.returnType == Boolean::class.javaPrimitiveType) true else null
                    }
                    else -> error("unexpected_test_input_method")
                }
            } as ExtractorInput
    }

    private data class Step(
        val bytes: ByteArray,
        val video: Boolean,
        val audio: Boolean,
        val endTracks: Boolean,
    )

    private class ReusingExtractor(val steps: List<Step>) : Extractor, ParsedTrackReporter {
        override var reportParsedTrack: (Int?) -> Unit = {}
        lateinit var output: ExtractorOutput
        private val outputs = mutableMapOf<Int, TrackOutput>()
        var index = 0

        override fun sniff(input: ExtractorInput) = true

        override fun init(output: ExtractorOutput) {
            this.output = output
        }

        override fun seek(position: Long, timeUs: Long) {
            if (position == 0L) index = 0
        }

        override fun release() {}

        override fun read(input: ExtractorInput, holder: PositionHolder): Int {
            val step = steps[index++]
            input.readFully(ByteArray(step.bytes.size), 0, step.bytes.size)
            if (step.bytes.size >= 8 && String(step.bytes, 4, 4) == "moov") {
                reportParsedTrack(if (step.video) C.TRACK_TYPE_VIDEO else null)
                reportParsedTrack(if (step.audio) C.TRACK_TYPE_AUDIO else null)
            }
            for ((type, mime) in
                listOf(
                    C.TRACK_TYPE_VIDEO to MimeTypes.VIDEO_H264,
                    C.TRACK_TYPE_AUDIO to MimeTypes.AUDIO_AAC,
                )) {
                if (
                    (type == C.TRACK_TYPE_VIDEO && step.video) ||
                        (type == C.TRACK_TYPE_AUDIO && step.audio)
                ) {
                    val target = outputs.getOrPut(type) { output.track(type, type) }
                    target.format(Format.Builder().setSampleMimeType(mime).build())
                }
            }
            if (step.endTracks) output.endTracks()
            return Extractor.RESULT_CONTINUE
        }
    }

    private fun guard(steps: List<Step>): Pair<GuardedMp4, ReusingExtractor> {
        val delegate = ReusingExtractor(steps)
        val guard = GuardedMp4(delegate)
        guard.init(
            object : ExtractorOutput {
                override fun track(id: Int, type: Int): TrackOutput = DiscardingTrackOutput()

                override fun endTracks() {}

                override fun seekMap(map: SeekMap) {}
            }
        )
        return guard to delegate
    }

    @Test
    fun reusedOutputsRepublishFormatsWithoutEndTracksReplay() {
        val bytes = moov()
        val (guard, _) =
            guard(listOf(Step(bytes, true, true, true), Step(bytes, true, true, false)))
        val input = Input(bytes + bytes)
        guard.read(input.value, PositionHolder())
        guard.read(input.value, PositionHolder())
    }

    @Test(expected = OmittedMediaType::class)
    fun oldVideoExposureCannotSatisfyNewMoov() {
        val bytes = moov()
        val (guard, _) =
            guard(listOf(Step(bytes, true, true, true), Step(bytes, false, true, false)))
        val input = Input(bytes + bytes)
        guard.read(input.value, PositionHolder())
        guard.read(input.value, PositionHolder())
    }

    @Test(expected = OmittedMediaType::class)
    fun oldAudioExposureCannotSatisfyNewMoov() {
        val bytes = moov()
        val (guard, _) =
            guard(listOf(Step(bytes, true, true, true), Step(bytes, true, false, false)))
        val input = Input(bytes + bytes)
        guard.read(input.value, PositionHolder())
        guard.read(input.value, PositionHolder())
    }

    @Test
    fun byteZeroReparseCanReuseOutputs() {
        val bytes = moov()
        val (guard, _) = guard(listOf(Step(bytes, true, true, true)))
        val input = Input(bytes)
        guard.read(input.value, PositionHolder())
        guard.seek(0, 0)
        input.position = 0
        guard.read(input.value, PositionHolder())
    }

    @Test
    fun ordinarySampleSeekKeepsValidatedTypes() {
        val bytes = moov()
        val sample = ByteArray(20)
        val (guard, _) =
            guard(listOf(Step(bytes, true, true, true), Step(sample, false, false, false)))
        val input = Input(bytes + sample)
        guard.read(input.value, PositionHolder())
        guard.seek(bytes.size.toLong(), 1000000)
        guard.read(input.value, PositionHolder())
    }

    @Test(expected = OmittedMediaType::class)
    fun nonzeroFragmentSeekStillObservesNewMoovVideoOmission() {
        val bytes = moov()
        val (guard, _) =
            guard(listOf(Step(bytes, true, true, true), Step(bytes, false, true, false)))
        val input = Input(bytes + bytes)
        guard.read(input.value, PositionHolder())
        guard.seek(bytes.size.toLong(), 1000000)
        guard.read(input.value, PositionHolder())
    }

    @Test(expected = OmittedMediaType::class)
    fun nonzeroFragmentSeekStillObservesNewMoovAudioOmission() {
        val bytes = moov()
        val (guard, _) =
            guard(listOf(Step(bytes, true, true, true), Step(bytes, true, false, false)))
        val input = Input(bytes + bytes)
        guard.read(input.value, PositionHolder())
        guard.seek(bytes.size.toLong(), 1000000)
        guard.read(input.value, PositionHolder())
    }
}
