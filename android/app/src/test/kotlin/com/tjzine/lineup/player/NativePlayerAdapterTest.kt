package com.tjzine.lineup.player

import android.app.Activity
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [30])
class NativePlayerAdapterTest {
    private class Messenger : BinaryMessenger {
        var handler: BinaryMessenger.BinaryMessageHandler? = null

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
            handler!!.onMessage(message) {}
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
}
