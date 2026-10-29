package com.tjzine.lineup.player

import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner::class)
@org.robolectric.annotation.Config(manifest = org.robolectric.annotation.Config.NONE, sdk = [28])
class Media3FailureTest {
    private fun classify(code: Int, cause: Throwable? = null) = Media3Failure.classify(code, cause)

    @Test
    fun decoderTypeUsesTheRendererFormat() {
        assertEquals(
            "video_decode_error",
            Media3Failure.classify(
                    PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
                    null,
                    "video/hevc",
                )
                .first,
        )
        assertEquals(
            "audio_decode_error",
            Media3Failure.classify(
                    PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
                    null,
                    "audio/ac3",
                )
                .first,
        )
        assertEquals(
            "native_error",
            Media3Failure.classify(PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED, null).first,
        )
    }

    @Test
    fun decoderInitializationCauseProvidesTypeWhenRendererFormatIsUnavailable() {
        val format = androidx.media3.common.Format.Builder().setSampleMimeType("audio/ac3").build()
        val cause =
            androidx.media3.exoplayer.mediacodec.MediaCodecRenderer.DecoderInitializationException(
                format,
                RuntimeException("synthetic"),
                false,
                -49999,
            )
        assertEquals(
            "audio_decode_error",
            Media3Failure.classify(PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED, cause).first,
        )
    }

    @Test
    fun typedContainerObserverWinsOverGenericIoAndOmissionWinsOverParser() {
        assertEquals(
            "container_error",
            classify(
                    PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
                    IOException(Mp4ObservationError()),
                )
                .first,
        )
        assertEquals(
            "video_decode_error",
            classify(
                    PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
                    OmittedMediaType(C.TRACK_TYPE_VIDEO),
                )
                .first,
        )
        assertEquals(
            "audio_decode_error",
            classify(
                    PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
                    OmittedMediaType(C.TRACK_TYPE_AUDIO),
                )
                .first,
        )
    }

    @Test
    fun networkOutputContainerSourceAndUnknownVocabulary() {
        for ((code, expected) in
            listOf(
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT to "network_error",
                PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED to "audio_output_error",
                PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED to "audio_output_error",
                PlaybackException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED to "video_output_error",
                PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED to "container_error",
                PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND to "source_open_error",
                PlaybackException.ERROR_CODE_UNSPECIFIED to "native_error",
            )) assertEquals(expected to null, classify(code))
    }
}
