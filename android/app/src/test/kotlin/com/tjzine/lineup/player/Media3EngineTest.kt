package com.tjzine.lineup.player

import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.Clock
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.ExoTimeoutException
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
}
