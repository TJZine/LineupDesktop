package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import java.io.IOException

/** Coalesces small extractor reads without changing upstream transfer accounting. */
@UnstableApi
internal class BufferedProgressiveDataSource(private val upstream: DataSource) : DataSource {
    private val buffer = ByteArray(64 * 1024)
    private var position = 0
    private var limit = 0
    private var remaining = 0L

    override fun addTransferListener(listener: TransferListener) = upstream.addTransferListener(listener)

    override fun open(dataSpec: DataSpec): Long {
        clear()
        val length = upstream.open(dataSpec)
        remaining = if (dataSpec.length != C.LENGTH_UNSET.toLong()) dataSpec.length else length
        return length
    }

    override fun read(target: ByteArray, offset: Int, length: Int): Int {
        require(offset >= 0 && length >= 0 && offset <= target.size - length)
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT

        if (position == limit) {
            // MP4 metadata and media payloads already request large blocks. Avoid
            // copying those through a second buffer.
            if (length >= buffer.size) {
                val count = readUpstream(target, offset, bounded(length))
                if (count > 0) consumed(count)
                return count
            }
            position = 0
            limit = 0
            limit = readUpstream(buffer, 0, bounded(buffer.size))
            if (limit == C.RESULT_END_OF_INPUT) {
                limit = 0
                return C.RESULT_END_OF_INPUT
            }
        }
        val count = minOf(length, limit - position)
        buffer.copyInto(target, offset, position, position + count)
        position += count
        consumed(count)
        return count
    }

    private fun bounded(length: Int): Int =
        if (remaining == C.LENGTH_UNSET.toLong()) length else minOf(length.toLong(), remaining).toInt()

    private fun readUpstream(target: ByteArray, offset: Int, length: Int): Int {
        val count = upstream.read(target, offset, length)
        if (count == 0) throw IOException("Upstream returned zero bytes for a nonempty read")
        if (count == C.RESULT_END_OF_INPUT) remaining = 0
        return count
    }

    private fun consumed(count: Int) {
        if (remaining != C.LENGTH_UNSET.toLong()) remaining -= count
    }

    override fun getUri(): Uri? = upstream.uri

    override fun getResponseHeaders(): Map<String, List<String>> = upstream.responseHeaders

    override fun close() {
        try {
            upstream.close()
        } finally {
            clear()
        }
    }

    private fun clear() {
        position = 0
        limit = 0
        remaining = 0
    }
}
