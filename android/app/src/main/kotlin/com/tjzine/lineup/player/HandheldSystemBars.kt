package com.tjzine.lineup.player

import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowInsets
import android.view.WindowInsetsController

/** Controls only Android's bars. The app decides when to request immersive mode. */
@Suppress("DEPRECATION")
internal class HandheldSystemBars(private val window: Window) {
    private val decor get() = window.decorView
    private var insetView: View? = null

    fun observe(publish: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT >= 30) {
            // The activity content view dispatches on to Flutter and the video layer.
            // Leave that dispatch intact so their layout still receives the insets.
            val content = window.findViewById<View>(android.R.id.content)
            insetView = content
            content.setOnApplyWindowInsetsListener { view, insets ->
                publish(fullscreen(insets))
                view.onApplyWindowInsets(insets)
            }
            content.requestApplyInsets()
        } else {
            decor.setOnSystemUiVisibilityChangeListener { flags ->
                publish(fullscreen(flags))
            }
        }
        observedFullscreen()?.let(publish)
    }

    fun observedFullscreen(): Boolean? =
        if (Build.VERSION.SDK_INT >= 30) decor.rootWindowInsets?.let(::fullscreen)
        else fullscreen(decor.windowSystemUiVisibility)

    fun setFullscreen(fullscreen: Boolean) {
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            val controller = checkNotNull(window.insetsController)
            controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (fullscreen) controller.hide(WindowInsets.Type.systemBars())
            else controller.show(WindowInsets.Type.systemBars())
        } else {
            // Retain edge-to-edge layout when explicitly clearing the immersive bits.
            decor.systemUiVisibility =
                (decor.systemUiVisibility and HIDE_FLAGS.inv()) or LAYOUT_FLAGS or
                    (if (fullscreen) HIDE_FLAGS else 0)
        }
    }

    fun close() {
        insetView?.setOnApplyWindowInsetsListener(null)
        insetView = null
        if (Build.VERSION.SDK_INT < 30) decor.setOnSystemUiVisibilityChangeListener(null)
    }

    private fun fullscreen(insets: WindowInsets): Boolean =
        !insets.isVisible(WindowInsets.Type.statusBars()) &&
            !insets.isVisible(WindowInsets.Type.navigationBars())

    private fun fullscreen(flags: Int): Boolean =
        flags and BAR_FLAGS == BAR_FLAGS

    private companion object {
        const val BAR_FLAGS = View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
        const val HIDE_FLAGS = BAR_FLAGS or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        const val LAYOUT_FLAGS = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
    }
}
