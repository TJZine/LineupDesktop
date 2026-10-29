package com.tjzine.lineup.player

/** Protocol/lifetime owner. Calls and completion callbacks use the application looper. */
internal class NativePlayerController(private val host: PlayerHost) {
    interface Reply {
        fun success(value: Any? = null)

        fun error(code: String)

        fun notImplemented()
    }

    private var initialized = false
    private var disposing = false
    private var generation = 0L
    private var epoch = 0L
    private var controlRevision = 0L
    private var displayRevision = -1L
    private var current: Session? = null
    private var cleanupEngine: PlayerEngine? = null
    private val cleanupWaiters = mutableListOf<(Boolean) -> Unit>()
    private var cleanupRunning = false
    private var volume = 100.0
    private val commands = ArrayDeque<PlayerCommand>()
    private var queuedBytes = 0
    private var commandPosted = false
    private var activeCommand: Long? = null
    private var nextCommand = 0L
    private val events = PlayerEventQueue()
    private var eventPosted = false

    private class Session(
        val generation: Long,
        val epoch: Long,
        val loadId: Long,
        val engine: PlayerEngine,
    ) {
        var ready = false
        var terminal = false
    }

    fun call(method: String, arguments: Any?, reply: Reply) {
        if (method !in methods) {
            reply.notImplemented()
            return
        }
        try {
            when (method) {
                "initialize" -> {
                    if (disposing) throw ProtocolError("initialize_failed")
                    if (!initialized) {
                        generation++
                        epoch++
                        displayRevision = -1
                        events.clear()
                        initialized = true
                        queue(mapOf("type" to "fullscreen", "fullscreen" to true))
                        queue(
                            mapOf(
                                "type" to "state",
                                "state" to "idle",
                                "message" to "Native Android player ready",
                            )
                        )
                    }
                    drainEvents()
                    reply.success(mapOf("clientApiVersion" to 1))
                }
                "dispose" -> dispose(reply)
                else -> {
                    if (!initialized || disposing) throw ProtocolError("not_initialized")
                    when (method) {
                        "setSubtitlePresentation" -> {
                            host.subtitlePresentation(PlayerProtocol.subtitlePresentation(arguments))
                            reply.success()
                        }
                        "setVideoRect" -> {
                            host.rect(PlayerProtocol.rect(arguments))
                            reply.success()
                        }
                        "setFullscreen" -> {
                            PlayerProtocol.boolean(PlayerProtocol.map(arguments)["fullscreen"])
                            queue(mapOf("type" to "fullscreen", "fullscreen" to true))
                            drainEvents()
                            reply.success()
                        }
                        "setDisplayMatching" -> {
                            val a = PlayerProtocol.map(arguments)
                            val revision = PlayerProtocol.integer(a["revision"], 0)
                            PlayerProtocol.boolean(a["session"])
                            if (
                                a["desired"] !in listOf("hdr", "sdr", "unknown") ||
                                    revision <= displayRevision
                            )
                                throw ProtocolError("invalid_argument")
                            displayRevision = revision
                            queue(
                                mapOf(
                                    "type" to "display",
                                    "revision" to revision,
                                    "session" to "unavailable",
                                    "observed" to "unknown",
                                    "outcome" to "failed",
                                    "wrote" to false,
                                    "owned" to false,
                                    "reason" to "unsupported_api",
                                    "route" to "none",
                                    "activeColorMode" to null,
                                )
                            )
                            reply.success()
                        }
                        else -> {
                            val command = PlayerProtocol.command(method, arguments)
                            val bytes =
                                (command as? PlayerCommand.Load)?.media?.credentialBytes ?: 0
                            if (commands.size >= 64 || queuedBytes + bytes > 128 * 1024)
                                throw ProtocolError("command_queue_full")
                            commands.addLast(command)
                            queuedBytes += bytes
                            postCommands()
                            reply.success()
                        }
                    }
                }
            }
        } catch (e: ProtocolError) {
            reply.error(e.code)
        } catch (_: Exception) {
            reply.error(if (method == "initialize") "initialize_failed" else "native_command_error")
        }
    }

    private fun postCommands() {
        if (commandPosted || activeCommand != null || commands.isEmpty() || !initialized) return
        commandPosted = true
        val owner = generation
        host.post {
            if (owner != generation || !initialized) return@post
            commandPosted = false
            if (activeCommand != null || commands.isEmpty()) return@post
            val command = commands.removeFirst()
            queuedBytes -= (command as? PlayerCommand.Load)?.media?.credentialBytes ?: 0
            val serial = ++nextCommand
            activeCommand = serial
            execute(command) {
                if (activeCommand == serial) {
                    activeCommand = null
                    postCommands()
                }
            }
        }
    }

    private fun execute(command: PlayerCommand, done: () -> Unit) {
        val owner = generation
        val revision = controlRevision
        when (command) {
            is PlayerCommand.Load ->
                retire { success ->
                    if (owner != generation || revision != controlRevision || !initialized) {
                        done()
                        return@retire
                    }
                    if (!success) {
                        loadError(command.media.loadId, "command_error")
                        done()
                        return@retire
                    }
                    try {
                        val session =
                            Session(generation, epoch, command.media.loadId, host.createEngine())
                        current = session
                        state(session, "loading", "Loading media")
                        session.engine.volume(volume)
                        session.engine.load(command.media, listener(session))
                    } catch (_: Exception) {
                        val session = current
                        if (session != null) fail(session, "native_error")
                        else loadError(command.media.loadId, "native_error")
                    }
                    done()
                }
            is PlayerCommand.Stop -> {
                val oldId = current?.loadId
                retire { success ->
                    if (owner == generation && initialized) {
                        if (success && oldId != null)
                            queue(
                                mapOf(
                                    "type" to "state",
                                    "state" to "stopped",
                                    "message" to "Playback stopped",
                                    "loadId" to oldId,
                                ),
                                epoch,
                            )
                        queue(
                            mapOf(
                                "type" to "stopResult",
                                "stopId" to command.id,
                                "success" to success,
                            )
                        )
                    }
                    done()
                }
            }
            else -> {
                try {
                    when (command) {
                        PlayerCommand.Play -> current?.takeIf { live(it) }?.engine?.play()
                        PlayerCommand.Pause -> current?.takeIf { live(it) }?.engine?.pause()
                        is PlayerCommand.Seek ->
                            current
                                ?.takeIf { live(it) }
                                ?.engine
                                ?.seek(command.seconds, command.exact)
                        is PlayerCommand.Volume -> {
                            volume = command.value
                            current?.takeIf { live(it) }?.engine?.volume(volume)
                        }
                        is PlayerCommand.Select -> {
                            val s = current
                            val success =
                                s != null &&
                                    live(s) &&
                                    s.loadId == command.loadId &&
                                    s.engine.select(command.type, command.id)
                            trackResult(command, success)
                        }
                        else -> Unit
                    }
                } catch (_: Exception) {
                    if (command is PlayerCommand.Select) trackResult(command, false)
                    else current?.let { fail(it, "command_error") }
                }
                done()
            }
        }
    }

    private fun listener(session: Session) =
        object : PlayerEngine.Listener {
            override fun firstFrame(positionMs: Long) {
                if (live(session)) host.firstFrame(session.generation, session.loadId, positionMs)
            }

            override fun fragmentSeek(position: Long) {
                if (live(session)) host.fragmentSeek(session.generation, session.loadId, position)
            }

            override fun frameTimestamp(presentationTimeUs: Long) {
                if (live(session))
                    host.frameTimestamp(session.generation, session.loadId, presentationTimeUs)
            }

            override fun sourceInitialization(revision: Int, accepted: Boolean) {
                if (live(session))
                    host.sourceInitialization(
                        session.generation,
                        session.loadId,
                        revision,
                        accepted,
                    )
            }

            override fun ready(paused: Boolean) {
                if (!live(session) || session.ready) return
                session.ready = true
                state(session, "playing", "Playing", mapOf("paused" to paused))
            }

            override fun ended() {
                if (!live(session)) return
                state(session, "ended", "Playback ended")
                session.terminal = true
                cleanupEngine = session.engine
                cleanup {}
            }

            override fun failure(code: String, httpStatus: Int?) = fail(session, code, httpStatus)

            override fun property(name: String, value: Any?) {
                if (live(session))
                    queue(
                        mapOf(
                            "type" to "property",
                            "name" to name,
                            "value" to value,
                            "loadId" to session.loadId,
                        ),
                        session.epoch,
                    )
            }
        }

    private fun live(s: Session) =
        initialized &&
            !disposing &&
            current === s &&
            s.generation == generation &&
            s.epoch == epoch &&
            !s.terminal

    private fun state(
        s: Session,
        state: String,
        message: String,
        extra: Map<String, Any?> = emptyMap(),
    ) {
        queue(
            mapOf("type" to "state", "state" to state, "message" to message, "loadId" to s.loadId) +
                extra,
            s.epoch,
        )
    }

    private fun loadError(loadId: Long, code: String) {
        queue(
            mapOf(
                "type" to "state",
                "state" to "error",
                "message" to "Native playback failed",
                "loadId" to loadId,
                "failureCode" to code,
            ),
            epoch,
        )
    }

    private fun trackResult(c: PlayerCommand.Select, success: Boolean) {
        queue(
            mapOf(
                "type" to "trackResult",
                "loadId" to c.loadId,
                "requestId" to c.requestId,
                "success" to success,
            ),
            epoch,
        )
    }

    private fun fail(s: Session, code: String, httpStatus: Int? = null) {
        if (!live(s)) return
        state(
            s,
            "error",
            "Native playback failed",
            mapOf("failureCode" to code) +
                (httpStatus?.let { mapOf("httpStatus" to it) } ?: emptyMap()),
        )
        s.terminal = true
        cleanupEngine = s.engine
        cleanup {}
    }

    private fun retire(complete: (Boolean) -> Unit) {
        epoch++
        current?.let { cleanupEngine = it.engine }
        current = null
        cleanup(complete)
    }

    private fun cleanup(complete: (Boolean) -> Unit) {
        host.keepScreenOn(false)
        if (cleanupRunning) {
            cleanupWaiters.add(complete)
            return
        }
        val engine = cleanupEngine
        if (engine == null) {
            complete(true)
            return
        }
        cleanupRunning = true
        cleanupWaiters.add(complete)
        var completed = false
        val finish: (Boolean) -> Unit = { success ->
            if (!completed) {
                completed = true
                cleanupRunning = false
                if (success && cleanupEngine === engine) cleanupEngine = null
                val waiters = cleanupWaiters.toList()
                cleanupWaiters.clear()
                waiters.forEach { it(success) }
            }
        }
        try {
            engine.release(finish)
        } catch (_: Exception) {
            finish(false)
        }
    }

    private fun purgeCommands() {
        commands.clear()
        queuedBytes = 0
        commandPosted = false
        controlRevision++
    }

    private fun dispose(reply: Reply) {
        if (disposing) {
            reply.error("dispose_in_progress")
            return
        }
        if (!initialized && cleanupEngine == null && !cleanupRunning) {
            reply.success()
            return
        }
        host.subtitlePresentation(null)
        disposing = true
        initialized = false
        generation++
        epoch++
        purgeCommands()
        events.clear()
        // Even an empty dispose replies asynchronously; concurrent disposal remains explicit.
        host.post {
            retire { success ->
                disposing = false
                if (success) reply.success() else reply.error("native_command_error")
            }
        }
    }

    fun releaseForBackground() {
        val owner = generation
        val loadId = current?.loadId
        val pending = commands.toList()
        purgeCommands()
        retire { success ->
            if (owner != generation || !initialized) return@retire
            for (c in pending) when (c) {
                is PlayerCommand.Stop ->
                    queue(mapOf("type" to "stopResult", "stopId" to c.id, "success" to success))
                is PlayerCommand.Select -> trackResult(c, false)
                else -> Unit
            }
            if (loadId != null) {
                if (success)
                    queue(
                        mapOf(
                            "type" to "state",
                            "state" to "stopped",
                            "message" to "Playback stopped",
                            "loadId" to loadId,
                        ),
                        epoch,
                    )
                else loadError(loadId, "native_error")
            }
            postCommands()
        }
    }

    fun close() {
        host.subtitlePresentation(null)
        initialized = false
        generation++
        purgeCommands()
        events.clear()
        retire {}
    }

    private fun queue(value: Map<String, Any?>, mediaEpoch: Long? = null) {
        events.add(QueuedEvent(generation, mediaEpoch, value))
        if (!eventPosted) {
            eventPosted = true
            host.post {
                eventPosted = false
                drainEvents()
            }
        }
    }

    private fun drainEvents() {
        if (events.consumeOverflow()) current?.let { fail(it, "event_queue_overflow") }
        while (true) {
            val e = events.take() ?: break
            if (initialized && e.generation == generation && (e.epoch == null || e.epoch == epoch))
                host.event(e.value)
        }
    }

    companion object {
        private val methods =
            setOf(
                "initialize",
                "dispose",
                "load",
                "play",
                "pause",
                "seek",
                "stop",
                "selectTrack",
                "setVolume",
                "setVideoRect",
                "setSubtitlePresentation",
                "setFullscreen",
                "setDisplayMatching",
            )
    }
}
