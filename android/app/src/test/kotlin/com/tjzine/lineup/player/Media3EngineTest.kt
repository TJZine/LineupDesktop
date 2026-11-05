package com.tjzine.lineup.player

import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.Clock
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.ExoTimeoutException
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.ui.SubtitleView
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class Media3EngineTest {
    private val context = RuntimeEnvironment.getApplication()
    private val handler = Handler(Looper.getMainLooper())

    private fun engine(createPlayer: (android.content.Context) -> ExoPlayer) =
        Media3Engine(
            context,
            handler,
            SurfaceView(context),
            SubtitleView(context),
            {},
            {},
            createPlayer,
        )

    private fun release(engine: Media3Engine): Boolean {
        var result: Boolean? = null
        engine.release { result = it }
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (result == null && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(5)
        }
        assertNotNull("release callback must be bounded", result)
        return result!!
    }

    private val listener = object : PlayerEngine.Listener {
        override fun ready(paused: Boolean) {}
        override fun ended() {}
        override fun failure(code: String, httpStatus: Int?) {}
        override fun property(name: String, value: Any?) {}
    }

    @Test
    fun initialPreparationUsesScheduledJoinSourceAtRequestedPosition() {
        lateinit var player: ExoPlayer
        var source: MediaSource? = null
        val engine = engine {
            player = ExoPlayer.Builder(it).build()
            object : ExoPlayer by player {
                override fun setMediaSource(mediaSource: MediaSource, startPositionMs: Long) {
                    source = mediaSource
                    player.setMediaSource(mediaSource, startPositionMs)
                }
            }
        }
        shadowOf(player.playbackLooper).unPause()
        try {
            engine.load(MediaLoad("https://127.0.0.1:9/synthetic", 1, null, true, 42.5), listener)
            assertTrue(source is InitialJoinMediaSource)
            assertEquals(42_500L, player.currentPosition)
            assertFalse(player.playWhenReady)
        } finally {
            release(engine)
        }
    }

    @Test
    fun explicitSeeksReplaceInitialToleranceWithExactOrPreviousSync() {
        lateinit var player: ExoPlayer
        val engine = engine { ExoPlayer.Builder(it).build().also { value -> player = value } }
        shadowOf(player.playbackLooper).unPause()
        try {
            engine.load(MediaLoad("https://127.0.0.1:9/synthetic", 1, null, true, 42.5), listener)
            for (exact in listOf(true, false, true)) {
                engine.seek(12.75, exact)
                assertEquals(if (exact) SeekParameters.EXACT else SeekParameters.PREVIOUS_SYNC,
                    player.seekParameters)
                assertEquals(12_750L, player.currentPosition)
            }
        } finally {
            release(engine)
        }
    }

    @Test
    fun movieAudioFocusPausesTransientlyAndPermanentlyThroughObservedPauseEvents() {
        lateinit var player: ExoPlayer
        val engine = engine { ExoPlayer.Builder(it).build().also { value -> player = value } }
        shadowOf(player.playbackLooper).unPause()
        try {
            assertEquals(androidx.media3.common.C.USAGE_MEDIA, player.audioAttributes.usage)
            assertEquals(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MOVIE, player.audioAttributes.contentType)
            val pauses = mutableListOf<Boolean>()
            engine.load(MediaLoad("https://127.0.0.1:9/synthetic", 1, null, false, 0.0),
                object : PlayerEngine.Listener {
                    override fun ready(paused: Boolean) {}
                    override fun ended() {}
                    override fun failure(code: String, httpStatus: Int?) {}
                    override fun property(name: String, value: Any?) {
                        if (name == "pause") pauses += value as Boolean
                    }
                })
            // Replace networking with Media3's real in-memory silent media source.
            player.setMediaSource(androidx.media3.exoplayer.source.SilenceMediaSource.Factory()
                .setDurationUs(60_000_000).createMediaSource())
            player.prepare()
            player.play()
            fun settle(until: () -> Boolean) {
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
                while (!until() && System.nanoTime() < deadline) {
                    shadowOf(Looper.getMainLooper()).idle()
                    Thread.sleep(5)
                }
                assertTrue("Media3 callback must arrive", until())
            }
            val audio = shadowOf(context.getSystemService(android.content.Context.AUDIO_SERVICE)
                as android.media.AudioManager)
            settle { audio.lastAudioFocusRequest != null }
            val callback = audio.lastAudioFocusRequest.listener
            assertNotNull(callback)
            callback.onAudioFocusChange(android.media.AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK)
            val duckHandled = CountDownLatch(1)
            Handler(player.playbackLooper).post { duckHandled.countDown() }
            assertTrue(duckHandled.await(5, TimeUnit.SECONDS))
            shadowOf(Looper.getMainLooper()).idle()
            assertTrue("can-duck keeps play intent", player.playWhenReady)
            assertEquals(Player.PLAYBACK_SUPPRESSION_REASON_NONE, player.playbackSuppressionReason)
            assertNotEquals(true, pauses.lastOrNull())
            callback.onAudioFocusChange(android.media.AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
            settle { pauses.lastOrNull() == true }
            assertTrue("transient suppression retains play intent", player.playWhenReady)
            callback.onAudioFocusChange(android.media.AudioManager.AUDIOFOCUS_GAIN)
            settle { pauses.lastOrNull() == false }
            callback.onAudioFocusChange(android.media.AudioManager.AUDIOFOCUS_LOSS)
            settle { !player.playWhenReady && pauses.lastOrNull() == true }
            callback.onAudioFocusChange(android.media.AudioManager.AUDIOFOCUS_GAIN)
            shadowOf(Looper.getMainLooper()).idle()
            assertFalse("permanent loss requires explicit resume", player.playWhenReady)
            engine.play()
            settle { player.playWhenReady && pauses.lastOrNull() == false }
        } finally {
            release(engine)
        }
    }

    @Test
    fun realMedia3ReleaseTimeoutRetainsOwnershipUntilPlaybackThreadFinishes() {
        lateinit var player: ExoPlayer
        var timeoutObserved = false
        val engine = engine {
            ExoPlayer.Builder(it)
                // Robolectric freezes Android elapsed time; use a real elapsed clock
                // so the actual library's blocking release deadline can expire.
                .setClock(
                    object : Clock by Clock.DEFAULT {
                        override fun elapsedRealtime() =
                            TimeUnit.NANOSECONDS.toMillis(System.nanoTime())
                    }
                )
                .setReleaseTimeoutMs(20)
                .build()
                .also { value ->
                    player = value
                    value.addListener(
                        object : Player.Listener {
                            override fun onPlayerError(error: PlaybackException) {
                                timeoutObserved =
                                    error.errorCode == PlaybackException.ERROR_CODE_TIMEOUT &&
                                        (error.cause as? ExoTimeoutException)?.timeoutOperation ==
                                            ExoTimeoutException.TIMEOUT_OPERATION_RELEASE
                            }
                        }
                    )
                }
        }
        val playbackThread = player.playbackLooper.thread
        shadowOf(player.playbackLooper).unPause()
        val entered = CountDownLatch(1)
        val unblock = CountDownLatch(1)
        Handler(player.playbackLooper).post {
            entered.countDown()
            unblock.await()
        }
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        try {
            assertFalse(release(engine))
            assertTrue("the real library must emit its release timeout", timeoutObserved)
            assertTrue(playbackThread.isAlive)
            // Media3 itself now reports released, and a second release is a no-op.
            // Neither is a valid fence while its queued teardown is still blocked.
            assertTrue(player.isReleased)
            player.release()
            assertFalse(release(engine))
            assertTrue(playbackThread.isAlive)
        } finally {
            unblock.countDown()
        }
        playbackThread.join(5000)
        assertFalse("actual Media3 teardown must terminate its thread", playbackThread.isAlive)
        assertTrue(release(engine))
        assertTrue(release(engine))
    }

    @Test
    fun ordinaryReleaseWaitsForActualPlaybackThreadAndClearsAwakeState() {
        lateinit var player: ExoPlayer
        var awake = true
        val engine =
            Media3Engine(
                context,
                handler,
                SurfaceView(context),
                SubtitleView(context),
                {},
                { awake = it },
                { ExoPlayer.Builder(it).build().also { value -> player = value } },
            )
        shadowOf(player.playbackLooper).unPause()
        assertTrue(release(engine))
        assertFalse(player.playbackLooper.thread.isAlive)
        assertFalse(awake)
    }
    @Test
    fun explicitSessionUsesHlsAndDirectKeepsGuardedProgressiveSource() {
        val factory = androidx.media3.datasource.okhttp.OkHttpDataSource.Factory(MediaHttp.forLoad())
        val direct = MediaLoad("https://session.invalid/index.m3u8", 1, null, false, 0.0)
        assertTrue(Media3Engine.createSource(direct, factory, GuardedExtractorsFactory {}) is
            InitialJoinMediaSource)
        assertTrue(Media3Engine.createSource(direct.copy(kind = LoadKind.plexSession), factory,
            GuardedExtractorsFactory {}) is androidx.media3.exoplayer.hls.HlsMediaSource)
    }

    @Test
    fun sessionPreparationUsesPlaylistDefaultWhileDirectKeepsExplicitPosition() {
        for (kind in listOf(LoadKind.direct, LoadKind.plexSession)) {
            lateinit var actual: ExoPlayer
            var preparation: List<Any?>? = null
            val engine = engine { context ->
                actual = ExoPlayer.Builder(context).build()
                java.lang.reflect.Proxy.newProxyInstance(
                    ExoPlayer::class.java.classLoader,
                    arrayOf(ExoPlayer::class.java),
                ) { _, method, args ->
                    when (method.name) {
                        "setMediaSource" -> { preparation = args!!.toList(); null }
                        // Record preparation at the player boundary without starting network IO.
                        "prepare" -> null
                        else -> method.invoke(actual, *(args ?: emptyArray()))
                    }
                } as ExoPlayer
            }
            shadowOf(actual.playbackLooper).unPause()
            try {
                engine.load(MediaLoad("https://session.invalid/index.m3u8", 1, null, false, 13.25, kind),
                    object : PlayerEngine.Listener {
                        override fun ready(paused: Boolean) {}
                        override fun ended() {}
                        override fun failure(code: String, httpStatus: Int?) { fail(code) }
                        override fun property(name: String, value: Any?) {}
                    })
                val args = preparation!!
                if (kind == LoadKind.plexSession) {
                    assertEquals("session must preserve manifest default start", 1, args.size)
                    assertTrue(args[0] is androidx.media3.exoplayer.hls.HlsMediaSource)
                } else {
                    assertEquals(2, args.size)
                    assertTrue(args[0] is InitialJoinMediaSource)
                    assertEquals(13250L, args[1])
                }
            } finally {
                assertTrue(release(engine))
            }
        }
    }

}
