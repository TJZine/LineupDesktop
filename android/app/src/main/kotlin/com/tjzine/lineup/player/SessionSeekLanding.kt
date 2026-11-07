package com.tjzine.lineup.player

/** Receives the positioned seek marker and frame metadata on the playback looper. */
internal class SessionSeekLanding(private val landed: (Long) -> Unit) {
    private var pending: Pair<Long, Long>? = null

    fun reachedSeekTarget(id: Long, targetUs: Long) {
        pending = id to targetUs
    }

    fun frame(presentationTimeUs: Long, frameRate: Float) {
        val (id, targetUs) = pending ?: return
        val frameUs = if (frameRate.isFinite() && frameRate > 0f) {
            (1_000_000.0 / frameRate).toLong()
        } else 0L
        if (presentationTimeUs < targetUs - frameUs) return
        pending = null
        landed(id)
    }
}
