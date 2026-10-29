package com.tjzine.lineup.player

import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test

class Mp4TypeObserverTest {
    private fun int(n: Int) = ByteBuffer.allocate(4).putInt(n).array()

    private fun long(n: Long) = ByteBuffer.allocate(8).putLong(n).array()

    private fun box(
        type: String,
        payload: ByteArray = byteArrayOf(),
        extended: Boolean = false,
        zero: Boolean = false,
    ): ByteArray =
        (if (extended) int(1) + type.toByteArray() + long(payload.size + 16L)
        else int(if (zero) 0 else payload.size + 8) + type.toByteArray()) + payload

    private fun track(type: String) =
        box("trak", box("mdia", box("hdlr", ByteArray(8) + type.toByteArray() + ByteArray(8))))

    private fun moov(vararg types: String) =
        box("moov", types.fold(byteArrayOf()) { a, t -> a + track(t) })

    private fun feed(bytes: ByteArray, chunk: Int = bytes.size): Mp4TypeObserver {
        val observer = Mp4TypeObserver()
        var i = 0
        while (i < bytes.size) {
            val n = minOf(chunk, bytes.size - i)
            observer.consume(i.toLong(), bytes, i, n, bytes.size.toLong())
            i += n
        }
        return observer
    }

    @Test
    fun arbitraryConsumedReadChunksPreserveTypes() {
        val bytes = box("ftyp", ByteArray(16)) + moov("vide", "soun", "text")
        for (chunk in 1..31) assertEquals(
            Mp4TypeObserver.Types(true, true),
            feed(bytes, chunk).requireSnapshot(),
        )
    }

    @Test
    fun zeroAndExtendedSizeHeaders() {
        val bytes =
            box("free", ByteArray(9), extended = true) + box("moov", track("soun"), zero = true)
        assertEquals(Mp4TypeObserver.Types(false, true), feed(bytes, 3).requireSnapshot())
    }

    @Test
    fun metadataHandlerIsNotMediaDeclaration() {
        val metadata = box("meta", box("hdlr", ByteArray(8) + "vide".toByteArray()))
        assertEquals(
            Mp4TypeObserver.Types(false, true),
            feed(box("moov", metadata + track("soun"))).requireSnapshot(),
        )
    }

    @Test
    fun lateMoovAndResultSeekOverLargeMdat() {
        val observer = Mp4TypeObserver()
        val payloadSize = 4_000_000_000L
        val header = int(1) + "mdat".toByteArray() + long(payloadSize + 16)
        val metadata = moov("vide")
        val end = payloadSize + 16
        observer.consume(0, header, 0, header.size, end + metadata.size)
        observer.reposition(end)
        observer.consume(end, metadata, 0, metadata.size, end + metadata.size)
        assertTrue(observer.requireSnapshot().video)
    }

    @Test
    fun opaqueSkippedBytesDoNotNeedBuffering() {
        val observer = Mp4TypeObserver()
        val header = int(108) + "free".toByteArray()
        val metadata = moov("vide")
        observer.consume(0, header, 0, 8, (108 + metadata.size).toLong())
        observer.skip(8, 100)
        observer.consume(108, metadata, 0, metadata.size, (108 + metadata.size).toLong())
        assertTrue(observer.requireSnapshot().video)
    }

    @Test(expected = Mp4ObservationError::class)
    fun skippedHandlerIsFailClosed() {
        val bytes = box("moov", track("vide"))
        val observer = Mp4TypeObserver()
        observer.consume(0, bytes, 0, 32, bytes.size.toLong())
        observer.skip(32, 12)
    }

    @Test(expected = Mp4ObservationError::class)
    fun unknownSeekBeforeMetadataIsFailClosed() {
        Mp4TypeObserver().reposition(100)
    }

    @Test(expected = Mp4ObservationError::class)
    fun childCannotExceedParent() {
        feed(int(16) + "moov".toByteArray() + int(100) + "trak".toByteArray())
    }

    @Test(expected = Mp4ObservationError::class)
    fun unsigned64OverflowIsRejected() {
        feed(int(1) + "moov".toByteArray() + long(Long.MIN_VALUE))
    }

    @Test(expected = Mp4ObservationError::class)
    fun truncatedMetadataCannotBecomeAbsentVideo() {
        val bytes = moov("vide")
        val observer = Mp4TypeObserver()
        observer.consume(0, bytes, 0, bytes.size - 1, -1)
        observer.eof()
    }

    @Test(expected = Mp4ObservationError::class)
    fun shortHandlerIsRejected() {
        feed(box("moov", box("trak", box("mdia", box("hdlr", ByteArray(8))))))
    }

    @Test
    fun sampleSeekRetainsValidatedFactsWithoutEndTracksReplay() {
        val observer = feed(moov("vide", "soun"))
        observer.markValidated()
        val original = observer.types
        observer.seek(4000)
        observer.consume(4000, ByteArray(100), 0, 100, 10000)
        assertEquals(original, observer.types)
        // If a new endTracks occurred without observable metadata, it must fail closed.
        try {
            observer.requireSnapshot()
            fail()
        } catch (_: Mp4ObservationError) {}
    }

    @Test
    fun byteZeroReparseAndNewMoovResetDeclarations() {
        val first = moov("vide")
        val observer = feed(first)
        observer.markValidated()
        observer.seek(0)
        val second = moov("soun")
        observer.consume(0, second, 0, second.size, second.size.toLong())
        assertEquals(Mp4TypeObserver.Types(false, true), observer.requireSnapshot())
        observer.reset()
        assertEquals(0, observer.revision)
    }

    @Test
    fun indexProbeReturnsToExactExtendedMediaHeaderAndObservesLaterMoov() {
        val first = moov("vide")
        val media = box("moof", ByteArray(20), extended = true)
        val later = moov("soun")
        val length = first.size + media.size + later.size + 16L
        val observer = Mp4TypeObserver()
        observer.consume(0, first, 0, first.size, length)
        observer.markValidated()
        observer.consume(first.size.toLong(), media, 0, 16, length)
        observer.reposition(length - 16)
        observer.consume(length - 16, ByteArray(16), 0, 16, length)
        observer.reposition(first.size.toLong())
        val resumed = media + later
        observer.consume(first.size.toLong(), resumed, 0, resumed.size, length)
        assertEquals(Mp4TypeObserver.Types(false, true), observer.requireSnapshot())
        assertEquals(2, observer.revision)
    }

    @Test
    fun explicitSampleSeekCancelsIndexProbeReturnCheckpoint() {
        val first = moov("vide")
        val media = box("moof", ByteArray(20))
        val observer = Mp4TypeObserver()
        observer.consume(0, first, 0, first.size, 10000)
        observer.markValidated()
        observer.consume(first.size.toLong(), media, 0, 8, 10000)
        observer.reposition(9000)
        observer.seek(4000)
        observer.reposition(first.size.toLong())
        val opaque = moov("soun")
        observer.consume(first.size.toLong(), opaque, 0, opaque.size, 10000)
        assertEquals(Mp4TypeObserver.Types(true, false), observer.types)
        assertThrows(Mp4ObservationError::class.java) { observer.requireSnapshot() }
    }
}
