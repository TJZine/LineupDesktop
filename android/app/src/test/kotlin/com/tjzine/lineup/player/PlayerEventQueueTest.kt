package com.tjzine.lineup.player

import org.junit.Assert.*
import org.junit.Test

class PlayerEventQueueTest {
    private fun event(id: Int, type: String) =
        QueuedEvent(1, null, mapOf("id" to id, "type" to type))

    private fun cues(value: List<String>) =
        QueuedEvent(1, null, mapOf("type" to "property", "name" to "subtitle-cues", "value" to value))

    @Test
    fun clearSlotBecomesCurrentCueBeforeSelectedTrackSnapshotAtCapacity() {
        val queue = PlayerEventQueue()
        repeat(127) { queue.add(event(it, "trackResult")) }
        queue.add(cues(emptyList()))
        queue.add(QueuedEvent(1, null, mapOf("id" to 127, "type" to "property",
            "name" to "track-list", "value" to listOf(mapOf("id" to 1, "selected" to true)))))
        repeat(127) { queue.add(event(128 + it, "stopResult")) }
        // The later current cue replaces the clear in its existing FIFO slot.
        queue.add(cues(listOf("fixture current cue")))
        assertEquals(256, queue.size) // 255 ordinary + one reserved cue
        val events = generateSequence { queue.take() }.toList()
        assertEquals((0 until 255).toList(),
            events.filter { it.value["name"] != "subtitle-cues" }.map { it.value["id"] })
        assertEquals("subtitle-cues", events[127].value["name"])
        assertEquals(listOf("fixture current cue"), events[127].value["value"])
        assertEquals("track-list", events[128].value["name"])
        assertFalse(queue.consumeOverflow())
    }

    @Test
    fun firstCueUsesReservedSlotWithoutLosingCompletions() {
        val queue = PlayerEventQueue()
        repeat(255) { queue.add(event(it, if (it % 2 == 0) "trackResult" else "state")) }
        queue.add(cues(listOf("first")))
        assertEquals(256, queue.size)
        queue.add(cues(listOf("replacement")))
        queue.add(cues(emptyList()))
        repeat(300) { queue.add(event(1000 + it, "property")) }
        val events = generateSequence { queue.take() }.toList()
        assertEquals((0 until 255).toList(), events.dropLast(1).map { it.value["id"] })
        assertEquals("subtitle-cues", events.last().value["name"])
        assertEquals(emptyList<String>(), events.last().value["value"])
        assertFalse(queue.consumeOverflow())
    }

    @Test
    fun pendingCueKeepsItsPositionDuringReplacementAndOrdinaryOverflow() {
        val queue = PlayerEventQueue()
        repeat(127) { queue.add(event(it, "trackResult")) }
        queue.add(cues(listOf("first")))
        repeat(128) { queue.add(event(127 + it, "state")) }
        queue.add(cues(emptyList()))
        val beforeOverflow = mutableListOf<QueuedEvent>()
        repeat(127) { beforeOverflow.add(queue.take()!!) }
        assertEquals((0 until 127).toList(), beforeOverflow.map { it.value["id"] })
        assertEquals(emptyList<String>(), queue.take()!!.value["value"])

        queue.clear()
        repeat(127) { queue.add(event(it, "trackResult")) }
        queue.add(cues(listOf("first")))
        repeat(128) { queue.add(event(127 + it, "state")) }
        queue.add(event(999, "stopResult"))
        queue.add(cues(emptyList()))
        val events = generateSequence { queue.take() }.toList()
        assertEquals(256, events.size)
        assertEquals("subtitle-cues", events[126].value["name"])
        assertEquals(emptyList<String>(), events[126].value["value"])
        assertEquals((1 until 255).toList() + 999, events.filter { it.value["name"] != "subtitle-cues" }.map { it.value["id"] })
        assertTrue(queue.consumeOverflow())
    }

    @Test
    fun evictsOldestPropertyForAnyIncomingType() {
        val queue = PlayerEventQueue()
        repeat(255) { queue.add(event(it, if (it == 17) "property" else "state")) }
        queue.add(event(255, "stopResult"))
        val ids = generateSequence { queue.take() }.map { it.value["id"] }.toList()
        assertEquals(255, ids.size)
        assertFalse(ids.contains(17))
        assertEquals(0, ids.first())
        assertEquals(255, ids.last())
        assertFalse(queue.consumeOverflow())
    }

    @Test
    fun dropsIncomingPropertyWithoutDisplacingCompletions() {
        val queue = PlayerEventQueue()
        repeat(255) { queue.add(event(it, "trackResult")) }
        queue.add(event(999, "property"))
        assertEquals(255, queue.size)
        assertEquals(0, queue.take()!!.value["id"])
        assertFalse(queue.consumeOverflow())
    }

    @Test
    fun essentialOverflowEvictsOldestAndSignalsOnce() {
        val queue = PlayerEventQueue()
        repeat(255) { queue.add(event(it, "state")) }
        queue.add(event(255, "state"))
        assertEquals(1, queue.take()!!.value["id"])
        assertTrue(queue.consumeOverflow())
        assertFalse(queue.consumeOverflow())
        queue.clear()
        assertEquals(0, queue.size)
    }
}
