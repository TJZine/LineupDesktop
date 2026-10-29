package com.tjzine.lineup.player

import org.junit.Assert.*
import org.junit.Test

class NativePlayerControllerTest {
    private class Engine : PlayerEngine {
        lateinit var listener: PlayerEngine.Listener
        var media: MediaLoad? = null
        var released = false
        var exact: Boolean? = null
        var selection = true
        var releaseFailures = 0
        var deferRelease = false
        var pendingRelease: ((Boolean) -> Unit)? = null
        var releaseCalls = 0

        override fun load(media: MediaLoad, listener: PlayerEngine.Listener) {
            this.media = media
            this.listener = listener
        }

        override fun play() {
            listener.property("pause", false)
        }

        override fun pause() {
            listener.property("pause", true)
        }

        override fun seek(seconds: Double, exact: Boolean) {
            this.exact = exact
        }

        override fun select(type: String, id: Long?) = selection

        override fun volume(value: Double) {}

        override fun release(complete: (Boolean) -> Unit) {
            releaseCalls++
            if (deferRelease) {
                pendingRelease = { success ->
                    if (success) {
                        released = true
                        media = null
                    }
                    complete(success)
                }
                return
            }
            if (releaseFailures > 0) {
                releaseFailures--
                complete(false)
                return
            }
            released = true
            media = null
            complete(true)
        }
    }

    private class Host : PlayerHost {
        val tasks = ArrayDeque<() -> Unit>()
        val events = mutableListOf<Map<String, Any?>>()
        val engines = mutableListOf<Engine>()
        val frames = mutableListOf<Triple<Long, Long, Long>>()
        var rectangle: VideoRect? = null
        var presentation: SubtitlePresentation? = null
        val presentationsAtCreation = mutableListOf<SubtitlePresentation?>()
        var rejectPresentation = false
        override fun subtitlePresentation(value: SubtitlePresentation?) {
            if (rejectPresentation) throw IllegalStateException("fixture")
            presentation = value
        }

        override fun firstFrame(generation: Long, loadId: Long, positionMs: Long) {
            frames.add(Triple(generation, loadId, positionMs))
        }

        override fun post(task: () -> Unit) {
            tasks.addLast(task)
        }

        override fun rect(rect: VideoRect) {
            rectangle = rect
        }

        override fun keepScreenOn(keep: Boolean) {}

        override fun createEngine() = Engine().also { engines.add(it); presentationsAtCreation.add(presentation) }

        override fun event(value: Map<String, Any?>) {
            events.add(value)
        }

        fun drain() {
            var budget = 10000
            while (tasks.isNotEmpty()) {
                check(--budget > 0)
                tasks.removeFirst()()
            }
        }
    }

    private class Result : NativePlayerController.Reply {
        var value: Any? = null
        var error: String? = null
        var done = false

        override fun success(value: Any?) {
            this.value = value
            done = true
        }

        override fun error(code: String) {
            error = code
            done = true
        }

        override fun notImplemented() {
            error = "notImplemented"
            done = true
        }
    }

    private val host = Host()
    private val controller = NativePlayerController(host)

    private fun call(method: String, args: Any? = null) =
        Result().also { controller.call(method, args, it) }

    private fun initialize() {
        assertEquals(
            mapOf(
                "clientApiVersion" to 1,
                "capabilities" to
                    mapOf(
                        "displayMatching" to false,
                        "fullscreen" to "fixed",
                    ),
            ),
            call("initialize").value,
        )
        host.drain()
        host.events.clear()
    }

    private fun load(id: Long = 1, extra: Map<String, Any?> = emptyMap()) =
        call("load", mapOf("uri" to "https://media.invalid/file", "loadId" to id) + extra)

    @Test
    fun lifetimeAndPlayerScopedSnapshots() {
        assertEquals("not_initialized", call("play").error)
        assertEquals("notImplemented", call("mystery").error)
        assertTrue(call("dispose").done)
        call("initialize")
        assertEquals(true, host.events.first()["fullscreen"])
        call("setFullscreen", mapOf("fullscreen" to false))
        assertEquals(true, host.events.last()["fullscreen"])
        val disposal = call("dispose")
        assertFalse(disposal.done)
        assertEquals("dispose_in_progress", call("dispose").error)
        assertEquals("initialize_failed", call("initialize").error)
        assertEquals("not_initialized", call("play").error)
        host.drain()
        assertTrue(disposal.done)
        assertTrue(call("dispose").done)
    }

    @Test
    fun strictLoadValidationAndCredentialRedaction() {
        initialize()
        for (extra in
            listOf(
                mapOf("startSeconds" to null),
                mapOf("startSeconds" to Double.NaN),
                mapOf("startSeconds" to -1),
                mapOf("startPaused" to "false"),
                mapOf("startPaused" to null),
                mapOf("loadId" to 1.0),
                mapOf("plexToken" to ""),
                mapOf("plexToken" to "space token"),
                mapOf("plexToken" to "é"),
                mapOf("plexToken" to "x".repeat(8193)),
                mapOf("uri" to "é".repeat(16385)),
                mapOf("uri" to "https://u:p@media.invalid/a"),
                mapOf("uri" to "https://media.invalid/a?%58-Plex-Token=secret"),
            )) {
            assertEquals(extra.keys.toString(), "invalid_argument", load(extra = extra).error)
        }
        assertEquals(
            "insecure_media_uri",
            load(extra = mapOf("uri" to "http://media.invalid/a", "plexToken" to "secret")).error,
        )
        assertEquals(
            "insecure_media_uri",
            load(extra = mapOf("uri" to "https:a", "plexToken" to "secret")).error,
        )
        assertNull(load(0, mapOf("plexToken" to "x".repeat(8192), "startSeconds" to 0)).error)
        host.drain()
        assertFalse(host.engines.single().media.toString().contains("https"))
        call("stop", mapOf("stopId" to 1))
        host.drain()
        assertNull(host.engines.single().media)
    }

    @Test
    fun readyOnceEvenPausedAndNeverReemittedForSeekOrResume() {
        initialize()
        load(extra = mapOf("startPaused" to true))
        host.drain()
        val engine = host.engines.single()
        engine.listener.ready(true)
        engine.listener.ready(false)
        call("seek", mapOf("seconds" to 13.25, "mode" to "keyframes"))
        host.drain()
        assertEquals(false, engine.exact)
        call("seek", mapOf("seconds" to 31.25))
        call("play")
        host.drain()
        assertEquals(true, engine.exact)
        val states = host.events.filter { it["type"] == "state" }
        assertEquals(listOf("loading", "playing"), states.map { it["state"] })
        assertEquals(true, states.last()["paused"])
        assertEquals(false, host.events.last()["value"])
    }

    @Test
    fun staleCallbacksQueuedEventsAndCommandsCannotRelabelSuccessor() {
        initialize()
        load()
        host.drain()
        val old = host.engines.single()
        old.listener.property("time-pos", 99.0)
        load(2)
        host.drain()
        val next = host.engines.last()
        old.listener.ready(false)
        old.listener.failure("container_error")
        old.listener.ended()
        next.listener.ready(false)
        host.drain()
        assertTrue(old.released)
        assertEquals(1, host.events.count { it["state"] == "playing" })
        assertEquals(2L, host.events.last()["loadId"])
        call("stop", mapOf("stopId" to 41))
        host.drain()
        next.listener.property("time-pos", 123.0)
        host.drain()
        assertEquals(
            mapOf("type" to "stopResult", "stopId" to 41L, "success" to true),
            host.events.last(),
        )
    }

    @Test
    fun queuedCallbacksRetireOnDisposeAndReinitializeCanAcceptBeforeOldPostRuns() {
        initialize()
        load()
        host.drain()
        val old = host.engines.single()
        old.listener.ready(false)
        call("pause")
        val disposal = call("dispose")
        // Deliver disposal ahead of an old scheduled command, as host cleanup can do.
        host.tasks.removeLast()()
        assertTrue(disposal.done)
        call("initialize")
        load(2)
        host.drain()
        old.listener.failure("network_error")
        host.drain()
        assertEquals(2, host.engines.size)
        assertFalse(host.events.any { it["state"] == "playing" })
    }

    @Test
    fun stopAndTrackCompletionHaveIndependentImmutableIds() {
        initialize()
        load()
        host.drain()
        call(
            "selectTrack",
            mapOf("type" to "subtitle", "id" to null, "loadId" to 1, "requestId" to 9),
        )
        host.drain()
        assertEquals(
            mapOf("type" to "trackResult", "loadId" to 1L, "requestId" to 9L, "success" to true),
            host.events.last(),
        )
        assertFalse(host.events.any { it["name"] == "track-list" })
        call("selectTrack", mapOf("type" to "audio", "id" to 2, "loadId" to 99, "requestId" to 10))
        host.drain()
        assertEquals(false, host.events.last()["success"])
        call("stop", mapOf("stopId" to 42))
        host.drain()
        assertEquals(42L, host.events.last()["stopId"])
    }

    @Test
    fun commandCountAndByteAdmissionAndDisposePurgeCredentials() {
        initialize()
        repeat(64) { assertNull(call("play").error) }
        assertEquals("command_queue_full", call("pause").error)
        host.drain()
        val large = "https://media.invalid/" + "x".repeat(32700)
        repeat(3) {
            assertNull(
                load(it.toLong(), mapOf("uri" to large, "plexToken" to "x".repeat(8192))).error
            )
        }
        assertEquals(
            "command_queue_full",
            load(extra = mapOf("uri" to large, "plexToken" to "x".repeat(8192))).error,
        )
        call("dispose")
        host.drain()
        assertTrue(host.engines.isEmpty())
        initialize()
        assertNull(load().error)
        host.drain()
        assertEquals(1, host.engines.size)
    }

    @Test
    fun displayRevisionsAndRectSurviveStop() {
        initialize()
        val display = mapOf("revision" to 3, "session" to true, "desired" to "hdr")
        assertNull(call("setDisplayMatching", display).error)
        assertEquals("invalid_argument", call("setDisplayMatching", display).error)
        host.drain()
        assertEquals("unavailable", host.events.last()["session"])
        val rect = mapOf("left" to -1, "top" to 2, "width" to 0, "height" to 20, "scale" to 2)
        assertNull(call("setVideoRect", rect).error)
        call("stop", mapOf("stopId" to 1))
        host.drain()
        assertEquals(0.0, host.rectangle!!.width, 0.0)
        assertEquals("invalid_argument", call("setVideoRect", rect + mapOf("scale" to 0)).error)
        call("dispose")
        host.drain()
        initialize()
        assertNull(call("setDisplayMatching", display + mapOf("revision" to 0)).error)
    }

    @Test
    fun errorsAreTerminalAndCannotPublishLaterReady() {
        initialize()
        load()
        host.drain()
        val engine = host.engines.single()
        engine.listener.failure("http_error", 401)
        engine.listener.ready(false)
        host.drain()
        assertEquals("error", host.events.last()["state"])
        assertEquals(401, host.events.last()["httpStatus"])
        assertTrue(engine.released)
    }

    @Test
    fun backgroundReleasesAndFencesMediaButAcceptsAResumedLoad() {
        initialize()
        load(extra = mapOf("plexToken" to "synthetic-secret"))
        host.drain()
        val old = host.engines.single()
        controller.releaseForBackground()
        host.drain()
        assertTrue(old.released)
        assertNull(old.media)
        assertEquals("stopped", host.events.last()["state"])
        old.listener.ready(false)
        host.drain()
        assertFalse(host.events.any { it["state"] == "playing" })
        assertNull(load(2).error)
        host.drain()
        host.engines.last().listener.ready(false)
        host.drain()
        assertEquals(2L, host.events.last()["loadId"])
    }

    @Test
    fun failedStopRetainsCleanupForRetryWithANewStopId() {
        initialize()
        load()
        host.drain()
        val engine = host.engines.single()
        engine.releaseFailures = 1
        call("stop", mapOf("stopId" to 10))
        host.drain()
        assertEquals(false, host.events.last()["success"])
        assertFalse(engine.released)
        assertNotNull(engine.media)
        call("stop", mapOf("stopId" to 11))
        host.drain()
        assertEquals(11L, host.events.last()["stopId"])
        assertEquals(true, host.events.last()["success"])
        assertTrue(engine.released)
        assertNull(engine.media)
    }

    @Test
    fun backgroundCompletesAdmittedStopAndFencesFrameDiagnostics() {
        initialize()
        load()
        host.drain()
        val old = host.engines.single()
        old.listener.firstFrame(100)
        call("stop", mapOf("stopId" to 11))
        controller.releaseForBackground()
        host.drain()
        assertTrue(host.events.any { it["stopId"] == 11L && it["success"] == true })
        load(2)
        host.drain()
        old.listener.firstFrame(999)
        host.engines.last().listener.firstFrame(200)
        assertEquals(listOf(1L, 2L), host.frames.map { it.second })
        assertEquals(listOf(100L, 200L), host.frames.map { it.third })
    }

    @Test
    fun firstCueAtOrdinaryCapacityPreservesCompletionsAndActiveLoad() {
        initialize()
        load()
        host.drain()
        host.events.clear()
        val engine = host.engines.single()
        repeat(255) {
            call("setDisplayMatching", mapOf("revision" to it, "session" to true, "desired" to "hdr"))
        }
        engine.listener.property("subtitle-cues", listOf("first"))
        engine.listener.property("subtitle-cues", emptyList<Any>())
        repeat(300) { engine.listener.property("time-pos", it.toDouble()) }
        host.drain()
        assertEquals((0L until 255L).toList(), host.events.filter { it["type"] == "display" }.map { it["revision"] })
        assertEquals(256, host.events.size)
        assertEquals("subtitle-cues", host.events.last()["name"])
        assertEquals(emptyList<Any>(), host.events.last()["value"])
        assertFalse(host.events.any { it["state"] == "error" })
        assertFalse(engine.released)
        engine.listener.ready(false)
        host.drain()
        assertEquals("playing", host.events.last()["state"])
    }

    @Test
    fun essentialEventOverflowFailsTheActiveLoad() {
        initialize()
        load()
        host.drain()
        repeat(256) {
            call(
                "setDisplayMatching",
                mapOf("revision" to it, "session" to true, "desired" to "hdr"),
            )
        }
        host.drain()
        assertEquals("event_queue_overflow", host.events.last()["failureCode"])
        assertTrue(host.engines.single().released)
    }

    @Test
    fun stopAndSuccessorWaitForActualAsyncCleanup() {
        initialize()
        load()
        host.drain()
        val engine = host.engines.single()
        engine.deferRelease = true
        call("stop", mapOf("stopId" to 12))
        load(2)
        host.drain()
        assertFalse(host.events.any { it["stopId"] == 12L })
        assertEquals(1, host.engines.size)
        engine.pendingRelease!!(true)
        host.drain()
        assertTrue(host.events.any { it["stopId"] == 12L && it["success"] == true })
        assertEquals(2, host.engines.size)
    }

    @Test
    fun disposeCoalescesInFlightCleanupAndRetiresQueuedSuccessor() {
        initialize()
        load()
        host.drain()
        val engine = host.engines.single()
        engine.deferRelease = true
        call("stop", mapOf("stopId" to 12))
        host.drain()
        load(2)
        val disposal = call("dispose")
        host.drain()
        assertFalse(disposal.done)
        assertEquals(1, engine.releaseCalls)
        assertEquals("dispose_in_progress", call("dispose").error)
        engine.pendingRelease!!(true)
        host.drain()
        assertTrue(disposal.done)
        assertEquals(1, host.engines.size)
        assertFalse(host.events.any { it["stopId"] == 12L })
        initialize()
        load(3)
        host.drain()
        assertEquals(2, host.engines.size)
    }

    @Test
    fun backgroundDuringReplacementCannotStartRetiredLoadAfterCleanup() {
        initialize()
        load()
        host.drain()
        val engine = host.engines.single()
        engine.deferRelease = true
        load(2)
        host.drain()
        controller.releaseForBackground()
        engine.pendingRelease!!(true)
        host.drain()
        assertEquals(1, host.engines.size)
        load(3)
        host.drain()
        assertEquals(2, host.engines.size)
    }

    @Test
    fun methodSpecificMalformedValuesAreRejected() {
        initialize()
        val cases =
            listOf(
                "seek" to mapOf("seconds" to null),
                "seek" to mapOf("seconds" to Double.POSITIVE_INFINITY),
                "seek" to mapOf("seconds" to 1, "mode" to "relative"),
                "seek" to mapOf("seconds" to 1, "mode" to null),
                "setVolume" to mapOf("volume" to 101),
                "setVolume" to mapOf("volume" to -1),
                "stop" to mapOf("stopId" to 0),
                "setFullscreen" to mapOf("fullscreen" to 1),
                "selectTrack" to mapOf("type" to "sub", "id" to 1, "loadId" to 1, "requestId" to 1),
                "selectTrack" to
                    mapOf("type" to "audio", "id" to 0, "loadId" to 1, "requestId" to 1),
                "selectTrack" to
                    mapOf("type" to "audio", "id" to 1, "loadId" to 0, "requestId" to 1),
            )
        cases.forEach { (method, args) ->
            assertEquals(method, "invalid_argument", call(method, args).error)
        }
    }
    @Test fun presentationBypassesFullQueueAppliesBeforeEngineAndResetsOnDispose() {
        val host = Host()
        val controller = NativePlayerController(host)
        fun call(method: String, args: Any? = null): Result = Result().also { controller.call(method, args, it) }
        val args = mapOf("scale" to 3L, "imageRaise" to 0.25, "lineupDrawsStyled" to true)
        assertEquals("not_initialized", call("setSubtitlePresentation", args).error)
        call("initialize")
        repeat(64) { call("pause") }
        assertNull(call("setSubtitlePresentation", args).error)
        assertEquals(3f, host.presentation!!.scale)
        assertEquals("invalid_argument", call("setSubtitlePresentation", args + ("scale" to 5)).error)
        assertEquals(3f, host.presentation!!.scale)
        host.drain()
        call("load", mapOf("uri" to "https://fixture.invalid/media.mkv", "loadId" to 1L))
        host.drain()
        assertEquals(SubtitlePresentation(3f, 0.25f, true), host.presentationsAtCreation.single())
        call("dispose")
        assertNull(host.presentation)
        host.drain()
    }

    @Test fun subtitleApplyExceptionReturnsCommandErrorWithoutFailingTheActiveLoad() {
        val host = Host()
        val controller = NativePlayerController(host)
        fun call(method: String, args: Any? = null): Result = Result().also { controller.call(method, args, it) }
        call("initialize")
        call("load", mapOf("uri" to "https://fixture.invalid/media.mkv", "loadId" to 1L))
        host.drain()
        host.events.clear()
        host.rejectPresentation = true
        assertEquals("native_command_error", call("setSubtitlePresentation",
            mapOf("scale" to 1, "imageRaise" to 0, "lineupDrawsStyled" to false)).error)
        host.drain()
        assertFalse(host.engines.single().released)
        assertTrue(host.events.isEmpty())
    }

}
