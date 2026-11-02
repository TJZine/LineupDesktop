package com.tjzine.lineup.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.StatsDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.extractor.*
import androidx.media3.extractor.mkv.MatroskaExtractor
import androidx.media3.extractor.text.DefaultSubtitleParserFactory
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class BufferedProgressiveDataSourceTest {
    private val uri = Uri.parse("memory:public-fixture")
    private fun bytes(size: Int) = ByteArray(size) { ((it * 31 + it / 251) % 256).toByte() }
    private fun spec(position: Long = 0, length: Long = C.LENGTH_UNSET.toLong()) =
        DataSpec.Builder().setUri(uri).setPosition(position).setLength(length).setFlags(6).build()

    /** Real network=true transfer callbacks, without HTTP or any external resource. */
    private class MemoryNetwork(
        private val bytes: ByteArray,
        private val maxRead: Int = Int.MAX_VALUE,
        private val recordReadSizes: Boolean = true,
        private val unknownLength: Boolean = false,
        private val honorSpecLength: Boolean = true,
    ) : BaseDataSource(true) {
        val readSizes = mutableListOf<Int>()
        val openedSpecs = mutableListOf<DataSpec>()
        val headers = mapOf("X-Public-Fixture" to listOf("dummy"))
        var positiveReads = 0
        var returnedBytes = 0L
        var closeCalls = 0
        var readFailure: IOException? = null
        var openFailure: IOException? = null
        var closeFailure: IOException? = null
        var returnZero = false
        private var cursor = 0
        private var limit = 0
        private var opened = false
        override fun open(dataSpec: DataSpec): Long {
            check(!opened)
            openedSpecs.add(dataSpec)
            openFailure?.let { openFailure = null; throw it }
            require(dataSpec.position in 0..bytes.size.toLong())
            transferInitializing(dataSpec)
            cursor = dataSpec.position.toInt()
            limit = if (!honorSpecLength || dataSpec.length == C.LENGTH_UNSET.toLong()) bytes.size
                else minOf(bytes.size.toLong(), dataSpec.position + dataSpec.length).toInt()
            opened = true
            transferStarted(dataSpec)
            return if (unknownLength) C.LENGTH_UNSET.toLong() else (limit - cursor).toLong()
        }
        override fun read(target: ByteArray, offset: Int, length: Int): Int {
            check(opened)
            if (recordReadSizes) readSizes.add(length)
            if (length == 0) return 0
            readFailure?.let { readFailure = null; throw it }
            if (returnZero) { returnZero = false; return 0 }
            if (cursor == limit) return C.RESULT_END_OF_INPUT
            val count = minOf(length, maxRead, limit - cursor)
            bytes.copyInto(target, offset, cursor, cursor + count)
            cursor += count
            positiveReads++
            returnedBytes += count
            bytesTransferred(count)
            return count
        }
        override fun getUri(): Uri? = if (opened) Uri.parse("memory:redirected-public-fixture") else null
        override fun getResponseHeaders(): Map<String, List<String>> = headers
        override fun close() {
            closeCalls++
            if (opened) {
                opened = false
                transferEnded()
            }
            closeFailure?.let { closeFailure = null; throw it }
        }
    }

    private class Transfers : TransferListener {
        var initializing = 0
        var starts = 0
        var ends = 0
        var byteCalls = 0
        var bytes = 0L
        var allNetwork = true
        override fun onTransferInitializing(source: DataSource, spec: DataSpec, network: Boolean) {
            initializing++
            allNetwork = allNetwork && network
        }
        override fun onTransferStart(source: DataSource, spec: DataSpec, network: Boolean) {
            starts++
            allNetwork = allNetwork && network
        }
        override fun onBytesTransferred(source: DataSource, spec: DataSpec, network: Boolean, count: Int) {
            byteCalls++
            bytes += count
            allNetwork = allNetwork && network
        }
        override fun onTransferEnd(source: DataSource, spec: DataSpec, network: Boolean) {
            ends++
            allNetwork = allNetwork && network
        }
    }

    private fun readAll(source: DataSource, chunk: Int): ByteArray {
        val result = ByteArrayOutputStream()
        val target = ByteArray(chunk + 4) { 85 }
        while (true) {
            val count = source.read(target, 2, chunk)
            if (count == C.RESULT_END_OF_INPUT) break
            assertTrue("Nonempty read must make progress", count in 1..chunk)
            assertEquals(85.toByte(), target[0])
            assertEquals(85.toByte(), target[target.lastIndex])
            result.write(target, 2, count)
        }
        return result.toByteArray()
    }

    @Test fun partialUpstreamReadsRespectPositionLengthAndTargetOffsets() {
        val fixture = bytes(1000)
        val upstream = MemoryNetwork(fixture, maxRead = 7)
        val source = BufferedProgressiveDataSource(upstream)
        val request = spec(29, 173)
        assertEquals(173L, source.open(request))
        assertSame(request, upstream.openedSpecs.single())
        assertArrayEquals(fixture.copyOfRange(29, 202), readAll(source, 3))
        assertEquals(173L, upstream.returnedBytes)
        source.close()
    }

    @Test fun unknownLengthEofAndZeroLengthReadsDoNotFabricateBytes() {
        val fixture = bytes(19)
        val upstream = MemoryNetwork(fixture, maxRead = 5, unknownLength = true)
        val source = BufferedProgressiveDataSource(upstream)
        assertEquals(C.LENGTH_UNSET.toLong(), source.open(spec()))
        val target = ByteArray(2)
        assertEquals(0, source.read(target, 2, 0))
        assertTrue(upstream.readSizes.isEmpty())
        assertArrayEquals(fixture, readAll(source, 2))
        val countAtEof = upstream.readSizes.size
        assertEquals(0, source.read(target, 2, 0))
        assertEquals(C.RESULT_END_OF_INPUT, source.read(target, 0, 1))
        assertEquals(countAtEof, upstream.readSizes.size)
        source.close()
    }

    @Test fun explicitLengthCapsPrefetchWhenUpstreamReturnsUnknownLength() {
        val fixture = bytes(1000)
        // Deliberately non-enforcing test upstream isolates the wrapper's own range bound;
        // ordinary DataSources are also responsible for respecting DataSpec.length.
        val upstream = MemoryNetwork(fixture, unknownLength = true, honorSpecLength = false)
        val source = BufferedProgressiveDataSource(upstream)
        assertEquals(C.LENGTH_UNSET.toLong(), source.open(spec(29, 173)))
        assertArrayEquals(fixture.copyOfRange(29, 202), readAll(source, 3))
        assertEquals(listOf(173), upstream.readSizes)
        assertEquals(173L, upstream.returnedBytes)
        source.close()
    }

    @Test fun closeAndReopenDiscardUnreadPrefetchEvenWhenCloseThrows() {
        val fixture = bytes(150000)
        val upstream = MemoryNetwork(fixture)
        val source = BufferedProgressiveDataSource(upstream)
        source.open(spec(10))
        val target = ByteArray(3)
        assertEquals(1, source.read(target, 0, 1))
        assertEquals(fixture[10], target[0])
        assertTrue(upstream.returnedBytes > 1)
        val failure = IOException("public fixture close failure")
        upstream.closeFailure = failure
        assertSame(failure, assertThrows(IOException::class.java) { source.close() })
        assertEquals(3L, source.open(spec(90000, 3)))
        assertArrayEquals(fixture.copyOfRange(90000, 90003), readAll(source, 2))
        source.close()
        upstream.openFailure = failure
        assertSame(failure, assertThrows(IOException::class.java) { source.open(spec(20)) })
        source.close()
        source.open(spec(120000, 2))
        assertArrayEquals(fixture.copyOfRange(120000, 120002), readAll(source, 3))
        source.close()
    }

    @Test fun metadataAndNetworkTransferAccountingAreForwardedWithoutDuplication() {
        val upstream = MemoryNetwork(bytes(100000))
        val source = BufferedProgressiveDataSource(upstream)
        val transfers = Transfers()
        source.addTransferListener(transfers)
        val request = spec(123, 70000)
        source.open(request)
        assertSame(request, upstream.openedSpecs.single())
        assertEquals(upstream.uri, source.uri)
        assertSame(upstream.headers, source.responseHeaders)
        assertEquals(3, source.read(ByteArray(3), 0, 3))
        source.close()
        assertEquals(1, transfers.initializing)
        assertEquals(1, transfers.starts)
        assertEquals(1, transfers.ends)
        assertTrue(transfers.allNetwork)
        assertEquals(upstream.positiveReads, transfers.byteCalls)
        assertEquals(upstream.returnedBytes, transfers.bytes)
        assertEquals(65536L, transfers.bytes) // upstream prefetch, not the three delivered bytes
    }

    @Test fun largeReadsBypassEmptyBufferAndPreserveOrderAfterPrefetch() {
        val fixture = bytes(300000)
        val upstream = MemoryNetwork(fixture)
        val source = BufferedProgressiveDataSource(upstream)
        source.open(spec())
        val target = ByteArray(100003)
        assertEquals(target.size, source.read(target, 0, target.size))
        assertArrayEquals(fixture.copyOfRange(0, target.size), target)
        assertEquals(listOf(target.size), upstream.readSizes)
        source.close()
        source.open(spec())
        val output = ByteArrayOutputStream()
        val first = ByteArray(3)
        assertEquals(3, source.read(first, 0, 3))
        output.write(first)
        output.write(readAll(source, 100000))
        assertArrayEquals(fixture, output.toByteArray())
        source.close()
    }

    @Test fun failedRefillCannotReplayAnEarlierBuffer() {
        val fixture = bytes(65536 + 17)
        val upstream = MemoryNetwork(fixture)
        val source = BufferedProgressiveDataSource(upstream)
        source.open(spec())
        val target = ByteArray(65536)
        assertEquals(1, source.read(target, 0, 1))
        assertEquals(65535, source.read(target, 1, 65535))
        assertArrayEquals(fixture.copyOfRange(0, 65536), target)
        val failure = IOException("public fixture read failure")
        upstream.readFailure = failure
        assertSame(failure, assertThrows(IOException::class.java) { source.read(target, 0, 1) })
        assertArrayEquals(fixture.copyOfRange(65536, fixture.size), readAll(source, 3))
        source.close()
    }

    @Test fun nonprogressingUpstreamReadFailsInsteadOfReturningZero() {
        val upstream = MemoryNetwork(bytes(100))
        val source = BufferedProgressiveDataSource(upstream)
        source.open(spec())
        upstream.returnZero = true
        assertThrows(IOException::class.java) { source.read(ByteArray(1), 0, 1) }
        source.close()
    }

    @Test fun matroskaCuesSeekProducesIdenticalRealChunkIndex() {
        val fixture = matroskaFixture()
        fun parse(buffered: Boolean): Pair<ChunkIndex, Long> {
            val upstream = MemoryNetwork(fixture.bytes, recordReadSizes = false)
            val stats = StatsDataSource(if (buffered) BufferedProgressiveDataSource(upstream) else upstream)
            val extractor = MatroskaExtractor(DefaultSubtitleParserFactory())
            var map: SeekMap? = null
            var tracksEnded = false
            extractor.init(object : ExtractorOutput {
                override fun track(id: Int, type: Int): TrackOutput = DiscardingTrackOutput()
                override fun endTracks() { tracksEnded = true }
                override fun seekMap(value: SeekMap) { map = value }
            })
            fun input(position: Long): DefaultExtractorInput {
                val remaining = stats.open(spec(position))
                return DefaultExtractorInput(stats, position, remaining + position)
            }
            var input = input(0)
            val holder = PositionHolder()
            var iterations = 0
            try {
                while (map == null) {
                    check(++iterations < 1000)
                    val result = extractor.read(input, holder)
                    if (map != null) break // map callback precedes seek back to the media Cluster
                    when (result) {
                        Extractor.RESULT_SEEK -> { stats.close(); input = input(holder.position) }
                        Extractor.RESULT_END_OF_INPUT -> fail("No Matroska seek map")
                    }
                }
            } finally { stats.close(); extractor.release() }
            assertTrue(tracksEnded)
            assertEquals(listOf(0L, fixture.cuesOffset), upstream.openedSpecs.map { it.position })
            val index = (map as? ChunkIndex) ?: (map as? ChunkIndexProvider)?.chunkIndex
            assertNotNull(index)
            assertEquals(6144, index!!.length)
            assertArrayEquals(fixture.clusterOffsets, index.offsets)
            return index to stats.bytesRead
        }
        val (plain, plainBytes) = parse(false)
        val (buffered, bufferedBytes) = parse(true)
        assertArrayEquals(plain.offsets, buffered.offsets)
        assertArrayEquals(plain.sizes, buffered.sizes)
        assertArrayEquals(plain.timesUs, buffered.timesUs)
        assertArrayEquals(plain.durationsUs, buffered.durationsUs)
        assertEquals(plainBytes, bufferedBytes)
    }

    private data class MatroskaFixture(val bytes: ByteArray, val cuesOffset: Long, val clusterOffsets: LongArray)

    /** Public dummy metadata: 6144 cues × 37 declared VP8 tracks, final Cues via SeekHead. No media payload. */
    private fun matroskaFixture(): MatroskaFixture {
        fun uint(value: Long, width: Int = 4) = ByteArray(width) { n -> (value shr ((width - n - 1) * 8)).toByte() }
        fun id(value: Long) = uint(value, (1..4).first { value < (1L shl (it * 8)) })
        fun size(value: Int): ByteArray {
            val width = (1..8).first { value.toLong() < (1L shl (it * 7)) - 1 }
            return uint(value.toLong() or (1L shl (width * 7)), width)
        }
        fun element(tag: Long, content: ByteArray) = id(tag) + size(content.size) + content
        fun number(tag: Long, value: Long, width: Int = 4) = element(tag, uint(value, width))
        fun joined(vararg arrays: ByteArray) = ByteArrayOutputStream().apply { arrays.forEach { write(it) } }.toByteArray()
        val count = 6144
        val trackCount = 37
        val ebml = element(0x1A45DFA3, joined(number(0x4286, 1, 1), number(0x42F7, 1, 1),
            number(0x42F2, 4, 1), number(0x42F3, 8, 1), element(0x4282, "matroska".toByteArray()),
            number(0x4287, 4, 1), number(0x4285, 2, 1)))
        val info = element(0x1549A966, joined(number(0x2AD7B1, 1000000),
            element(0x4489, ByteBuffer.allocate(8).putDouble(count.toDouble() * 1000).array())))
        val trackEntries = ByteArrayOutputStream()
        repeat(trackCount) { track ->
            trackEntries.write(element(0xAE, joined(number(0xD7, track + 1L, 1), number(0x73C5, track + 1L, 1),
                number(0x83, 1, 1), element(0x86, "V_VP8".toByteArray()),
                element(0xE0, joined(number(0xB0, 16, 1), number(0xBA, 16, 1))))))
        }
        val tracks = element(0x1654AE6B, trackEntries.toByteArray())
        fun seekHead(cuesPosition: Long) = element(0x114D9B74, element(0x4DBB,
            joined(element(0x53AB, id(0x1C53BB6B)), number(0x53AC, cuesPosition))))
        val prefix = joined(seekHead(0), info, tracks)
        val clusters = ByteArrayOutputStream()
        val offsets = LongArray(count)
        repeat(count) { n ->
            offsets[n] = prefix.size.toLong() + clusters.size()
            clusters.write(element(0x1F43B675, number(0xE7, n.toLong() * 1000)))
        }
        val cuesPosition = prefix.size.toLong() + clusters.size()
        val cueContent = ByteArrayOutputStream()
        repeat(count) { n ->
            val positions = ByteArrayOutputStream()
            repeat(trackCount) { track ->
                positions.write(element(0xB7, joined(number(0xF7, track + 1L, 1), number(0xF1, offsets[n]))))
            }
            cueContent.write(element(0xBB, joined(number(0xB3, n.toLong() * 1000), positions.toByteArray())))
        }
        val body = joined(seekHead(cuesPosition), info, tracks, clusters.toByteArray(), element(0x1C53BB6B, cueContent.toByteArray()))
        val start = ebml.size + id(0x18538067).size + size(body.size).size
        return MatroskaFixture(ebml + element(0x18538067, body), start + cuesPosition,
            LongArray(count) { start + offsets[it] })
    }
}
