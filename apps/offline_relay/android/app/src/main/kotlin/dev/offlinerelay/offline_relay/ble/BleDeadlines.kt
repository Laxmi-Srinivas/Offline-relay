package dev.offlinerelay.offline_relay.ble

/** Independent operation deadlines; a receive must never cancel a pending send. */
internal class BleDeadlines(
    private val schedule: (Long, () -> Unit) -> (() -> Unit),
    private val expired: (String) -> Unit,
) {
    enum class Operation { SETUP, SEND, RECEIVE }

    private data class Pending(val token: Any, val cancel: () -> Unit)
    private val pending = mutableMapOf<Operation, Pending>()

    fun arm(operation: Operation, stage: String) {
        clear(operation)
        val token = Any()
        val cancel = schedule(15_000) {
            // Cancelled callbacks may already have been queued by the platform.
            if (pending[operation]?.token === token) {
                pending.remove(operation)
                expired(stage)
            }
        }
        pending[operation] = Pending(token, cancel)
    }

    fun clear(operation: Operation) {
        pending.remove(operation)?.cancel?.invoke()
    }

    fun clearAll() {
        val cancellations = pending.values.map { it.cancel }
        pending.clear()
        cancellations.forEach { it() }
    }
}
