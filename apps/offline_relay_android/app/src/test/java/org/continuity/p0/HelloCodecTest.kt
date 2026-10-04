package org.continuity.p0

import org.continuity.p0.protocol.*
import org.junit.Assert.*
import org.junit.Test

class HelloCodecTest {
    private val now = 1_700_000_000_000L
    private fun sample() = HelloCodec.create("Bob \"B\" \\ test", Role.HELPER, now)
    private fun rejected(bytes: ByteArray, time: Long = now) {
        try { HelloCodec.decode(bytes, time); fail("Accepted invalid HELLO") }
        catch (_: IllegalArgumentException) { }
        catch (_: IllegalStateException) { }
        catch (_: java.nio.charset.CharacterCodingException) { }
    }
    private fun wire() = HelloCodec.encode(sample()).toString(Charsets.UTF_8)
    @Test fun roundTripAndEscaping() { val h = sample(); assertEquals(h, HelloCodec.decode(HelloCodec.encode(h), now)) }
    @Test fun rejectsDuplicateKey() { rejected(wire().replace("\"version\":1", "\"version\":1,\"version\":1").toByteArray()) }
    @Test fun rejectsUnknownField() { rejected(wire().replace("\"version\":1", "\"extra\":1,\"version\":1").toByteArray()) }
    @Test fun rejectsDuplicatePayloadKey() { rejected(wire().replace("\"role\":", "\"role\":\"HELPER\",\"role\":").toByteArray()) }
    @Test fun rejectsTaskIdOnHello() { rejected(wire().replace("\"version\":1", "\"taskId\":\"x\",\"version\":1").toByteArray()) }
    @Test fun rejectsUnsupportedVersion() { rejected(wire().replace("\"version\":1", "\"version\":2").toByteArray()) }
    @Test fun rejectsStringVersion() { rejected(wire().replace("\"version\":1", "\"version\":\"1\"").toByteArray()) }
    @Test fun rejectsTrailingContent() { rejected((wire() + "{}").toByteArray()) }
    @Test fun rejectsTrailingComma() { rejected(wire().dropLast(1).plus(",}").toByteArray()) }
    @Test fun rejectsMalformedUtf8() { rejected(byteArrayOf(0xc3.toByte(), 0x28)) }
    @Test fun rejectsOversizeBeforeParsing() { rejected(ByteArray(8193)) }
    @Test fun rejectsExpiredAtBoundary() { rejected(HelloCodec.encode(sample()), now + 30_000) }
    @Test fun rejectsFutureClockSkew() { rejected(HelloCodec.encode(sample().copy(createdAt = now + 30_001, expiresAt = now + 60_001))) }
    @Test fun rejectsWrongLifetime() { rejected(HelloCodec.encode(sample().copy(expiresAt = now + 60_000))) }
    @Test fun rejectsInvalidUuid() { rejected(HelloCodec.encode(sample().copy(peerId = "not-an-id"))) }
    @Test fun rejectsLongName() { rejected(HelloCodec.encode(sample().copy(displayName = "a".repeat(41)))) }
    @Test fun rejectsUnpairedSurrogate() { rejected(wire().replace("HELPER", "\\ud800").toByteArray()) }
    @Test fun rejectsNullAndArray() {
        rejected(wire().replace("\"version\":1", "\"version\":null").toByteArray())
        rejected(wire().replace("\"version\":1", "\"version\":[]").toByteArray())
    }
    @Test fun reportsUnsupportedVersionCode() {
        val bytes = wire().replace("\"version\":1", "\"version\":2").toByteArray()
        try { HelloCodec.decode(bytes, now); fail("Must reject") }
        catch (e: HelloRejected) { assertEquals("UNSUPPORTED_VERSION", e.code) }
    }
    @Test fun reportsExpiredCode() {
        try { HelloCodec.decode(HelloCodec.encode(sample()), now + 30_000); fail("Must reject") }
        catch (e: HelloRejected) { assertEquals("EXPIRED", e.code) }
    }
}
