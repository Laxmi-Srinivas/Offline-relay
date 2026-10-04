package dev.offlinerelay.offline_relay.ble

fun main() {
    var passed = 0
    fun test(name: String, run: () -> Unit) {
        run()
        passed++
        println("PASS: $name")
    }
    fun requested(): HelperConversation = HelperConversation().apply {
        begin("A")
        check(receiveRequest("A", "request-A", "First", byteArrayOf(1)))
    }
    test("notification cooldown spans reconnects without dropping requests") {
        val alerts = RequestAlertGate()
        check(alerts.allow(0))
        repeat(100) { check(!alerts.allow(it.toLong() + 1)) }
        check(!alerts.allow(9_999))
        check(alerts.allow(10_000))
        val state = requested()
        state.clear()
        state.begin("B")
        check(state.receiveRequest("B", "request-B", "B", byteArrayOf(1)))
        check(!alerts.allow(10_001))
        check(state.requestId == "request-B")
    }
    test("unapproved burst stores no chat") {
        val state = requested()
        repeat(20_000) { state.queueChat("A", ByteArray(256)) }
        check(state.queuedChat.size == 0 && state.queuedChat.byteCount == 0)
    }
    test("accepted backlog retains newest 300 bounded payloads") {
        val state = requested()
        check(state.resolve("A", "request-A", true))
        repeat(20_000) { state.queueChat("A", ByteArray(256) { (it % 128).toByte() }) }
        check(state.queuedChat.size == 300 && state.queuedChat.byteCount == 76_800)
        check(state.queuedChat.drain().size == 300)
        check(state.queuedChat.size == 0 && state.queuedChat.byteCount == 0)
    }
    test("replacement requests cannot change pending identity or decision") {
        val state = requested()
        repeat(20_000) { check(!state.receiveRequest("A", "new-$it", "Changed", byteArrayOf(2))) }
        check(state.requestId == "request-A" && state.requestName == "First")
        check(state.resolve("A", "request-A", true))
        check(!state.receiveRequest("A", "later", "Changed", byteArrayOf(2)))
        check(state.accepted)
    }
    test("stale approval and chat cannot affect a replacement session") {
        val state = requested()
        state.resolve("A", "request-A", true)
        state.queueChat("A", byteArrayOf(3))
        state.begin("B")
        check(state.queuedChat.size == 0 && state.requestId == null)
        state.receiveRequest("B", "request-B", "B", byteArrayOf(4))
        check(!state.resolve("A", "request-A", true))
        check(!state.resolve("B", "request-A", true))
        state.queueChat("A", byteArrayOf(5))
        check(!state.accepted && state.queuedChat.size == 0)
    }
    test("reject is final for that connection") {
        val state = requested()
        check(state.resolve("A", "request-A", false))
        check(!state.resolve("A", "request-A", true))
        state.queueChat("A", byteArrayOf(1))
        check(state.queuedChat.size == 0)
    }
    test("cleanup removes retained request and chat") {
        val state = requested()
        state.resolve("A", "request-A", true)
        state.queueChat("A", byteArrayOf(1))
        state.clear()
        check(state.connectionId == null && state.request == null && state.requestName == null)
        check(state.queuedChat.size == 0 && !state.accepted)
    }
    test("buffer enforces byte budget, order and defensive payload copies") {
        val buffer = BoundedEventBuffer(maxEvents = 4, maxBytes = 256)
        val bytes = ByteArray(128) { 1 }
        buffer.add(mapOf("message" to bytes, "id" to 1))
        bytes[0] = 9
        check((buffer.drain().single()["message"] as ByteArray)[0] == 1.toByte())
        repeat(5) { buffer.add(mapOf("message" to ByteArray(128), "id" to it)) }
        check(buffer.size == 2 && buffer.byteCount == 256)
        check(buffer.drain().map { it["id"] } == listOf(3, 4))
    }
    test("oversized payloads rejected and metadata-only events count bounded") {
        val buffer = BoundedEventBuffer(maxEvents = 4)
        buffer.add(mapOf("message" to ByteArray(257)))
        check(buffer.size == 0)
        repeat(10_000) { buffer.add(mapOf("event" to "peerDiscovered", "id" to it)) }
        check(buffer.size == 4 && buffer.byteCount == 0)
    }
    println("$passed helper conversation/buffer tests passed")
}
