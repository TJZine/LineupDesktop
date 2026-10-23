package com.tjzine.lineup.player

import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.ExoPlaybackException

@UnstableApi
internal object Media3Failure {
    fun classify(error: PlaybackException): Pair<String, Int?> {
        return classify(
            error.errorCode,
            error.cause,
            (error as? ExoPlaybackException)?.rendererFormat?.sampleMimeType,
        )
    }

    internal fun classify(
        errorCode: Int,
        cause: Throwable?,
        rendererMime: String? = null,
    ): Pair<String, Int?> {
        val causes = generateSequence(cause) { it.cause }.take(32).toList()
        causes.filterIsInstance<OmittedMediaType>().firstOrNull()?.let {
            return (if (it.mediaType == C.TRACK_TYPE_VIDEO) "video_decode_error"
            else "audio_decode_error") to null
        }
        // This structural guard extends IOException; test it BEFORE generic network IO.
        if (causes.any { it is Mp4ObservationError }) return "container_error" to null
        causes.filterIsInstance<HttpDataSource.InvalidResponseCodeException>().firstOrNull()?.let {
            return "http_error" to it.responseCode.takeIf { code -> code in 400..599 }
        }
        if (causes.any { it is HttpDataSource.HttpDataSourceException })
            return "network_error" to null
        if (
            causes.any {
                it is androidx.media3.exoplayer.video.MediaCodecVideoDecoderException &&
                    !it.isSurfaceValid
            }
        )
            return "video_output_error" to null
        val decoderMime =
            rendererMime
                ?: causes
                    .filterIsInstance<
                        androidx.media3.exoplayer.mediacodec.MediaCodecRenderer.DecoderInitializationException
                    >()
                    .firstOrNull()
                    ?.mimeType
        val code =
            when (errorCode) {
                PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS -> "http_error"
                PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND,
                PlaybackException.ERROR_CODE_IO_NO_PERMISSION,
                PlaybackException.ERROR_CODE_IO_UNSPECIFIED -> "source_open_error"
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
                PlaybackException.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE,
                PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,
                PlaybackException.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED -> "network_error"
                PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
                PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
                PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED,
                PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED -> "container_error"
                PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED,
                PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED,
                PlaybackException.ERROR_CODE_AUDIO_TRACK_OFFLOAD_INIT_FAILED,
                PlaybackException.ERROR_CODE_AUDIO_TRACK_OFFLOAD_WRITE_FAILED ->
                    "audio_output_error"
                PlaybackException.ERROR_CODE_VIDEO_FRAME_PROCESSOR_INIT_FAILED,
                PlaybackException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED -> "video_output_error"
                PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
                PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
                PlaybackException.ERROR_CODE_DECODING_FAILED,
                PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
                PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED -> {
                    when (androidx.media3.common.MimeTypes.getTrackType(decoderMime)) {
                        C.TRACK_TYPE_VIDEO -> "video_decode_error"
                        C.TRACK_TYPE_AUDIO -> "audio_decode_error"
                        else -> "native_error"
                    }
                }
                else -> "native_error"
            }
        return code to null
    }
}
