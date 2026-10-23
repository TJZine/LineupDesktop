package com.tjzine.lineup

import android.content.res.AssetManager
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

private const val LICENSE_FILE_LIMIT = 2 * 1024 * 1024

private class LicenseAssetSizeExceeded : RuntimeException()

/**
 * Reads the immutable Android runtime notices bundled under assets/licenses.
 * Dart receives only opaque IDs minted by [list]; it never supplies a path.
 */
class LicenseResources(private val source: AssetSource) {
    constructor(assets: AssetManager) : this(AssetManagerSource(assets))

    interface AssetSource {
        fun list(path: String): List<String>

        fun read(path: String): ByteArray
    }

    private enum class Operation { LIST, READ }

    private enum class Stage {
        ASSET_LIST,
        ASSET_READ,
        ENTRY_NAME,
        ENTRY_KIND,
        FILE_SIZE,
        FILE_ENCODING,
        TREE_BOUNDS,
        ENTRY_COUNT,
        REQUIRED_INDEX,
        DOCUMENT_ID,
        DEPTH_BOUNDS,
    }

    private enum class Category { SYSTEM, INVALID, BOUNDS, MISSING, ENCODING }

    private class Failure(
        val stage: Stage,
        val category: Category,
        cause: Throwable? = null,
    ) : RuntimeException(null, cause)

    private data class Document(val path: String, val bytes: Int)

    private val fileLimit = LICENSE_FILE_LIMIT
    private val treeLimit = 16 * 1024 * 1024
    private val documentLimit = 4096
    private val documents = LinkedHashMap<String, String>()
    private val diagnosticsEnabled =
        System.getenv("LINEUP_LICENSE_DIAGNOSTICS") == "1"

    /** Returns Flutter-codec-compatible maps with stable, opaque document IDs. */
    fun list(): List<Map<String, Any>> {
        return try {
            index()
        } catch (failure: Failure) {
            report(Operation.LIST, failure)
            throw failure
        }
    }

    /** Reads a document only after [list] has minted its ID. */
    fun read(id: String?): String {
        return try {
            val path = id?.let { documents[it] }
                ?: throw Failure(Stage.DOCUMENT_ID, Category.INVALID)
            decode(readBounded(path))
        } catch (failure: Failure) {
            report(Operation.READ, failure)
            throw failure
        }
    }

    private fun index(): List<Map<String, Any>> {
        documents.clear()
        val files = mutableListOf<Document>()
        var total = 0
        val roots = listDirectory("")
        if (!roots.contains("licenses")) {
            throw Failure(Stage.REQUIRED_INDEX, Category.MISSING)
        }
        total += walk("licenses", 0, files)
        if (roots.contains("patches")) {
            total += walk("patches", 0, files)
        }
        val buildInfo = readBounded("BUILD-INFO.txt")
        decode(buildInfo)
        total += buildInfo.size
        if (total > treeLimit) {
            throw Failure(Stage.TREE_BOUNDS, Category.BOUNDS)
        }
        files += Document("BUILD-INFO.txt", buildInfo.size)
        if (files.none { it.path == "licenses/NOTICES-SUMMARY.txt" }) {
            throw Failure(Stage.REQUIRED_INDEX, Category.MISSING)
        }
        if (files.size > documentLimit) {
            throw Failure(Stage.ENTRY_COUNT, Category.BOUNDS)
        }
        return files.sortedBy { it.path }.mapIndexed { index, document ->
            val id = "native-$index"
            documents[id] = document.path
            mapOf("id" to id, "path" to document.path, "bytes" to document.bytes)
        }
    }

    private fun walk(path: String, depth: Int, files: MutableList<Document>): Int {
        if (depth >= 16) {
            throw Failure(Stage.DEPTH_BOUNDS, Category.BOUNDS)
        }
        var total = 0
        val children = listDirectory(path)
        if (children.isEmpty()) {
            val bytes = readBounded(path)
            decode(bytes)
            files += Document(path, bytes.size)
            return bytes.size
        }
        for (name in children.sorted()) {
            validateName(name)
            val childPath = "$path/$name"
            val nested = listDirectory(childPath)
            if (nested.isEmpty()) {
                val bytes = readBounded(childPath)
                decode(bytes)
                if (files.size >= documentLimit) {
                    throw Failure(Stage.ENTRY_COUNT, Category.BOUNDS)
                }
                files += Document(childPath, bytes.size)
                total += bytes.size
            } else {
                total += walk(childPath, depth + 1, files)
            }
            if (total > treeLimit) {
                throw Failure(Stage.TREE_BOUNDS, Category.BOUNDS)
            }
        }
        return total
    }

    private fun listDirectory(path: String): List<String> {
        return try {
            source.list(path)
        } catch (error: Throwable) {
            throw Failure(Stage.ASSET_LIST, Category.SYSTEM, error)
        }
    }

    private fun readBounded(path: String): ByteArray {
        validatePath(path)
        return try {
            val bytes = source.read(path)
            if (bytes.isEmpty() || bytes.size > fileLimit) {
                throw Failure(Stage.FILE_SIZE, Category.BOUNDS)
            }
            bytes
        } catch (failure: Failure) {
            throw failure
        } catch (_: LicenseAssetSizeExceeded) {
            throw Failure(Stage.FILE_SIZE, Category.BOUNDS)
        } catch (error: Throwable) {
            throw Failure(Stage.ASSET_READ, Category.SYSTEM, error)
        }
    }

    private fun decode(bytes: ByteArray): String {
        return try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        } catch (error: CharacterCodingException) {
            throw Failure(Stage.FILE_ENCODING, Category.ENCODING, error)
        }
    }

    private fun validateName(name: String) {
        if (name.isEmpty() || name == "." || name == ".." || name.contains('/')) {
            throw Failure(Stage.ENTRY_NAME, Category.INVALID)
        }
    }

    private fun validatePath(path: String) {
        val parts = path.split('/')
        if (parts.isEmpty() || parts.any { it.isEmpty() || it == "." || it == ".." }) {
            throw Failure(Stage.ENTRY_NAME, Category.INVALID)
        }
        parts.forEach(::validateName)
    }

    private fun report(operation: Operation, failure: Failure) {
        if (!diagnosticsEnabled) return
        System.err.println(
            "[lineup-license-native] operation=${operation.name.lowercase()} " +
                "stage=${failure.stage.name.lowercase()} " +
                "category=${failure.category.name.lowercase()}",
        )
    }

    private class AssetManagerSource(private val assets: AssetManager) : AssetSource {
        override fun list(path: String): List<String> = assets.list(path)?.toList() ?: emptyList()

        override fun read(path: String): ByteArray {
            assets.open(path, AssetManager.ACCESS_STREAMING).use { input ->
                return input.readAllBytesBounded(LICENSE_FILE_LIMIT)
            }
        }
    }
}

private fun InputStream.readAllBytesBounded(limit: Int): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(32 * 1024)
    while (true) {
        val count = read(buffer)
        if (count < 0) break
        output.write(buffer, 0, count)
        if (output.size() > limit) {
            throw LicenseAssetSizeExceeded()
        }
    }
    return output.toByteArray()
}
