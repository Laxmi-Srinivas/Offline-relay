package dev.offlinerelay.offline_relay.ble

import java.util.ArrayDeque

/** Notification cooldown survives peer disconnect/reconnect within this service lifetime. */
internal class RequestAlertGate(private val intervalMillis: Long = 10_000) {
    private var lastAlert: Long? = null
    fun allow(nowMillis: Long): Boolean {
        val previous = lastAlert
        if (previous != null && nowMillis - previous < intervalMillis) return false
        lastAlert = nowMillis
        return true
    }
}

/** In-memory delivery backlog. Drop oldest events rather than retaining unlimited input. */
internal class BoundedEventBuffer(
    private val maxEvents: Int = 300,
    private val maxBytes: Int = 300 * 256,
) {
    private val events = ArrayDeque<Map<String, Any?>>()
    var byteCount: Int = 0
        private set
    val size: Int get() = events.size

    init { require(maxEvents > 0 && maxBytes >= 256) }

    fun add(event: Map<String, Any?>) {
        val payload = event["message"] as? ByteArray
        if (payload != null && (payload.isEmpty() || payload.size > 256)) return
        val bytes = payload?.size ?: 0
        while (events.size >= maxEvents || byteCount + bytes > maxBytes) {
            byteCount -= (events.removeFirst()["message"] as? ByteArray)?.size ?: 0
        }
        val copy = event.toMutableMap()
        if (payload != null) copy["message"] = payload.clone()
        events.addLast(copy)
        byteCount += bytes
    }

    fun drain(): List<Map<String, Any?>> = events.toList().also { clear() }

    fun clear() {
        events.clear()
        byteCount = 0
    }
}

/** One request and decision per live helper connection; never a cross-session approval. */
internal class HelperConversation {
    var connectionId: String? = null
        private set
    var requestId: String? = null
        private set
    var requestName: String? = null
        private set
    private var requestBytes: ByteArray? = null
    var resolved = false
        private set
    var accepted = false
        private set
    val request: ByteArray? get() = requestBytes?.clone()
    val queuedChat = BoundedEventBuffer()

    fun begin(id: String) {
        clear()
        connectionId = id
    }

    fun receiveRequest(id: String, requestId: String, name: String, bytes: ByteArray): Boolean {
        if (connectionId != id || this.requestId != null || resolved ||
            requestId.isBlank() || name.isBlank() || bytes.isEmpty() || bytes.size > 256) return false
        this.requestId = requestId
        requestName = name
        requestBytes = bytes.clone()
        return true
    }

    fun resolve(id: String, requestId: String, accept: Boolean): Boolean {
        if (connectionId != id || this.requestId != requestId || resolved) return false
        resolved = true
        accepted = accept
        return true
    }

    fun permitsChat(id: String): Boolean = connectionId == id && accepted

    fun queueChat(id: String, bytes: ByteArray) {
        if (permitsChat(id)) queuedChat.add(mapOf(
            "event" to "message", "connectionId" to id, "message" to bytes,
        ))
    }

    fun clear() {
        connectionId = null
        requestId = null
        requestName = null
        requestBytes = null
        resolved = false
        accepted = false
        queuedChat.clear()
    }
}
