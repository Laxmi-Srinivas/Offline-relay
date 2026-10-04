package org.continuity.p0.protocol

import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction
import java.util.UUID

enum class HelpCategory { FOOD, RIDE, OTHER }

sealed interface HelpMessage {
    val messageId: String
    val taskId: String
    val createdAt: Long
    val expiresAt: Long

    data class Request(
        override val messageId: String, override val taskId: String,
        override val createdAt: Long, override val expiresAt: Long,
        val category: HelpCategory, val details: String,
    ) : HelpMessage

    data class Accept(
        override val messageId: String, override val taskId: String,
        override val createdAt: Long, override val expiresAt: Long,
    ) : HelpMessage

    data class Decline(
        override val messageId: String, override val taskId: String,
        override val createdAt: Long, override val expiresAt: Long,
    ) : HelpMessage

    data class Chat(
        override val messageId: String, override val taskId: String,
        override val createdAt: Long, override val expiresAt: Long,
        val text: String,
    ) : HelpMessage

    data class End(
        override val messageId: String, override val taskId: String,
        override val createdAt: Long, override val expiresAt: Long,
    ) : HelpMessage
}

class HelpMessageRejected(val code: String) : IllegalArgumentException(code)

/** Strict, bounded wire codec for one request and its temporary text conversation. */
object HelpMessageCodec {
    const val TASK_LIFETIME_MS = 300_000L
    const val MAX_REQUEST_BYTES = 500
    const val MAX_CHAT_BYTES = 1000
    private const val MAX_MESSAGE_BYTES = 8192
    private val uuid = Regex("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")

    fun newRequest(category: HelpCategory, details: String, now: Long): HelpMessage.Request {
        require(now > 0 && now <= Long.MAX_VALUE - TASK_LIFETIME_MS)
        require(validText(details, MAX_REQUEST_BYTES))
        return HelpMessage.Request(UUID.randomUUID().toString(), UUID.randomUUID().toString(), now,
            now + TASK_LIFETIME_MS, category, details)
    }

    fun accept(request: HelpMessage.Request) = HelpMessage.Accept(UUID.randomUUID().toString(), request.taskId,
        request.createdAt, request.expiresAt)
    fun decline(request: HelpMessage.Request) = HelpMessage.Decline(UUID.randomUUID().toString(), request.taskId,
        request.createdAt, request.expiresAt)
    fun chat(taskId: String, createdAt: Long, expiresAt: Long, text: String): HelpMessage.Chat {
        require(validText(text, MAX_CHAT_BYTES))
        return HelpMessage.Chat(UUID.randomUUID().toString(), taskId, createdAt, expiresAt, text)
    }
    fun end(taskId: String, createdAt: Long, expiresAt: Long) = HelpMessage.End(UUID.randomUUID().toString(),
        taskId, createdAt, expiresAt)

    fun validText(text: String, maxBytes: Int): Boolean {
        if (text.isBlank() || text.any { it.code < 32 && it != '\n' && it != '\t' }) return false
        return try {
            val encoded = Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).encode(CharBuffer.wrap(text))
            encoded.remaining() <= maxBytes
        } catch (_: Exception) { false }
    }

    fun encode(message: HelpMessage): ByteArray {
        val payload = when (message) {
            is HelpMessage.Request -> "\"category\":${quote(message.category.name)},\"details\":${quote(message.details)}"
            is HelpMessage.Accept, is HelpMessage.Decline, is HelpMessage.End -> ""
            is HelpMessage.Chat -> "\"text\":${quote(message.text)}"
        }
        val type = when (message) {
            is HelpMessage.Request -> "TASK_REQUEST"
            is HelpMessage.Accept -> "TASK_ACCEPT"
            is HelpMessage.Decline -> "TASK_DECLINE"
            is HelpMessage.Chat -> "CHAT_MESSAGE"
            is HelpMessage.End -> "TASK_END"
        }
        val bytes = ("{\"version\":1,\"messageId\":${quote(message.messageId)}," +
            "\"taskId\":${quote(message.taskId)},\"createdAt\":${message.createdAt}," +
            "\"expiresAt\":${message.expiresAt},\"type\":${quote(type)},\"payload\":{$payload}}")
            .toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_MESSAGE_BYTES)
        return bytes
    }

    fun decode(bytes: ByteArray, now: Long): HelpMessage {
        if (bytes.size > MAX_MESSAGE_BYTES) throw HelpMessageRejected("INVALID_MESSAGE")
        val text = try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) { throw HelpMessageRejected("INVALID_MESSAGE") }
        val root = try { JsonReader(text).parse() } catch (_: Exception) { throw HelpMessageRejected("INVALID_MESSAGE") }
        if (root.keys != setOf("version", "messageId", "taskId", "createdAt", "expiresAt", "type", "payload"))
            throw HelpMessageRejected("INVALID_MESSAGE")
        if (root["version"] != 1L) throw HelpMessageRejected("UNSUPPORTED_VERSION")
        val id = root["messageId"] as? String ?: throw HelpMessageRejected("INVALID_MESSAGE")
        val task = root["taskId"] as? String ?: throw HelpMessageRejected("INVALID_MESSAGE")
        val created = root["createdAt"] as? Long ?: throw HelpMessageRejected("INVALID_MESSAGE")
        val expires = root["expiresAt"] as? Long ?: throw HelpMessageRejected("INVALID_MESSAGE")
        if (!uuid.matches(id) || !uuid.matches(task) || created <= 0 ||
            created > Long.MAX_VALUE - TASK_LIFETIME_MS || expires != created + TASK_LIFETIME_MS ||
            created - now > 30_000L) throw HelpMessageRejected("INVALID_MESSAGE")
        if (now >= expires) throw HelpMessageRejected("EXPIRED")
        val payload = root["payload"] as? Map<*, *> ?: throw HelpMessageRejected("INVALID_MESSAGE")
        fun string(key: String) = payload[key] as? String ?: throw HelpMessageRejected("INVALID_MESSAGE")
        return when (root["type"] as? String) {
            "TASK_REQUEST" -> {
                if (payload.keys != setOf("category", "details")) throw HelpMessageRejected("INVALID_MESSAGE")
                val category = try { HelpCategory.valueOf(string("category")) }
                catch (_: Exception) { throw HelpMessageRejected("INVALID_MESSAGE") }
                val details = string("details")
                if (!validText(details, MAX_REQUEST_BYTES)) throw HelpMessageRejected("INVALID_MESSAGE")
                HelpMessage.Request(id, task, created, expires, category, details)
            }
            "TASK_ACCEPT" -> { if (payload.isNotEmpty()) throw HelpMessageRejected("INVALID_MESSAGE"); HelpMessage.Accept(id, task, created, expires) }
            "TASK_DECLINE" -> { if (payload.isNotEmpty()) throw HelpMessageRejected("INVALID_MESSAGE"); HelpMessage.Decline(id, task, created, expires) }
            "CHAT_MESSAGE" -> {
                if (payload.keys != setOf("text")) throw HelpMessageRejected("INVALID_MESSAGE")
                val body = string("text")
                if (!validText(body, MAX_CHAT_BYTES)) throw HelpMessageRejected("INVALID_MESSAGE")
                HelpMessage.Chat(id, task, created, expires, body)
            }
            "TASK_END" -> { if (payload.isNotEmpty()) throw HelpMessageRejected("INVALID_MESSAGE"); HelpMessage.End(id, task, created, expires) }
            else -> throw HelpMessageRejected("INVALID_MESSAGE")
        }
    }

    private fun quote(value: String): String = "\"" + buildString {
        value.forEach { c -> when (c) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\n' -> append("\\n")
            '\t' -> append("\\t")
            '\r' -> append("\\r")
            else -> if (c.code < 32) append("\\u%04x".format(c.code)) else append(c)
        } }
    } + "\""

    private class JsonReader(private val source: String) {
        private var i = 0
        fun parse(): Map<String, Any> { val out = obj(); ws(); require(i == source.length); return out }
        private fun ws() { while (i < source.length && source[i] in " \r\n\t") i++ }
        private fun take(c: Char) { ws(); require(i < source.length && source[i++] == c) }
        private fun obj(): Map<String, Any> {
            take('{'); ws(); val out = linkedMapOf<String, Any>()
            if (i < source.length && source[i] == '}') { i++; return out }
            while (true) {
                val key = str(); require(!out.containsKey(key)); take(':'); ws(); require(i < source.length)
                val v: Any = when (source[i]) { '{' -> obj(); '"' -> str(); else -> number() }
                out[key] = v; ws(); require(i < source.length)
                if (source[i] == '}') { i++; return out }; take(',')
            }
        }
        private fun number(): Long {
            ws(); val start = i
            if (i < source.length && source[i] == '-') i++
            require(i < source.length && source[i] in '0'..'9')
            if (source[i] == '0') i++ else while (i < source.length && source[i] in '0'..'9') i++
            return source.substring(start, i).toLong()
        }
        private fun str(): String {
            take('"'); val out = StringBuilder()
            while (i < source.length) {
                val c = source[i++]
                if (c == '"') return out.toString()
                require(c.code >= 32)
                if (c != '\\') out.append(c) else {
                    require(i < source.length)
                    when (val e = source[i++]) {
                        '"', '\\', '/' -> out.append(e)
                        'b' -> out.append('\b'); 'f' -> out.append('\u000c'); 'n' -> out.append('\n')
                        'r' -> out.append('\r'); 't' -> out.append('\t')
                        'u' -> { require(i + 4 <= source.length); val h = source.substring(i, i + 4)
                            require(h.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' })
                            out.append(h.toInt(16).toChar()); i += 4 }
                        else -> error("escape")
                    }
                }
            }
            error("string")
        }
    }
}
