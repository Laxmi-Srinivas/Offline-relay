package dev.offlinerelay.offline_relay.ble

fun main() {
    val queue = BleOperationQueue(2)
    val calls = mutableListOf<String>()
    check(queue.add { calls.add("first") })
    check(queue.add { calls.add("second") })
    check(calls == listOf("first"))
    check(queue.size == 2)
    check(!queue.add { calls.add("overflow") })
    queue.complete()
    check(calls == listOf("first", "second"))
    check(queue.size == 1)
    queue.complete()
    check(queue.size == 0)
    check(queue.add { calls.add("old") })
    check(queue.add { calls.add("discarded") })
    queue.clear()
    check(queue.size == 0)
    check(queue.add { calls.add("replacement") })
    check(!calls.contains("discarded"))
    val burst = BleOperationQueue()
    repeat(64) { check(burst.add {}) }
    repeat(20_000) { check(!burst.add {}) }
    check(burst.size == 64)
    val gate = RequestAlertGate()
    check(gate.allow(100))
    check(!gate.allow(101))
    check(!gate.allow(10_099))
    check(gate.allow(10_100))
    println("PASS: GATT serialization, in-flight bound, overflow, drain, clear/replacement, 20,000-operation burst and notification cooldown")
}
