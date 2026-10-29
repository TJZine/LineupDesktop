package com.tjzine.lineup.player

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import androidx.media3.common.*
import androidx.media3.common.text.Cue
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.SubtitleView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class Media3SubtitleRoutingTest {
    @Test fun switchesClearAndRerouteAndLivePresentationReappliesOriginalCues() {
        val context = RuntimeEnvironment.getApplication()
        val subtitles = SubtitleView(context)
        var presentation = SubtitlePresentation()
        lateinit var player: ExoPlayer
        val engine = Media3Engine(context, Handler(Looper.getMainLooper()), SurfaceView(context), subtitles, {}, {},
            { ExoPlayer.Builder(it).build().also { p -> player = p } }, { presentation })
        shadowOf(player.playbackLooper).unPause()
        val events = mutableListOf<Any?>()
        val listener = object : PlayerEngine.Listener {
            override fun ready(paused: Boolean) {}
            override fun ended() {}
            override fun failure(code: String, httpStatus: Int?) { fail(code) }
            override fun property(name: String, value: Any?) { if (name == "subtitle-cues") events.add(value) }
        }
        Media3Engine::class.java.getDeclaredField("observer").apply { isAccessible = true }.set(engine, listener)
        fun nativeCues() = SubtitleView::class.java.getDeclaredField("cues").apply { isAccessible = true }.get(subtitles) as List<*>
        fun track(mime: String) = Tracks(listOf(Tracks.Group(TrackGroup(Format.Builder().setSampleMimeType(mime).build()),
            false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true))))
        try {
            engine.subtitleTracksChanged(track("application/pgs"))
            val text = Cue.Builder().setText("Fixture dialogue").setTextSize(0.1f, Cue.TEXT_SIZE_TYPE_FRACTIONAL).build()
            engine.subtitleCuesChanged(listOf(text))
            assertEquals(1, nativeCues().size)
            events.clear()
            engine.subtitleTracksChanged(track("application/x-subrip"))
            assertTrue(nativeCues().isEmpty())
            assertEquals(emptyList<Any>(), events.first())
            assertEquals("Fixture dialogue", ((((events.last() as List<*>).single() as Map<*, *>)["lines"] as List<*>).single() as List<*>).single().let { (it as Map<*, *>)["text"] })
            engine.subtitleTracksChanged(track("text/x-ssa"))
            assertEquals(1, nativeCues().size)
            presentation = SubtitlePresentation(scale = 3f)
            engine.refreshSubtitles()
            assertEquals(0.3f, (nativeCues().single() as Cue).textSize, 0.0001f)
            engine.refreshSubtitles()
            assertEquals(0.3f, (nativeCues().single() as Cue).textSize, 0.0001f)
            presentation = SubtitlePresentation(lineupDrawsStyled = true)
            engine.refreshSubtitles()
            assertTrue(nativeCues().isEmpty())
            val bitmap = Cue.Builder().setBitmap(Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888)).build()
            engine.subtitleCuesChanged(listOf(text, bitmap))
            assertSame(bitmap, nativeCues().single())
            engine.subtitleTracksChanged(Tracks.EMPTY)
            assertTrue(nativeCues().isEmpty())
            assertEquals(emptyList<Any>(), events.last())
        } finally {
            var done = false
            engine.release { done = it }
            val until = System.nanoTime() + 5_000_000_000L
            while (!done && System.nanoTime() < until) { shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(5) }
            assertTrue(done)
        }
    }
}
