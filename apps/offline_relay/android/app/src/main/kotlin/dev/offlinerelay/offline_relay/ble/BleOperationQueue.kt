package dev.offlinerelay.offline_relay.ble

import java.util.ArrayDeque

/** Main-thread GATT work, including its in-flight operation, has a finite bound. */
internal class BleOperationQueue(private val capacity: Int = 64) {
    private val pending = ArrayDeque<() -> Unit>()
    private var busy = false
    val size: Int get() = pending.size + if (busy) 1 else 0
    init { require(capacity > 0) }
    fun add(operation: () -> Unit): Boolean {
        if (size >= capacity) return false
        pending.addLast(operation)
        runNext()
        return true
    }
    fun complete() { busy = false; runNext() }
    fun clear() { pending.clear(); busy = false }
    private fun runNext() {
        if (!busy && pending.isNotEmpty()) {
            busy = true
            pending.removeFirst()()
        }
    }
}
