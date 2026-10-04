package org.continuity.p0

import org.continuity.p0.core.*
import org.continuity.p0.protocol.*
import org.continuity.p0.transport.*
import org.junit.Assert.*
import org.junit.Test

class ConnectionSessionTest {
    private class Fake : NearbyTransport {
        override var listener: (TransportEvent) -> Unit = {}
        var confirmCount = 0
        var closed = false
        var sent = 0
        val payloads = mutableListOf<ByteArray>()
        var completion: Completion? = null
        var immediateSend = true
        override fun startAdvertising(displayName: String, done: Completion) = done(null)
        override fun stopAdvertising() {}
        override fun startDiscovery(done: Completion) = done(null)
        override fun stopDiscovery() {}
        override fun connect(endpointId: String, done: Completion) = done(null)
        override fun confirmConnection(endpointId: String, approved: Boolean, done: Completion) { if (approved) confirmCount++; done(null) }
        override fun send(endpointId: String, bytes: ByteArray, done: Completion) {
            sent++; payloads.add(bytes.copyOf()); completion = done; if (immediateSend) done(null)
        }
        override fun disconnect(endpointId: String) {}
        override fun close() { closed = true }
    }
    private val now = 1_700_000_000_000L
    private val adapters = mutableListOf<Fake>()
    private val timers = mutableListOf<() -> Unit>()
    private val s = ConnectionSession(
        { Fake().also { adapters.add(it) } }, { now },
        { _, action ->
            var cancelled = false
            timers.add { if (!cancelled) action() }
            val cancel: () -> Unit = { cancelled = true }; cancel
        }, {},
    )
    private val t get() = adapters.last()
    private fun begin() {
        s.start(Role.REQUESTER)
        t.listener(TransportEvent.PeerFound("bob", "Helper"))
        s.connect("bob")
        t.listener(TransportEvent.VerificationRequired("bob", "Helper", "1234"))
    }
    private fun connected() { begin(); s.confirm(true); t.listener(TransportEvent.Connected("bob")) }
    private fun helperConnected() {
        s.start(Role.HELPER)
        t.listener(TransportEvent.VerificationRequired("alice", "Requester", "1234"))
        s.confirm(true); t.listener(TransportEvent.Connected("alice"))
        t.listener(TransportEvent.BytesReceived("alice", remote(Role.REQUESTER)))
    }
    private fun remote(role: Role = Role.HELPER) = HelloCodec.encode(HelloCodec.create("Helper", role, now))
    @Test fun noConnectionAcceptanceBeforeUserConfirmation() {
        begin(); assertEquals(0, t.confirmCount)
        t.listener(TransportEvent.Connected("bob"))
        assertEquals("VERIFYING", s.state.phase); assertEquals(0, t.sent)
    }
    @Test fun bidirectionalHelloReachesReady() {
        connected(); assertEquals("CONNECTED", s.state.phase)
        t.listener(TransportEvent.BytesReceived("bob", remote()))
        assertEquals("READY", s.state.phase); assertTrue(s.state.helloSent); assertTrue(s.state.helloReceived)
        assertNotNull(s.state.remotePeerId)
    }
    @Test fun mustSendAndReceiveBeforeReady() {
        begin(); t.immediateSend = false; s.confirm(true); t.listener(TransportEvent.Connected("bob"))
        t.listener(TransportEvent.BytesReceived("bob", remote()))
        assertEquals("CONNECTED", s.state.phase)
        t.completion!!(null); assertEquals("READY", s.state.phase)
    }
    @Test fun rejectConnectionNeverSendsHello() {
        begin(); val old = t; s.confirm(false)
        assertEquals("ERROR", s.state.phase); assertTrue(old.closed); assertEquals(0, old.sent)
    }
    @Test fun ignoresWrongEndpointPayload() {
        connected(); t.listener(TransportEvent.BytesReceived("eve", remote()))
        assertFalse(s.state.helloReceived)
    }
    @Test fun rejectsSameRole() {
        connected(); t.listener(TransportEvent.BytesReceived("bob", remote(Role.REQUESTER)))
        assertEquals("ERROR", s.state.phase)
    }
    @Test fun ignoresIdenticalDuplicate() {
        connected(); val bytes = remote()
        t.listener(TransportEvent.BytesReceived("bob", bytes)); t.listener(TransportEvent.BytesReceived("bob", bytes))
        assertEquals("READY", s.state.phase)
    }
    @Test fun rejectsSecondDistinctHello() {
        connected(); t.listener(TransportEvent.BytesReceived("bob", remote()))
        t.listener(TransportEvent.BytesReceived("bob", remote()))
        assertEquals("ERROR", s.state.phase)
    }
    @Test fun timeoutClosesConnection() {
        connected(); val old = t; timers.last()()
        assertEquals("ERROR", s.state.phase); assertTrue(old.closed)
    }
    @Test fun readyCancelsHelloTimeout() {
        connected(); t.listener(TransportEvent.BytesReceived("bob", remote()))
        timers.forEach { it() }; assertEquals("READY", s.state.phase)
    }
    @Test fun oldSessionCallbacksCannotChangeRestartedState() {
        connected(); val callback = t.listener; val completion = t.completion!!
        s.stop(); s.start(Role.HELPER)
        callback(TransportEvent.Error("OLD_ERROR")); completion("SEND_FAILED")
        assertEquals("ADVERTISING", s.state.phase); assertFalse(s.state.helloReceived)
    }
    @Test fun disconnectClearsIdentityAndFlags() {
        connected(); t.listener(TransportEvent.BytesReceived("bob", remote()))
        t.listener(TransportEvent.Disconnected("bob"))
        assertEquals("ERROR", s.state.phase); assertNull(s.state.remotePeerId)
        assertFalse(s.state.helloSent); assertFalse(s.state.helloReceived)
    }
    @Test fun ignoresHelloBeforeVerification() {
        begin(); t.listener(TransportEvent.BytesReceived("bob", remote()))
        assertFalse(s.state.helloReceived)
    }
    @Test fun malformedHelloFailsSafely() {
        connected(); t.listener(TransportEvent.BytesReceived("bob", byteArrayOf(0)))
        assertEquals("ERROR", s.state.phase)
    }

    @Test fun requesterCanRequestAcceptChatAndEndOfflineSession() {
        connected(); t.listener(TransportEvent.BytesReceived("bob", remote()))
        s.sendRequest(HelpCategory.FOOD, "Help me place a food order")
        assertEquals("WAITING_ACCEPT", s.state.phase)
        val request = s.state.request!!
        t.listener(TransportEvent.BytesReceived("bob", HelpMessageCodec.encode(HelpMessageCodec.accept(request))))
        assertEquals("CHAT", s.state.phase)
        s.sendChat("Can you help order from the cafe?")
        assertEquals("Can you help order from the cafe?", s.state.chat.single().text)
        val reply = HelpMessageCodec.chat(request.taskId, request.createdAt, request.expiresAt, "Sure, what would you like?")
        t.listener(TransportEvent.BytesReceived("bob", HelpMessageCodec.encode(reply)))
        assertEquals(2, s.state.chat.size)
        assertFalse(s.state.chat.last().sentByMe)
        s.endHelp()
        assertEquals("TASK_ENDED", s.state.phase)
    }

    @Test fun helperMustAcceptBeforeChat() {
        helperConnected()
        val request = HelpMessageCodec.newRequest(HelpCategory.RIDE, "Help me arrange a ride", now)
        t.listener(TransportEvent.BytesReceived("alice", HelpMessageCodec.encode(request)))
        assertEquals("REQUEST_RECEIVED", s.state.phase)
        s.acceptRequest()
        assertEquals("CHAT", s.state.phase)
        assertTrue(HelpMessageCodec.decode(t.payloads.last(), now) is HelpMessage.Accept)
    }

    @Test fun helperCanDeclineAndRequesterSeesIt() {
        connected(); t.listener(TransportEvent.BytesReceived("bob", remote()))
        s.sendRequest(HelpCategory.OTHER, "Please check this information")
        val request = s.state.request!!
        val decline = HelpMessageCodec.decline(request)
        t.listener(TransportEvent.BytesReceived("bob", HelpMessageCodec.encode(decline)))
        assertEquals("TASK_DECLINED", s.state.phase)
    }

    @Test fun chatBeforeAcceptanceIsRejected() {
        helperConnected()
        val request = HelpMessageCodec.newRequest(HelpCategory.OTHER, "Check a sign", now)
        t.listener(TransportEvent.BytesReceived("alice", HelpMessageCodec.encode(request)))
        val chat = HelpMessageCodec.chat(request.taskId, request.createdAt, request.expiresAt, "Hello")
        t.listener(TransportEvent.BytesReceived("alice", HelpMessageCodec.encode(chat)))
        assertEquals("ERROR", s.state.phase)
    }
}
