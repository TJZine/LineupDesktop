package com.tjzine.lineup

import androidx.media3.common.util.Log
import androidx.media3.common.util.UnstableApi

/** A live probe may hold capability URLs in third-party exception objects. */
@UnstableApi
internal object DebugSessionLogging {
    fun configure(debug: Boolean, arguments: List<String>) {
        if (debug && "--case=session-live" in arguments) Log.setLogLevel(Log.LOG_LEVEL_OFF)
    }
}
