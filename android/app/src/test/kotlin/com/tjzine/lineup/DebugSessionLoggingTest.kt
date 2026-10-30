package com.tjzine.lineup

import androidx.media3.common.util.Log
import org.junit.Assert.assertEquals
import org.junit.Test

class DebugSessionLoggingTest {
    @Test
    fun onlyExplicitDebugLiveCaseSuppressesThirdPartyMediaLogs() {
        val original = Log.getLogLevel()
        try {
            Log.setLogLevel(Log.LOG_LEVEL_WARNING)
            DebugSessionLogging.configure(false, listOf("--case=session-live"))
            assertEquals(Log.LOG_LEVEL_WARNING, Log.getLogLevel())
            DebugSessionLogging.configure(true, listOf("--case=session-hls"))
            assertEquals(Log.LOG_LEVEL_WARNING, Log.getLogLevel())
            DebugSessionLogging.configure(true, emptyList())
            assertEquals(Log.LOG_LEVEL_WARNING, Log.getLogLevel())
            DebugSessionLogging.configure(true, listOf("--case=session-live"))
            assertEquals(Log.LOG_LEVEL_OFF, Log.getLogLevel())
        } finally {
            Log.setLogLevel(original)
        }
    }
}
