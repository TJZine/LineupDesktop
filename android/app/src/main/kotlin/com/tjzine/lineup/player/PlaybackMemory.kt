package com.tjzine.lineup.player

import android.app.ActivityManager
import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl

/**
 * Media3 buffer memory policy. Media3 1.11.1 sizes an HTTPS (streaming) load's
 * byte target from the selected track types: 131,072,000 bytes for video plus
 * 13,107,200 for audio (~138 MiB), held as 64 KiB Java-heap allocations. On a
 * low-RAM TV that competes with the app heap and swap. Low-RAM devices get an
 * explicit byte cap; all duration thresholds (start/rebuffer) stay at Media3
 * defaults so channel-switch start time is unchanged.
 */
@UnstableApi
internal object PlaybackMemory {
    /** 48 MiB ≈ 15 s of a 25 Mbps or ≈ 5 s of an 80 Mbps 4K remux. */
    const val LOW_RAM_TARGET_BUFFER_BYTES = 48 * 1024 * 1024
    private const val LOW_RAM_TOTAL_BYTES = 2L * 1024 * 1024 * 1024
    private const val MEBIBYTE = 1024 * 1024

    /** Null keeps Media3's track-based default. */
    fun targetBufferBytes(lowRamDevice: Boolean, totalMemBytes: Long, memoryClassMb: Int): Int? {
        if (!lowRamDevice && totalMemBytes >= LOW_RAM_TOTAL_BYTES) return null
        // Allocations live on the Java heap: never let the buffer claim more than
        // half of this app's heap class, nor less than Media3's own minimum.
        val heapBound = memoryClassMb.coerceAtLeast(1).toLong() * MEBIBYTE / 2
        return minOf(LOW_RAM_TARGET_BUFFER_BYTES.toLong(), heapBound)
            .coerceAtLeast(DefaultLoadControl.DEFAULT_MIN_BUFFER_SIZE.toLong())
            .toInt()
    }

    fun loadControl(context: Context): LoadControl {
        val manager = context.getSystemService(ActivityManager::class.java)
        val info = ActivityManager.MemoryInfo().also { manager.getMemoryInfo(it) }
        val target = targetBufferBytes(manager.isLowRamDevice, info.totalMem, manager.memoryClass)
        val builder = DefaultLoadControl.Builder()
        // prioritizeTimeOverSizeThresholds stays false (Media3's streaming default):
        // the byte cap stops loading, and a reached cap also permits playback start.
        if (target != null) builder.setTargetBufferBytes(target)
        return builder.build()
    }
}
