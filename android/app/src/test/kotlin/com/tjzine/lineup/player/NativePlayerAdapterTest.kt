package com.tjzine.lineup.player

import android.app.Activity
import android.graphics.Color
import android.view.SurfaceView
import android.view.View
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.SubtitleView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [30, 31])
class NativePlayerAdapterTest {
    private class Messenger : BinaryMessenger {
        var handler: BinaryMessenger.BinaryMessageHandler? = null
        var lastError: String? = null

        override fun send(channel: String, message: ByteBuffer?) {}

        override fun send(
            channel: String,
            message: ByteBuffer?,
            callback: BinaryMessenger.BinaryReply?,
        ) {}

        override fun setMessageHandler(
            channel: String,
            handler: BinaryMessenger.BinaryMessageHandler?,
        ) {
            if (channel == "lineup/native_player") this.handler = handler
        }

        fun call(method: String, arguments: Any? = null) {
            val message = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, arguments))
            message.rewind()
            lastError = null
            handler!!.onMessage(message) { response ->
                response?.rewind()
                try { StandardMethodCodec.INSTANCE.decodeEnvelope(response!!) }
                catch (error: io.flutter.plugin.common.FlutterException) { lastError = error.code }
            }
        }
    }

    private fun rect(width: Double, height: Double) =
        mapOf("left" to 0.0, "top" to 0.0, "width" to width, "height" to height, "scale" to 2.0)

    @Test
    fun emptyRectangleHidesTheSurfaceViewItselfSoItsSurfaceIsReleased() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val messenger = Messenger()
        val adapter = NativePlayerAdapter(activity, messenger)
        activity.setContentView(adapter.view)
        val video = (0 until adapter.view.childCount)
            .map(adapter.view::getChildAt)
            .filterIsInstance<SurfaceView>()
            .single()
        messenger.call("initialize")

        messenger.call("setVideoRect", rect(960.0, 540.0))
        assertEquals(View.VISIBLE, adapter.view.visibility)
        assertEquals(View.VISIBLE, video.visibility)

        // Leaving the player posts 0x0. A VISIBLE SurfaceView at 0x0 inside an
        // INVISIBLE container keeps a SurfaceControl that a later window stop
        // orphans (black video after Back/Home and reopen on API 30/31).
        messenger.call("setVideoRect", rect(0.0, 0.0))
        assertEquals(View.INVISIBLE, adapter.view.visibility)
        assertEquals(View.INVISIBLE, video.visibility)

        messenger.call("setVideoRect", rect(960.0, 540.0))
        assertEquals(View.VISIBLE, video.visibility)
        adapter.close()
    }

    @Test
    fun visibleRouteRectanglesKeepTheSurfaceUntilPlaybackIsActuallyHidden() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val messenger = Messenger()
        val adapter = NativePlayerAdapter(activity, messenger)
        activity.setContentView(adapter.view)
        val video = (0 until adapter.view.childCount)
            .map(adapter.view::getChildAt)
            .filterIsInstance<SurfaceView>()
            .single()
        messenger.call("initialize")

        // Flutter transfers the same native output between Player and Guide.
        // Only a real final hide sends zero; it must still release the view's
        // surface before a hidden window stop/start, as required by 91528805.
        repeat(10) {
            for ((width, height) in listOf(960.0 to 540.0, 320.0 to 180.0)) {
                messenger.call("setVideoRect", rect(width, height))
                assertEquals(View.VISIBLE, adapter.view.visibility)
                assertEquals(View.VISIBLE, video.visibility)
                assertEquals((width * 2).toInt(), video.layoutParams.width)
                assertEquals((height * 2).toInt(), video.layoutParams.height)
                assertEquals(adapter.view, video.parent)
            }
        }
        messenger.call("setVideoRect", rect(0.0, 0.0))
        assertEquals(View.INVISIBLE, video.visibility)
        adapter.releaseForBackground()
        messenger.call("setVideoRect", rect(960.0, 540.0))
        assertEquals(View.VISIBLE, video.visibility)
        adapter.close()
    }

    @Test
    fun textSubtitlesAreOutlinedWithoutABackgroundBox() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val adapter = NativePlayerAdapter(activity, Messenger())
        val subtitles = (0 until adapter.view.childCount)
            .map(adapter.view::getChildAt)
            .filterIsInstance<SubtitleView>()
            .single()
        // SubtitleView has no style getter; read the field setStyle assigns.
        val style = SubtitleView::class.java.getDeclaredField("style")
            .apply { isAccessible = true }
            .get(subtitles) as CaptionStyleCompat

        assertEquals(Color.WHITE, style.foregroundColor)
        assertEquals(Color.TRANSPARENT, style.backgroundColor)
        assertEquals(Color.TRANSPARENT, style.windowColor)
        assertEquals(CaptionStyleCompat.EDGE_TYPE_OUTLINE, style.edgeType)
        assertEquals(Color.BLACK, style.edgeColor)
        assertNull(style.typeface)
        adapter.close()
    }
    @Test
    fun presentationCorrectsSizeForLetterboxingAndDisposeResetsThePersistentView() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val messenger = Messenger()
        val adapter = NativePlayerAdapter(activity, messenger)
        val subtitles = (0 until adapter.view.childCount).map(adapter.view::getChildAt)
            .filterIsInstance<SubtitleView>().single()
        messenger.call("initialize")
        NativePlayerAdapter::class.java.getDeclaredField("videoSize").apply { isAccessible = true }
            .set(adapter, androidx.media3.common.VideoSize(2390, 1000))
        messenger.call("setSubtitlePresentation", mapOf("scale" to 2, "imageRaise" to 0, "lineupDrawsStyled" to false))
        for ((width, height) in listOf(960.0 to 540.0, 320.0 to 180.0)) {
            messenger.call("setVideoRect", rect(width, height))
            val fraction = SubtitleView::class.java.getDeclaredField("defaultTextSize")
                .apply { isAccessible = true }.getFloat(subtitles)
            assertEquals(0.0533f * 2 * (height * 2).toFloat() / subtitles.layoutParams.height, fraction, 0.00001f)
        }
        subtitles.setCues(listOf(androidx.media3.common.text.Cue.Builder().setText("fixture").build()))
        messenger.call("dispose")
        val style = SubtitleView::class.java.getDeclaredField("style").apply { isAccessible = true }.get(subtitles)
        assertEquals(CaptionStyleCompat.DEFAULT, style)
        assertEquals(SubtitleView.DEFAULT_TEXT_SIZE_FRACTION,
            SubtitleView::class.java.getDeclaredField("defaultTextSize").apply { isAccessible = true }.getFloat(subtitles))
        assertEquals(emptyList<Any>(), SubtitleView::class.java.getDeclaredField("cues").apply { isAccessible = true }.get(subtitles))
        adapter.close()
    }

    @Test
    @Config(shadows = [FailingSubtitleView::class])
    fun subtitleViewFailureCannotPreventDisposal() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val messenger = Messenger()
        val adapter = NativePlayerAdapter(activity, messenger)
        messenger.call("initialize")
        val subtitles = (0 until adapter.view.childCount).map(adapter.view::getChildAt)
            .filterIsInstance<SubtitleView>().single()
        org.robolectric.shadow.api.Shadow.extract<FailingSubtitleView>(subtitles).fail = true
        messenger.call("dispose")
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        assertNull(messenger.lastError)
        messenger.call("setSubtitlePresentation", mapOf("scale" to 1, "imageRaise" to 0, "lineupDrawsStyled" to false))
        assertEquals("not_initialized", messenger.lastError)
        adapter.close()
    }

    @org.robolectric.annotation.Implements(SubtitleView::class)
    class FailingSubtitleView : org.robolectric.shadows.ShadowViewGroup() {
        var fail = false
        @org.robolectric.annotation.Implementation
        fun setCues(cues: List<androidx.media3.common.text.Cue>?) {
            if (fail) throw IllegalStateException("fixture")
        }
    }

}
