package com.tjzine.lineup

import android.app.Activity
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets

/** Activity-owned OS facts. A floating IME can be visible with zero inset size. */
class KeyboardVisibilityObserver(
    private val activity: Activity,
    private val onVisibilityChanged: (Boolean) -> Unit,
) : AutoCloseable {
    private var observer: View? = null
    private var lastVisibility: Boolean? = null
    private var closed = false

    fun watch(): Boolean {
        if (closed || Build.VERSION.SDK_INT < 30) return false
        if (observer == null) {
            val child = View(activity).apply {
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }
            observer = child
            child.setOnApplyWindowInsetsListener { view, insets ->
                // An unwatch/close retires even a queued callback from this view.
                if (!closed && observer === view) {
                    publish(insets.isVisible(WindowInsets.Type.ime()))
                }
                insets // Never replace Flutter's listener or consume its insets.
            }
            (activity.window.decorView as ViewGroup).addView(
                child, ViewGroup.LayoutParams(1, 1),
            )
        }
        activity.window.decorView.rootWindowInsets?.let {
            publish(it.isVisible(WindowInsets.Type.ime()))
        }
        observer?.requestApplyInsets()
        return true
    }

    private fun publish(visible: Boolean) {
        if (visible == lastVisibility) return
        lastVisibility = visible
        onVisibilityChanged(visible)
    }

    fun unwatch() {
        val child = observer
        observer = null
        lastVisibility = null
        child?.setOnApplyWindowInsetsListener(null)
        (child?.parent as? ViewGroup)?.removeView(child)
    }

    override fun close() {
        if (closed) return
        closed = true
        unwatch()
    }
}
