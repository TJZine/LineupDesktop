package com.tjzine.lineup

import android.view.KeyEvent

/**
 * One OS Back ingress. Modern Android owns Back through OnBackInvoked; TV key
 * copies must never also enter Flutter's keyboard path. Older Android owns a
 * completed physical press here and emits the same navigation route request.
 * No application/navigation policy or delayed-event credit lives in this class.
 */
internal class AndroidBackInput(
    private val systemBackCallbacks: Boolean,
    private val onLegacyBack: () -> Unit,
) {
    private data class Press(val deviceId: Int, val downTime: Long)
    private var press: Press? = null

    fun handle(event: KeyEvent): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_BACK) return false
        if (systemBackCallbacks) return true

        when (event.action) {
            KeyEvent.ACTION_DOWN -> if (event.repeatCount == 0) {
                press = Press(event.deviceId, event.downTime)
            }
            KeyEvent.ACTION_UP -> {
                val started = press
                press = null
                if (!event.isCanceled && started != null &&
                    started.deviceId == event.deviceId && started.downTime == event.downTime
                ) {
                    onLegacyBack()
                }
            }
        }
        return true
    }

    fun cancelPendingPress() {
        press = null
    }
}
