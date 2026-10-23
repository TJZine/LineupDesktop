package com.tjzine.lineup.player

import org.junit.Assert.*
import org.junit.Test

class PlayerEventQueueTest {
    private fun event(id: Int, type: String) =
        QueuedEvent(1, null, mapOf("id" to id, "type" to type))

    @Test
    fun evictsOldestPropertyForAnyIncomingType() {
        val queue = PlayerEventQueue()
        repeat(256) { queue.add(event(it, if (it == 17) "property" else "state")) }
        queue.add(event(256, "stopResult"))
        val ids = generateSequence { queue.take() }.map { it.value["id"] }.toList()
        assertEquals(256, ids.size)
        assertFalse(ids.contains(17))
        assertEquals(0, ids.first())
        assertEquals(256, ids.last())
        assertFalse(queue.consumeOverflow())
    }

    @Test
    fun dropsIncomingPropertyWithoutDisplacingCompletions() {
        val queue = PlayerEventQueue()
        repeat(256) { queue.add(event(it, "trackResult")) }
        queue.add(event(999, "property"))
        assertEquals(256, queue.size)
        assertEquals(0, queue.take()!!.value["id"])
        assertFalse(queue.consumeOverflow())
    }

    @Test
    fun essentialOverflowEvictsOldestAndSignalsOnce() {
        val queue = PlayerEventQueue()
        repeat(256) { queue.add(event(it, "state")) }
        queue.add(event(256, "state"))
        assertEquals(1, queue.take()!!.value["id"])
        assertTrue(queue.consumeOverflow())
        assertFalse(queue.consumeOverflow())
        queue.clear()
        assertEquals(0, queue.size)
    }
}
