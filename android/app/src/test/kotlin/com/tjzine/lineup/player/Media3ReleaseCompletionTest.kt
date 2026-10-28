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
class Media3ReleaseCompletionTest {
    @Test
    fun internalCallTimeoutCanCompleteWithinTheActualTeardownFence() {
        val context = RuntimeEnvironment.getApplication()
        val handler = Handler(Looper.getMainLooper())
        val timeout = CountDownLatch(1)
        lateinit var player: ExoPlayer
        val engine = Media3Engine(context, handler, SurfaceView(context), SubtitleView(context), {}, {}, {
            ExoPlayer.Builder(it).setClock(object : Clock by Clock.DEFAULT {
                override fun elapsedRealtime() = TimeUnit.NANOSECONDS.toMillis(System.nanoTime())
            }).setReleaseTimeoutMs(20).build().also { value ->
                player = value
                value.addListener(object : Player.Listener {
                    override fun onPlayerError(error: PlaybackException) {
                        if (error.errorCode == PlaybackException.ERROR_CODE_TIMEOUT &&
                            (error.cause as? ExoTimeoutException)?.timeoutOperation == ExoTimeoutException.TIMEOUT_OPERATION_RELEASE) {
                            timeout.countDown()
                        }
                    }
                })
            }
        })
        val playbackThread = player.playbackLooper.thread
        shadowOf(player.playbackLooper).unPause()
        val entered = CountDownLatch(1)
        val finishTeardown = CountDownLatch(1)
        Handler(player.playbackLooper).post {
            entered.countDown()
            finishTeardown.await()
        }
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val finisher = Thread {
            if (timeout.await(5, TimeUnit.SECONDS)) {
                // Keep the real release call over its deadline, then let Media3
                // finish its real queued teardown within our worker's fence.
                Thread.sleep(50)
                finishTeardown.countDown()
            }
        }.apply { start() }
        try {
            var result: Boolean? = null
            engine.release { result = it }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (result == null && System.nanoTime() < deadline) {
                shadowOf(Looper.getMainLooper()).idle()
                Thread.sleep(5)
            }
            assertEquals("the real library release call must time out", 0L, timeout.count)
            assertEquals("acknowledge completed teardown rather than a past call deadline", true, result)
            assertFalse("a successful acknowledgement must fence the playback thread", playbackThread.isAlive)
        } finally {
            finishTeardown.countDown()
            finisher.join(5000)
            playbackThread.join(5000)
        }
    }
}
