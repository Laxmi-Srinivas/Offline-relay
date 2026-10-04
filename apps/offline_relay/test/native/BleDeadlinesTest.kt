package dev.offlinerelay.offline_relay.ble

/** Dependency-free tests of the timer implementation used by the Android session. */
private class Clock {
    private data class Task(val at: Long, val run: () -> Unit, var cancelled: Boolean = false)
    private val tasks = mutableListOf<Task>()
    var now = 0L
    val callbacks = mutableListOf<() -> Unit>()

    fun schedule(delay: Long, run: () -> Unit): () -> Unit {
        val task = Task(now + delay, run)
        tasks.add(task)
        callbacks.add(run)
        return { task.cancelled = true }
    }

    fun advance(delta: Long) {
        now += delta
        val due = tasks.filter { it.at <= now }
        tasks.removeAll(due.toSet())
        due.filterNot { it.cancelled }.forEach { it.run() }
    }
}

fun main() {
    var passed = 0
    fun test(name: String, body: (Clock, BleDeadlines, MutableList<String>) -> Unit) {
        val clock = Clock()
        val expired = mutableListOf<String>()
        val deadlines = BleDeadlines(clock::schedule) { expired.add(it) }
        body(clock, deadlines, expired)
        passed++
        println("PASS $name")
    }
    val send = BleDeadlines.Operation.SEND
    val receive = BleDeadlines.Operation.RECEIVE
    val setup = BleDeadlines.Operation.SETUP

    test("completed receive does not cancel outstanding send") { clock, timers, expired ->
        timers.arm(send, "send")
        clock.advance(5_000)
        timers.arm(receive, "receive")
        timers.clear(receive)
        clock.advance(10_000)
        check(expired == listOf("send"))
    }
    test("inbound flood cannot extend send deadline") { clock, timers, expired ->
        timers.arm(send, "send")
        repeat(14) { clock.advance(1_000); timers.arm(receive, "receive"); timers.clear(receive) }
        clock.advance(1_000)
        check(expired == listOf("send"))
    }
    test("successful send does not cancel incomplete receive") { clock, timers, expired ->
        timers.arm(receive, "receive")
        timers.arm(send, "send")
        timers.clear(send)
        clock.advance(15_000)
        check(expired == listOf("receive"))
    }
    test("idle subscription expires at 15 seconds") { clock, timers, expired ->
        timers.arm(setup, "subscription")
        clock.advance(14_999)
        check(expired.isEmpty())
        clock.advance(1)
        check(expired == listOf("subscription"))
    }
    test("stale callback cannot expire a replacement timer") { clock, timers, expired ->
        timers.arm(send, "old")
        val stale = clock.callbacks.last()
        clock.advance(1_000)
        timers.arm(send, "new")
        stale()
        check(expired.isEmpty())
        clock.advance(15_000)
        check(expired == listOf("new"))
    }
    test("close clears every timer including queued callbacks") { clock, timers, expired ->
        timers.arm(send, "send"); timers.arm(receive, "receive"); timers.arm(setup, "setup")
        timers.clearAll()
        clock.callbacks.forEach { it() }
        clock.advance(15_000)
        check(expired.isEmpty())
    }
    println("$passed native deadline tests passed")
}
