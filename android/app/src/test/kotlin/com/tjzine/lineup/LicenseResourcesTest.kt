package com.tjzine.lineup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LicenseResourcesTest {
    private class FakeAssets(initial: Map<String, ByteArray>) : LicenseResources.AssetSource {
        private val files = initial.toMutableMap()
        private val listedDirectories: MutableMap<String, List<String>> = mutableMapOf()

        init {
            for (path in files.keys) {
                val parts = path.split('/')
                for (index in parts.indices) {
                    val directory = parts.take(index).joinToString("/")
                    val child = parts[index]
                    listedDirectories[directory] =
                        (listedDirectories[directory].orEmpty() + child).distinct()
                }
            }
        }

        override fun list(path: String): List<String> = listedDirectories[path].orEmpty()

        override fun read(path: String): ByteArray = files[path]
            ?: throw IllegalArgumentException("not a file")

        fun replace(path: String, bytes: ByteArray) {
            files[path] = bytes
        }
    }

    private fun assets(extra: Map<String, ByteArray> = emptyMap()) = FakeAssets(
        mapOf(
            "BUILD-INFO.txt" to "Flutter 3.47.7\n".toByteArray(),
            "licenses/NOTICES-SUMMARY.txt" to "summary\n".toByteArray(),
            "licenses/media3/LICENSE.txt" to "Apache\n".toByteArray(),
            "licenses/media3/nested/NOTICE.txt" to "Notice\n".toByteArray(),
        ) + extra,
    )

    @Test
    fun indexesNestedDocumentsWithOpaqueIdsAndExactSizes() {
        val reader = LicenseResources(assets())

        val entries = reader.list()

        assertEquals(
            listOf(
                "BUILD-INFO.txt",
                "licenses/NOTICES-SUMMARY.txt",
                "licenses/media3/LICENSE.txt",
                "licenses/media3/nested/NOTICE.txt",
            ),
            entries.map { it["path"] },
        )
        assertTrue(entries.all { (it["id"] as String).startsWith("native-") })
        assertEquals(7, entries.first { it["path"] == "licenses/media3/LICENSE.txt" }["bytes"])
        assertEquals(
            "Notice\n",
            reader.read(entries.single { it["path"] == "licenses/media3/nested/NOTICE.txt" }["id"] as String),
        )
    }

    @Test
    fun rejectsUnknownIdsAndRequiresAnIndexedTree() {
        val reader = LicenseResources(assets())

        assertThrows(RuntimeException::class.java) { reader.read("native-0") }
        reader.list()
        assertThrows(RuntimeException::class.java) { reader.read("../SENTINEL") }

        val missingSummary = assets().also { it.replace("licenses/NOTICES-SUMMARY.txt", ByteArray(0)) }
        assertThrows(RuntimeException::class.java) { LicenseResources(missingSummary).list() }
    }

    @Test
    fun rejectsInvalidUtf8AndOversizedDocuments() {
        val invalid = assets().also {
            it.replace("licenses/media3/nested/NOTICE.txt", byteArrayOf(0xff.toByte()))
        }
        assertThrows(RuntimeException::class.java) { LicenseResources(invalid).list() }

        val oversized = assets().also {
            it.replace("licenses/media3/nested/NOTICE.txt", ByteArray(2 * 1024 * 1024 + 1))
        }
        assertThrows(RuntimeException::class.java) { LicenseResources(oversized).list() }
    }

    @Test
    fun rejectsTraversalNamesFromAssetSource() {
        val source = object : LicenseResources.AssetSource {
            override fun list(path: String): List<String> = when (path) {
                "" -> listOf("licenses")
                "licenses" -> listOf("../SENTINEL")
                else -> emptyList()
            }

            override fun read(path: String): ByteArray = "unexpected".toByteArray()
        }

        assertThrows(RuntimeException::class.java) { LicenseResources(source).list() }
    }
}
