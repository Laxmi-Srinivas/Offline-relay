package org.continuity.p0

import org.continuity.p0.protocol.*
import org.junit.Assert.*
import org.junit.Test

class HelpMessageCodecTest {
    private val now = 1_700_000_000_000L

    @Test fun requestRoundTripsAllCategoriesAndUnicode() {
        for (category in HelpCategory.entries) {
            val request = HelpMessageCodec.newRequest(category, "Please help me order food 🍜", now)
            assertEquals(request, HelpMessageCodec.decode(HelpMessageCodec.encode(request), now))
        }
    }

    @Test fun acceptChatAndEndKeepTaskBinding() {
        val request = HelpMessageCodec.newRequest(HelpCategory.RIDE, "Need help arranging a ride", now)
        val messages = listOf(
            HelpMessageCodec.accept(request),
            HelpMessageCodec.decline(request),
            HelpMessageCodec.chat(request.taskId, request.createdAt, request.expiresAt, "What is the pickup point?"),
            HelpMessageCodec.end(request.taskId, request.createdAt, request.expiresAt),
        )
        messages.forEach { assertEquals(it, HelpMessageCodec.decode(HelpMessageCodec.encode(it), now)) }
    }

    @Test fun rejectsExpiredAndOversizedMessages() {
        val request = HelpMessageCodec.newRequest(HelpCategory.OTHER, "Check the venue sign", now)
        try {
            HelpMessageCodec.decode(HelpMessageCodec.encode(request), request.expiresAt)
            fail("expired request accepted")
        } catch (e: HelpMessageRejected) { assertEquals("EXPIRED", e.code) }
        try {
            HelpMessageCodec.newRequest(HelpCategory.FOOD, "x".repeat(HelpMessageCodec.MAX_REQUEST_BYTES + 1), now)
            fail("oversize request accepted")
        } catch (_: IllegalArgumentException) { }
    }

    @Test fun rejectsUnknownFieldsAndInvalidText() {
        val request = HelpMessageCodec.newRequest(HelpCategory.OTHER, "Check the sign", now)
        val wire = HelpMessageCodec.encode(request).toString(Charsets.UTF_8)
            .replace("\"details\":", "\"extra\":true,\"details\":")
        try {
            HelpMessageCodec.decode(wire.toByteArray(), now)
            fail("unknown field accepted")
        } catch (e: HelpMessageRejected) { assertEquals("INVALID_MESSAGE", e.code) }
        assertFalse(HelpMessageCodec.validText("\u0001bad", HelpMessageCodec.MAX_CHAT_BYTES))
        assertFalse(HelpMessageCodec.validText("\uD800", HelpMessageCodec.MAX_CHAT_BYTES))
    }
}
