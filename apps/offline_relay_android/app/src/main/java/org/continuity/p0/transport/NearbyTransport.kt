package org.continuity.p0.transport

sealed interface TransportEvent {
    data class PeerFound(val endpointId: String, val displayName: String) : TransportEvent
    data class PeerLost(val endpointId: String) : TransportEvent
    data class VerificationRequired(val endpointId: String, val displayName: String, val digits: String) : TransportEvent
    data class Connected(val endpointId: String) : TransportEvent
    data class Disconnected(val endpointId: String) : TransportEvent
    data class BytesReceived(val endpointId: String, val bytes: ByteArray) : TransportEvent
    data class Error(val code: String) : TransportEvent
}
typealias Completion = (String?) -> Unit

interface NearbyTransport {
    var listener: (TransportEvent) -> Unit
    fun startAdvertising(displayName: String, done: Completion)
    fun stopAdvertising()
    fun startDiscovery(done: Completion)
    fun stopDiscovery()
    fun connect(endpointId: String, done: Completion)
    fun confirmConnection(endpointId: String, approved: Boolean, done: Completion)
    fun send(endpointId: String, bytes: ByteArray, done: Completion)
    fun disconnect(endpointId: String)
    fun close()
}
