package com.tjzine.lineup.player

import android.content.Context
import android.os.Handler
import android.view.SurfaceView
import androidx.media3.common.*
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.ExoTimeoutException
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.SubtitleView
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient

/** Media/OS mechanism only. Each instance has one immutable load and is never reused. */
@UnstableApi
internal class Media3Engine(
    context: Context,
    private val handler: Handler,
    video: SurfaceView,
    private val subtitles: SubtitleView,
    private val sizeChanged: (VideoSize) -> Unit,
    private val keepScreenOn: (Boolean) -> Unit,
    createPlayer: (Context) -> ExoPlayer = {
        ExoPlayer.Builder(it).setLoadControl(PlaybackMemory.loadControl(it)).build()
    },
    private val subtitlePresentation: () -> SubtitlePresentation = { SubtitlePresentation() },
) : PlayerEngine {
    // The default builder owns an exclusive playback thread. Media3 quits it only
    // after releaseInternal finishes renderer/source teardown. Keep that public
    // thread handle: release() returning (or isReleased) cannot prove completion.
    private val player = createPlayer(context).also {
        it.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            /* handleAudioFocus = */ true,
        )
        it.setVideoSurfaceView(video)
    }
    // Transient focus loss suppresses playback without clearing playWhenReady.
    // Report the observed pause through the existing Dart event contract; Media3
    // alone owns ducking/resumption, while Dart retains scheduling policy.
    private fun observedPaused() = !player.playWhenReady ||
        player.playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS
    private val playbackThread = player.playbackLooper.thread
    private var releasingPlayer = false
    private var releaseTimedOut = false
    private var releaseReturned = false

    init {
        player.addListener(
            object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    val timeout = error.cause as? ExoTimeoutException
                    if (
                        releasingPlayer &&
                            error.errorCode == PlaybackException.ERROR_CODE_TIMEOUT &&
                            timeout?.timeoutOperation ==
                                ExoTimeoutException.TIMEOUT_OPERATION_RELEASE
                    ) {
                        releaseTimedOut = true
                    }
                }
            }
        )
    }

    private val tracks = Media3Tracks()
    private val debug =
        context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
    private var client: OkHttpClient? = null
    private var http: OkHttpDataSource.Factory? = null
    private var closed = false
    private var released = false
    private var observer: PlayerEngine.Listener? = null
    private var lastCues: List<Cue> = emptyList()
    private var subtitleFormat: Format? = null
    private val ssaParsers = SsaDialogueParser.Factory(debug) {
        handler.post { if (!closed) refreshSubtitles() }
    }

    internal fun subtitleTracksChanged(value: Tracks) {
        if (closed) return
        try {
            subtitleFormat = value.groups.firstNotNullOfOrNull { group ->
                if (group.type != C.TRACK_TYPE_TEXT) null else
                    (0 until group.length).firstOrNull { group.isTrackSelected(it) }
                        ?.let { group.getTrackFormat(it) }
            }
            if (subtitleFormat == null) lastCues = emptyList()
            subtitles.setCues(emptyList())
            observer?.property("subtitle-cues", emptyList<Any>())
            refreshSubtitles()
        } catch (_: Exception) {
            if (debug) android.util.Log.d("LineupPlayer", "Subtitle track update skipped")
        }
    }

    internal fun subtitleCuesChanged(cues: List<Cue>) {
        if (!closed) {
            lastCues = cues
            refreshSubtitles()
        }
    }

    fun refreshSubtitles() {
        if (closed) return
        try {
            val presentation = subtitlePresentation()
            val native = SubtitleCues.engineDraws(subtitleFormat, presentation) ||
                ssaParsers.nativeFallback(subtitleFormat, lastCues)
            subtitles.setCues(lastCues.filter { it.bitmap != null || native }
                .map { SubtitleCues.transform(SsaDialogueParser.nativeCue(it), presentation) })
            observer?.property("subtitle-cues", if (native) emptyList<Any>()
                else if (subtitleFormat == null) emptyList<Any>() else SubtitleCues.encode(
                    if (SsaDialogueParser.isSsa(subtitleFormat)) SsaDialogueParser.lineupCues(lastCues) else lastCues))
        } catch (_: Exception) {
            if (debug) android.util.Log.d("LineupPlayer", "Subtitle update skipped")
        }
    }

    private val progress =
        object : Runnable {
            override fun run() {
                if (closed) return
                val p = player.currentPosition
                observer?.property("time-pos", p.coerceAtLeast(0) / 1000.0)
                val d = player.duration
                observer?.property("duration", if (d == C.TIME_UNSET || d < 0) null else d / 1000.0)
                handler.postDelayed(this, 250)
            }
        }

    override fun load(media: MediaLoad, listener: PlayerEngine.Listener) {
        check(observer == null && !closed)
        observer = listener
        if (media.uri.toHttpUrlOrNull()?.isHttps != true) {
            listener.failure("source_open_error")
            return
        }
        val network = MediaHttp.forLoad()
        client = network
        val source = OkHttpDataSource.Factory(network)
        if (media.token != null)
            source.setDefaultRequestProperties(mapOf("X-Plex-Token" to media.token))
        http = source
        if (debug) {
            var lastTimestamp: Long? = null
            player.setVideoFrameMetadataListener { ptsUs, _, _, _ ->
                val previous = lastTimestamp
                if (previous == null || ptsUs < previous || ptsUs - previous >= 5_000_000) {
                    lastTimestamp = ptsUs
                    handler.post { if (!closed) listener.frameTimestamp(ptsUs) }
                }
            }
        }
        player.addListener(
            object : Player.Listener {
                override fun onPlaybackStateChanged(state: Int) {
                    if (closed) return
                    when (state) {
                        Player.STATE_READY -> listener.ready(observedPaused())
                        Player.STATE_ENDED -> listener.ended()
                    }
                }

                override fun onEvents(player: Player, events: Player.Events) {
                    if (!closed && events.containsAny(
                            Player.EVENT_PLAY_WHEN_READY_CHANGED,
                            Player.EVENT_PLAYBACK_SUPPRESSION_REASON_CHANGED,
                        )) {
                        listener.property("pause", observedPaused())
                    }
                }

                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    if (!closed) keepScreenOn(isPlaying)
                }

                override fun onTracksChanged(value: Tracks) {
                    if (closed) return
                    val unsupported =
                        when {
                            value.containsType(C.TRACK_TYPE_VIDEO) &&
                                !value.isTypeSupported(C.TRACK_TYPE_VIDEO) -> "video_decode_error"
                            value.containsType(C.TRACK_TYPE_AUDIO) &&
                                !value.isTypeSupported(C.TRACK_TYPE_AUDIO) -> "audio_decode_error"
                            else -> null
                        }
                    if (unsupported != null) {
                        listener.failure(unsupported)
                        return
                    }
                    subtitleTracksChanged(value)
                    listener.property("track-list", tracks.encode(value))
                }

                override fun onCues(cueGroup: CueGroup) {
                    subtitleCuesChanged(cueGroup.cues)
                }

                override fun onVideoSizeChanged(size: VideoSize) {
                    if (!closed) sizeChanged(size)
                }

                override fun onPlayerError(error: PlaybackException) {
                    if (closed) return
                    val (code, status) = Media3Failure.classify(error)
                    listener.failure(code, status)
                }
            }
        )
        player.addAnalyticsListener(
            object : AnalyticsListener {
                private var firstFrame = false

                override fun onRenderedFirstFrame(
                    time: AnalyticsListener.EventTime,
                    output: Any,
                    renderTimeMs: Long,
                ) {
                    if (!closed && !firstFrame) {
                        firstFrame = true
                        listener.firstFrame(player.currentPosition)
                    }
                }

                override fun onVideoDecoderInitialized(
                    time: AnalyticsListener.EventTime,
                    name: String,
                    timestamp: Long,
                    duration: Long,
                ) {
                    if (!closed) listener.property("hwdec-current", Media3Tracks.bounded(name))
                }

                override fun onVideoInputFormatChanged(
                    time: AnalyticsListener.EventTime,
                    format: Format,
                    reuse: androidx.media3.exoplayer.DecoderReuseEvaluation?,
                ) {
                    if (closed) return
                    listener.property("video-codec", Media3Tracks.codec(format))
                    listener.property("video-format", Media3Tracks.bounded(format.sampleMimeType))
                    listener.property("video-params", Media3Tracks.videoParams(format))
                }
            }
        )
        listener.property("current-vo", null)
        listener.property("hwdec-current", null)
        listener.property(
            "video-target-params",
            mapOf("gamma" to null, "primaries" to null, "pixelformat" to null),
        )
        player.setSeekParameters(SeekParameters.EXACT)
        player.setMediaSource(
            ProgressiveMediaSource.Factory(
                    source,
                    GuardedExtractorsFactory { fact ->
                        if (debug && fact["phase"] == "fragment-seek") {
                            val position = fact["position"] as Long
                            handler.post { if (!closed) listener.fragmentSeek(position) }
                        }
                        if (debug && fact["phase"] == "validate") {
                            val revision = fact["revision"] as Int
                            val accepted =
                                (fact["declaredVideo"] != true || fact["video"] == true) &&
                                    (fact["declaredAudio"] != true || fact["audio"] == true)
                            handler.post {
                                if (!closed) listener.sourceInitialization(revision, accepted)
                            }
                        }
                    }.apply { setSubtitleParserFactory(ssaParsers) },
                )
                .createMediaSource(MediaItem.fromUri(media.uri)),
            milliseconds(media.startSeconds),
        )
        player.playWhenReady = !media.paused
        listener.property("pause", media.paused)
        player.prepare()
        handler.post(progress)
    }

    override fun play() {
        player.play()
    }

    override fun pause() {
        player.pause()
    }

    override fun seek(seconds: Double, exact: Boolean) {
        player.setSeekParameters(if (exact) SeekParameters.EXACT else SeekParameters.PREVIOUS_SYNC)
        player.seekTo(milliseconds(seconds))
    }

    override fun select(type: String, id: Long?): Boolean {
        val nativeType =
            when (type) {
                "video" -> C.TRACK_TYPE_VIDEO
                "audio" -> C.TRACK_TYPE_AUDIO
                else -> C.TRACK_TYPE_TEXT
            }
        val target = id?.let { tracks.target(it) ?: return false }
        if (target != null && target.type != nativeType) return false
        val builder =
            player.trackSelectionParameters
                .buildUpon()
                .clearOverridesOfType(nativeType)
                .setTrackTypeDisabled(nativeType, target == null)
        if (target != null)
            builder.setOverrideForType(TrackSelectionOverride(target.group, target.index))
        player.trackSelectionParameters = builder.build()
        return true
    }

    override fun volume(value: Double) {
        player.volume = (value / 100).toFloat()
    }

    override fun release(complete: (Boolean) -> Unit) {
        if (released) {
            complete(true)
            return
        }
        val firstAttempt = !closed
        closed = true
        observer = null
        lastCues = emptyList()
        subtitleFormat = null
        ssaParsers.clear()
        handler.removeCallbacks(progress)
        http?.setDefaultRequestProperties(emptyMap())
        http = null
        val closingNetwork = client
        client = null
        if (firstAttempt) {
            releasingPlayer = true
            try {
                player.release()
                releaseReturned = true
            } catch (_: Exception) {
                // Retain cleanup ownership. A failed release call is not proof of teardown.
            } finally {
                releasingPlayer = false
            }
        }
        try {
            subtitles.setCues(emptyList())
        } catch (_: Exception) {
            if (debug) android.util.Log.d("LineupPlayer", "Subtitle clear skipped")
        } finally {
            keepScreenOn(false)
        }
        // Cancelling an in-flight call closes its socket (TLS close_notify). Never
        // perform this IO on the application looper or reply to stop/dispose before
        // it completes. Idle connections stay in the shared pool (see MediaHttp).
        // Media3's blocking-call deadline is not the teardown fence: its queued
        // release can finish just afterward. Wait for the actual playback thread
        // even after that deadline, and acknowledge only once it has terminated.
        // A later retry observes the same thread; it never calls release() again.
        val timedOutThisAttempt = firstAttempt && releaseTimedOut
        val returned = releaseReturned
        cleanupExecutor.execute {
            val decoderSuccess =
                if (returned) {
                    try {
                        playbackThread.join(1000)
                        !playbackThread.isAlive
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        false
                    }
                } else false
            val networkSuccess =
                try {
                    closingNetwork?.dispatcher?.cancelAll()
                    true
                } catch (_: Exception) {
                    false
                }
            handler.post {
                if (!networkSuccess) client = closingNetwork
                released = decoderSuccess && networkSuccess
                complete(released)
            }
        }
    }

    companion object {
        private val cleanupExecutor =
            java.util.concurrent.Executors.newSingleThreadExecutor { task ->
                Thread(task, "LineupMediaCleanup").apply { isDaemon = true }
            }
    }

    private fun milliseconds(seconds: Double): Long =
        (seconds * 1000).coerceAtMost(Long.MAX_VALUE.toDouble()).toLong()
}
