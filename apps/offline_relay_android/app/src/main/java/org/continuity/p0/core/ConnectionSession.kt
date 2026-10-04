package org.continuity.p0.core

import org.continuity.p0.protocol.*
import org.continuity.p0.transport.*

data class Candidate(val id: String, val name: String)
data class ChatLine(val messageId: String, val text: String, val sentByMe: Boolean)
data class ConnectionState(
    val role: Role? = null, val phase: String = "IDLE", val status: String = "Choose a role to begin.",
    val peers: List<Candidate> = emptyList(), val endpoint: String? = null,
    val peerName: String = "", val digits: String? = null,
    val helloSent: Boolean = false, val helloReceived: Boolean = false,
    val remotePeerId: String? = null,
    val request: HelpMessage.Request? = null,
    val chat: List<ChatLine> = emptyList(),
)

/** Single-threaded main-loop session, with no Android/Nearby imports. */
class ConnectionSession(
    private val factory: () -> NearbyTransport,
    private val now: () -> Long,
    private val schedule: (Long, () -> Unit) -> (() -> Unit),
    private val changed: (ConnectionState) -> Unit,
) {
    var state = ConnectionState(); private set
    private var transport: NearbyTransport? = null
    private var epoch = 0
    private var timeout: (() -> Unit)? = null
    private var taskTimeout: (() -> Unit)? = null
    private var localHello: Hello? = null
    private var received: ByteArray? = null
    private val seenMessages = mutableMapOf<String, ByteArray>()
    private fun update(value: ConnectionState) { state = value; changed(value) }
    private fun shutdown() {
        epoch++; timeout?.invoke(); timeout = null
        taskTimeout?.invoke(); taskTimeout = null
        transport?.close(); transport = null; localHello = null; received = null; seenMessages.clear()
    }
    fun start(role: Role) {
        shutdown()
        update(ConnectionState(role, "STARTING", "Starting nearby session…"))
        val t = factory(); transport = t; val token = epoch
        t.listener = { if (token == epoch) event(it) }
        val done: Completion = done@ { error ->
            if (token != epoch) return@done
            if (error != null) fail(error)
            else if (state.phase == "STARTING") update(state.copy(
                phase = if (role == Role.HELPER) "ADVERTISING" else "DISCOVERING",
                status = if (role == Role.HELPER) "Available to help. Start discovery on the other phone."
                else "Searching. Start Helping on the other phone."))
        }
        if (role == Role.HELPER) t.startAdvertising("Helper", done) else t.startDiscovery(done)
    }
    fun connect(id: String) {
        if (state.phase != "DISCOVERING" || state.peers.none { it.id == id }) return
        update(state.copy(phase = "CONNECTING", status = "Connecting…", endpoint = id, peers = emptyList()))
        armConnectionTimeout()
        val token = epoch
        transport?.connect(id) { if (token == epoch && it != null) fail(it) }
    }
    private fun armConnectionTimeout() {
        timeout?.invoke(); val token = epoch
        timeout = schedule(60_000) { if (token == epoch) fail("CONNECTION_FAILED: connection timed out") }
    }
    fun confirm(approved: Boolean) {
        if (state.phase != "VERIFYING") return
        val id = state.endpoint ?: return
        if (!approved) {
            transport?.confirmConnection(id, false) {}
            fail("CONNECTION_REJECTED"); return
        }
        update(state.copy(phase = "WAITING", digits = null, status = "Waiting for the other phone to confirm…"))
        val token = epoch
        transport?.confirmConnection(id, true) { if (token == epoch && it != null) fail(it) }
    }
    fun stop() {
        shutdown(); update(ConnectionState(status = "Disconnected. Choose roles again on both phones to reconnect."))
    }
    fun fail(message: String) {
        val role = state.role; shutdown()
        update(ConnectionState(role = role, phase = "ERROR", status = message))
    }

    fun sendRequest(category: HelpCategory, details: String) {
        if (state.phase != "READY" || state.role != Role.REQUESTER) return
        if (!HelpMessageCodec.validText(details, HelpMessageCodec.MAX_REQUEST_BYTES)) return
        val request = try { HelpMessageCodec.newRequest(category, details.trim(), now()) }
            catch (_: Exception) { return }
        val endpoint = state.endpoint ?: return
        val token = epoch
        update(state.copy(phase = "WAITING_ACCEPT", status = "Request sent. Waiting for the helper…", request = request))
        armTaskTimeout(request)
        val bytes = outgoingBytes(request) ?: return
        transport?.send(endpoint, bytes) { error ->
            if (token == epoch && error != null) fail(error)
        }
    }

    fun acceptRequest() {
        val request = state.request ?: return
        if (state.phase != "REQUEST_RECEIVED" || state.role != Role.HELPER) return
        if (expireIfDue(request)) return
        val endpoint = state.endpoint ?: return
        val token = epoch
        update(state.copy(phase = "CHAT", status = "Request accepted. Chat directly with the requester."))
        armTaskTimeout(request)
        val bytes = outgoingBytes(HelpMessageCodec.accept(request)) ?: return
        transport?.send(endpoint, bytes) { error ->
            if (token == epoch && error != null) fail(error)
        }
    }

    fun declineRequest() {
        val request = state.request ?: return
        if (state.phase != "REQUEST_RECEIVED" || state.role != Role.HELPER) return
        if (expireIfDue(request)) return
        val endpoint = state.endpoint ?: return
        val token = epoch
        taskTimeout?.invoke(); taskTimeout = null
        update(state.copy(phase = "TASK_DECLINED", status = "You declined this request."))
        val bytes = outgoingBytes(HelpMessageCodec.decline(request)) ?: return
        transport?.send(endpoint, bytes) { error ->
            if (token == epoch && error != null) fail(error)
        }
    }

    fun sendChat(text: String) {
        val request = state.request ?: return
        if (state.phase != "CHAT" || !HelpMessageCodec.validText(text.trim(), HelpMessageCodec.MAX_CHAT_BYTES)) return
        if (expireIfDue(request)) return
        val endpoint = state.endpoint ?: return
        val message = try { HelpMessageCodec.chat(request.taskId, request.createdAt, request.expiresAt, text.trim()) }
            catch (_: Exception) { return }
        val token = epoch
        update(state.copy(chat = state.chat + ChatLine(message.messageId, message.text, sentByMe = true)))
        val bytes = outgoingBytes(message) ?: return
        transport?.send(endpoint, bytes) { error ->
            if (token == epoch && error != null) fail(error)
        }
    }

    fun endHelp() {
        val request = state.request ?: return
        if (state.phase != "CHAT") return
        if (expireIfDue(request)) return
        val endpoint = state.endpoint ?: return
        val token = epoch
        update(state.copy(phase = "TASK_ENDED", status = "Help session ended."))
        taskTimeout?.invoke(); taskTimeout = null
        val bytes = outgoingBytes(HelpMessageCodec.end(request.taskId, request.createdAt, request.expiresAt)) ?: return
        transport?.send(endpoint, bytes) { error ->
            if (token == epoch && error != null) fail(error)
        }
    }

    private fun armTaskTimeout(request: HelpMessage.Request) {
        taskTimeout?.invoke()
        val token = epoch
        val remaining = (request.expiresAt - now()).coerceAtLeast(0)
        taskTimeout = schedule(remaining) {
            if (token == epoch && state.phase in setOf("WAITING_ACCEPT", "REQUEST_RECEIVED", "CHAT")) {
                taskTimeout = null
                update(state.copy(phase = "TASK_EXPIRED", status = "This help request expired."))
            }
        }
    }

    private fun expireIfDue(request: HelpMessage.Request): Boolean {
        if (now() < request.expiresAt) return false
        taskTimeout?.invoke(); taskTimeout = null
        update(state.copy(phase = "TASK_EXPIRED", status = "This help request expired."))
        return true
    }

    private fun outgoingBytes(message: HelpMessage): ByteArray? {
        if (seenMessages.size >= 128) { fail("LIMIT_REACHED"); return null }
        val bytes = try { HelpMessageCodec.encode(message) } catch (_: Exception) {
            fail("INVALID_MESSAGE"); return null
        }
        seenMessages[message.messageId] = bytes.copyOf()
        return bytes
    }

    private fun receiveHelpMessage(endpointId: String, bytes: ByteArray) {
        if (state.endpoint != endpointId || state.phase !in setOf("READY", "WAITING_ACCEPT", "REQUEST_RECEIVED", "CHAT")) return
        val message = try { HelpMessageCodec.decode(bytes, now()) }
            catch (error: HelpMessageRejected) {
                if (error.code == "EXPIRED") update(state.copy(phase = "TASK_EXPIRED", status = "This help request expired."))
                else fail(error.code)
                return
            } catch (_: Exception) { fail("INVALID_MESSAGE"); return }
        val previous = seenMessages[message.messageId]
        if (previous != null) {
            if (!previous.contentEquals(bytes)) fail("INVALID_MESSAGE")
            return
        }
        if (seenMessages.size >= 128) { fail("LIMIT_REACHED"); return }
        seenMessages[message.messageId] = bytes.copyOf()

        when (message) {
            is HelpMessage.Request -> {
                if (state.phase != "READY" || state.role != Role.HELPER || state.request != null ||
                    state.remotePeerId == null) { fail("UNAUTHORIZED_PEER"); return }
                update(state.copy(phase = "REQUEST_RECEIVED", status = "A nearby person is asking for help.", request = message))
                armTaskTimeout(message)
            }
            is HelpMessage.Accept -> {
                val request = state.request
                if (state.phase != "WAITING_ACCEPT" || state.role != Role.REQUESTER ||
                    request == null || !sameTask(request, message)) { fail("INVALID_STATE"); return }
                update(state.copy(phase = "CHAT", status = "The helper accepted. You can chat now."))
                armTaskTimeout(request)
            }
            is HelpMessage.Decline -> {
                val request = state.request
                if (state.phase != "WAITING_ACCEPT" || state.role != Role.REQUESTER ||
                    request == null || !sameTask(request, message)) { fail("INVALID_STATE"); return }
                taskTimeout?.invoke(); taskTimeout = null
                update(state.copy(phase = "TASK_DECLINED", status = "The helper declined this request."))
            }
            is HelpMessage.Chat -> {
                val request = state.request
                if (state.phase != "CHAT" || request == null || !sameTask(request, message)) {
                    fail("INVALID_STATE"); return
                }
                update(state.copy(chat = state.chat + ChatLine(message.messageId, message.text, sentByMe = false)))
            }
            is HelpMessage.End -> {
                val request = state.request
                if (state.phase != "CHAT" || request == null || !sameTask(request, message)) {
                    fail("INVALID_STATE"); return
                }
                taskTimeout?.invoke(); taskTimeout = null
                update(state.copy(phase = "TASK_ENDED", status = "The other person ended the help session."))
            }
        }
    }

    private fun sameTask(request: HelpMessage.Request, message: HelpMessage): Boolean =
        request.taskId == message.taskId && request.createdAt == message.createdAt && request.expiresAt == message.expiresAt

    private fun event(e: TransportEvent) {
        when (e) {
            is TransportEvent.PeerFound -> if (state.phase == "DISCOVERING" && HelloCodec.validName(e.displayName)) {
                val peers = state.peers.filterNot { it.id == e.endpointId }
                if (peers.size < 20) update(state.copy(peers = peers + Candidate(e.endpointId, e.displayName)))
            }
            is TransportEvent.PeerLost -> update(state.copy(peers = state.peers.filterNot { it.id == e.endpointId }))
            is TransportEvent.VerificationRequired -> {
                if (state.phase !in setOf("STARTING", "ADVERTISING", "CONNECTING")) return
                if (state.endpoint != null && state.endpoint != e.endpointId) return
                if (!HelloCodec.validName(e.displayName)) { fail("INVALID_MESSAGE"); return }
                armConnectionTimeout()
                update(state.copy(phase = "VERIFYING", endpoint = e.endpointId,
                    peerName = e.displayName, digits = e.digits, peers = emptyList(),
                    status = "Compare the code with the other phone."))
            }
            is TransportEvent.Connected -> {
                if (state.phase != "WAITING" || state.endpoint != e.endpointId) return
                update(state.copy(phase = "CONNECTED", status = "Verified connection. Exchanging HELLO…"))
                timeout?.invoke(); val token = epoch
                timeout = schedule(30_000) { if (token == epoch) fail("CONNECTION_FAILED: HELLO timed out") }
                val h = HelloCodec.create(if (state.role == Role.HELPER) "Helper" else "Requester", state.role!!, now())
                localHello = h
                transport?.send(e.endpointId, HelloCodec.encode(h)) { error ->
                    if (token == epoch) {
                        if (error != null) fail(error) else { update(state.copy(helloSent = true)); ready() }
                    }
                }
            }
            is TransportEvent.BytesReceived -> {
                if (state.endpoint != e.endpointId || state.phase !in setOf(
                        "CONNECTED", "READY", "WAITING_ACCEPT", "REQUEST_RECEIVED", "CHAT")) return
                if (received != null) {
                    if (received!!.contentEquals(e.bytes)) return
                    if (state.helloReceived && state.helloSent) receiveHelpMessage(e.endpointId, e.bytes)
                    return
                }
                val h = try { HelloCodec.decode(e.bytes, now()) } catch (error: HelloRejected) {
                    fail(error.code); return
                } catch (_: Exception) {
                    fail("INVALID_MESSAGE: invalid or expired HELLO"); return
                }
                if (h.role == state.role || h.peerId == localHello?.peerId) {
                    fail("UNAUTHORIZED_PEER: choose opposite roles"); return
                }
                received = e.bytes.copyOf()
                update(state.copy(helloReceived = true, peerName = h.displayName, remotePeerId = h.peerId))
                ready()
            }
            is TransportEvent.Disconnected -> if (state.endpoint == e.endpointId) fail("CONNECTION_LOST")
            is TransportEvent.Error -> fail(e.code)
        }
    }
    private fun ready() {
        if (state.helloSent && state.helloReceived) {
            timeout?.invoke(); timeout = null
            update(state.copy(phase = "READY", status = "READY — HELLO sent and received."))
        }
    }
}
