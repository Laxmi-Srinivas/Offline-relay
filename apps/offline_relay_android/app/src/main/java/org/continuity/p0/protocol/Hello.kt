package org.continuity.p0.protocol

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.UUID

enum class Role { REQUESTER, HELPER }
data class Hello(val messageId: String, val createdAt: Long, val expiresAt: Long,
                 val peerId: String, val displayName: String, val role: Role)

class HelloRejected(val code: String) : IllegalArgumentException(code)

object HelloCodec {
    private val uuid = Regex("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
    fun validName(value: String) = value.isNotBlank() && value.toByteArray().size <= 40 &&
        value.none { it.code < 32 && it != '\n' && it != '\t' }
    fun create(name: String, role: Role, now: Long) =
        Hello(UUID.randomUUID().toString(), now, now + 30_000, UUID.randomUUID().toString(), name, role)

    fun encode(h: Hello): ByteArray {
        fun quote(s: String): String = "\"" + buildString {
            s.forEach { c -> when (c) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\t' -> append("\\t")
                else -> append(c)
            } }
        } + "\""
        return ("{\"version\":1,\"messageId\":" + quote(h.messageId) +
            ",\"createdAt\":" + h.createdAt + ",\"expiresAt\":" + h.expiresAt +
            ",\"type\":\"HELLO\",\"payload\":{\"peerId\":" + quote(h.peerId) +
            ",\"displayName\":" + quote(h.displayName) + ",\"role\":" + quote(h.role.name) + "}}").toByteArray()
    }

    fun decode(bytes: ByteArray, now: Long): Hello {
        require(bytes.size <= 8192)
        val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        val root = Parser(text).parse()
        require(root.keys == setOf("version", "messageId", "createdAt", "expiresAt", "type", "payload"))
        require(root["version"] is Long && root["type"] == "HELLO")
        if (root["version"] != 1L) throw HelloRejected("UNSUPPORTED_VERSION")
        val payload = root["payload"] as? Map<*, *> ?: error("payload")
        require(payload.keys == setOf("peerId", "displayName", "role"))
        val created = root["createdAt"] as? Long ?: error("createdAt")
        val expires = root["expiresAt"] as? Long ?: error("expiresAt")
        require(created > 0 && created <= Long.MAX_VALUE - 30_000)
        require(expires == created + 30_000 && created - now <= 30_000)
        if (now >= expires) throw HelloRejected("EXPIRED")
        val messageId = root["messageId"] as? String ?: error("messageId")
        val peerId = payload["peerId"] as? String ?: error("peerId")
        val name = payload["displayName"] as? String ?: error("displayName")
        require(uuid.matches(messageId) && uuid.matches(peerId) && validName(name))
        return Hello(messageId, created, expires, peerId, name,
            Role.valueOf(payload["role"] as? String ?: error("role")))
    }

    // Small strict reader for the current object/string/integer HELLO schema.
    // No permissive JSON coercions, duplicate keys, arrays, or trailing content.
    private class Parser(private val text: String) {
        private var i = 0
        fun parse(): Map<String, Any> {
            val value = obj(1); space(); require(i == text.length); return value
        }
        private fun space() { while (i < text.length && text[i] in " \r\n\t") i++ }
        private fun take(c: Char) { space(); require(i < text.length && text[i++] == c) }
        private fun obj(depth: Int): Map<String, Any> {
            require(depth <= 4); take('{'); space()
            val out = linkedMapOf<String, Any>()
            if (i < text.length && text[i] == '}') { i++; return out }
            while (true) {
                val key = string(); require(!out.containsKey(key)); take(':'); space()
                require(i < text.length)
                val value: Any = when (text[i]) {
                    '{' -> obj(depth + 1)
                    '"' -> string()
                    else -> number()
                }
                out[key] = value; space(); require(i < text.length)
                if (text[i] == '}') { i++; return out }
                take(',')
            }
        }
        private fun number(): Long {
            space(); val start = i
            if (i < text.length && text[i] == '-') i++
            require(i < text.length && text[i] in '0'..'9')
            if (text[i] == '0') i++ else while (i < text.length && text[i] in '0'..'9') i++
            return text.substring(start, i).toLong()
        }
        private fun string(): String {
            take('"'); val out = StringBuilder()
            while (i < text.length) {
                val c = text[i++]
                if (c == '"') {
                    val result = out.toString()
                    // Reject unpaired surrogate escapes as well as malformed wire UTF-8.
                    val encoder = Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                    encoder.encode(java.nio.CharBuffer.wrap(result))
                    return result
                }
                require(c.code >= 32)
                if (c != '\\') out.append(c) else {
                    require(i < text.length)
                    when (val e = text[i++]) {
                        '"', '\\', '/' -> out.append(e)
                        'b' -> out.append('\b')
                        'f' -> out.append('\u000c')
                        'n' -> out.append('\n')
                        'r' -> out.append('\r')
                        't' -> out.append('\t')
                        'u' -> {
                            require(i + 4 <= text.length)
                            val hex = text.substring(i, i + 4)
                            require(hex.all { it in "0123456789abcdefABCDEF" })
                            out.append(hex.toInt(16).toChar()); i += 4
                        }
                        else -> error("escape")
                    }
                }
            }
            error("Unclosed string")
        }
    }
}
