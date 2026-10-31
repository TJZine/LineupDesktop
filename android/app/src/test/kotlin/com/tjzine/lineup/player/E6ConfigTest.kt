package com.tjzine.lineup.player

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class E6ConfigTest {
    private fun rejects(code: String? = null, action: () -> Unit) {
        try { action(); fail("must reject") } catch (error: E6Failure) { if (code != null) assertEquals(code, error.code) }
    }

    @Test fun sharedHostNativePlaylistRejectionVectors() {
        var directory = java.io.File(System.getProperty("user.dir")).absoluteFile
        while (!java.io.File(directory, "tool/android/fixtures/e6_playlist_scope_cases.json").isFile)
            directory = directory.parentFile ?: error("missing shared scope cases")
        val rows = org.json.JSONArray(java.io.File(directory, "tool/android/fixtures/e6_playlist_scope_cases.json").readText())
        val config = E6Config.parse(e6Input() + mapOf("sourceDurationMs" to 20000,
            "expectedDurationsSeconds" to listOf(10, 10)), false)
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            val name = row.getString("name")
            val bytes = if (row.has("hex")) row.getString("hex").chunked(2).map { it.toInt(16).toByte() }.toByteArray()
                else row.getString("text").toByteArray(Charsets.UTF_8)
            try {
                val candidate = if (row.has("variant")) E6Config.parse(e6Input(uri = row.getString("variant")) +
                    mapOf("sourceDurationMs" to 20000, "expectedDurationsSeconds" to listOf(10, 10)), false) else config
                assertEquals(name, 3, candidate.playlist(bytes).size)
                assertTrue(name, row.isNull("reason"))
            } catch (error: E6Failure) {
                assertFalse(name, row.isNull("reason"))
                assertEquals(name, "playlist_scope", error.code)
                assertEquals(name, row.getString("reason"), error.scopeReason)
                assertEquals(name, if (row.isNull("tag")) null else row.getString("tag"), error.scopeTag)
                assertEquals(name, if (row.isNull("index")) null else row.getInt("index"), error.scopeIndex)
                assertTrue(name, E6Facts.valid(mapOf("event" to "failure", "failureCode" to error.code) + error.scopeFacts()))
                assertFalse(name, error.scopeFacts().toString().contains("PRIVATE_SENTINEL"))
            }
        }
    }

    @Test fun exactInputWhitelistAndPublicBaselineGate() {
        assertTrue(E6Config.parse(e6Input(), true).baseline)
        rejects("baseline_private_refused") { E6Config.parse(e6Input(seek = true), true) }
        rejects("baseline_private_refused") { E6Config.parse(e6Input(uri =
            "https://server.invalid/video/:/transcode/universal/session/private/base/index.m3u8"), true) }
        rejects("invalid_config") { E6Config.parse(e6Input() + ("token" to "PRIVATE_SENTINEL"), false) }
        rejects("invalid_config") { E6Config.parse(e6Input() - "observeSeconds", false) }
        rejects("invalid_config") { E6Config.parse(e6Input() + ("observeSeconds" to 9), false) }
    }

    @Test fun sourceMetadataHasFiniteExactNumericBounds() {
        for (changes in listOf(mapOf("offsetSeconds" to 6), mapOf("mode" to "other"),
            mapOf("expectedAudioCodec" to "truehd"), mapOf("expectedVideoCodec" to "av1"),
            mapOf("expectedMediaSequence" to 1), mapOf("expectedTargetDurationSeconds" to 121),
            mapOf("sourceDurationMs" to 42_000), mapOf("expectedDurationsSeconds" to listOf(10, 0, 10, 20)),
            mapOf("expectedDurationsSeconds" to listOf(10.0000001, 10, 10, 10))))
            rejects { E6Config.parse(e6Input() + changes, false) }
        assertEquals(listOf(10_000_000L, 10_000_000L, 10_000_000L, 10_000_000L), E6Config.parse(e6Input(), false).durationsUs)
    }

    @Test fun rejectsRawAndResolvedEscapesBeforeNormalization() {
        val config = E6Config.parse(e6Input(), false)
        for (uri in listOf("../stop", "%2e%2e/init.mp4", "foo%2fbar.m4s", "a\\b", "0.m4s?token=private",
            "https://localhost:21443/e6-other/0.m4s", "https://other.invalid/e6-clock/0.m4s",
            "/e6-clock/sub/0.m4s", "https://user@localhost:21443/e6-clock/0.m4s", "\n0.m4s"))
            rejects("unsafe_reference") { config.reference(uri) }
        assertEquals("/e6-clock/0.m4s", config.reference("0.m4s").encodedPath)
    }

    @Test fun exactSessionNamespaceRejectsSameOriginOtherSessionAndControl() {
        val config = E6Config.parse(e6Input(uri = "https://server.invalid/video/:/transcode/universal/session/owned/base/index.m3u8"), false)
        rejects("unsafe_reference") { config.reference("/video/:/transcode/universal/session/foreign/base/0.m4s") }
        rejects("unsafe_reference") { config.reference("/video/:/transcode/universal/stop") }
        assertEquals("E6Config()", config.toString())
    }

    @Test fun finitePlaylistDerivesOnlyExactInitAndMediaReferences() {
        val config = E6Config.parse(e6Input(21), false)
        val refs = config.playlist(e6Playlist(21).toByteArray())
        assertEquals(5, refs.size)
        val media = refs.entries.single { it.key.encodedPath.endsWith("/2.m4s") }.value
        assertEquals(E6Reference("media", 2, 2), media)
        assertEquals("init", refs.entries.single { it.key.encodedPath.endsWith("init.mp4") }.value.kind)
        // A noncanonical filename is never exported as an index, while its private exact URI stays usable.
        val zeroPadded = config.playlist(e6Playlist(21, media = listOf("00000.m4s", "1.m4s", "2.m4s", "3.m4s")).toByteArray())
        assertNull(zeroPadded.entries.first().value.filenameIndex)
    }

    @Test fun playlistRejectsScopeTimingAndSelectionContradictions() {
        val config = E6Config.parse(e6Input(21), false)
        val good = e6Playlist(21)
        for (bad in listOf(good.replace("#EXT-X-ENDLIST", ""), good.replace("10.000000,", "9.000000,"),
            good.replace("TARGETDURATION:10", "TARGETDURATION:11"), good.replace("MEDIA-SEQUENCE:0", "MEDIA-SEQUENCE:1"),
            good.replace("TIME-OFFSET=21", "TIME-OFFSET=21,PRECISE=YES"),
            good.replace("#EXT-X-MAP", "#EXT-X-DISCONTINUITY\n#EXT-X-MAP"),
            good.replace("#EXT-X-MAP", "#EXT-X-KEY:METHOD=AES-128,URI=\"key\"\n#EXT-X-MAP"),
            good.replace("0.m4s", "../0.m4s"), good.replace("1.m4s", "0.m4s"),
            good.replace("#EXT-X-MAP", "#EXT-X-STREAM-INF:BANDWIDTH=1\n#EXT-X-MAP")))
            rejects { config.playlist(bad.toByteArray()) }
    }

    @Test fun queueRefusesPrivateStringsAndRetainsLifetimeBoundAcrossDrain() {
        val queue = E6FactQueue()
        rejects("fact_schema") { queue.add(mapOf("event" to "format", "videoCodec" to "PRIVATE_SENTINEL")) }
        rejects("fact_schema") { queue.add(mapOf("event" to "ready", "uri" to "PRIVATE_SENTINEL")) }
        repeat(298) { queue.add(mapOf("event" to "ready", "positionMs" to it)); queue.drain() }
        rejects("event_overflow") { queue.add(mapOf("event" to "position")) }
        queue.add(mapOf("event" to "release", "released" to false))
        assertEquals(1, queue.drain().size)
        rejects("event_overflow") { queue.add(mapOf("event" to "release")) }
    }

    @Test fun sharedCollectorSchemaMatchesEveryNativeFieldTypeAndEnum() {
        var directory = java.io.File(System.getProperty("user.dir")).absoluteFile
        while (!java.io.File(directory, "tool/android/fixtures/e6_schema.json").isFile) {
            directory = directory.parentFile ?: error("repository schema missing")
        }
        val fields = org.json.JSONObject(java.io.File(directory, "tool/android/fixtures/e6_schema.json").readText()).getJSONObject("fields")
        assertEquals(E6Facts.enums.keys + E6Facts.booleans + E6Facts.numbers, fields.keys().asSequence().toSet())
        for ((key, values) in E6Facts.enums) {
            val schema = fields.getJSONObject(key)
            assertEquals("string", schema.getString("type"))
            val actual = schema.getJSONArray("enum")
            assertEquals(values, (0 until actual.length()).map { actual.getString(it) }.toSet())
        }
        for (key in E6Facts.booleans) assertEquals("boolean", fields.getJSONObject(key).getString("type"))
        for (key in E6Facts.numbers) assertEquals("integer", fields.getJSONObject(key).getString("type"))
        assertFalse(E6Facts.valid(mapOf("event" to "ready", "positionMs" to 1.0)))
    }
}
