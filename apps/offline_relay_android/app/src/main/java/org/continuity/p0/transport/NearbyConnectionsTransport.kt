package org.continuity.p0.transport

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import com.google.android.gms.tasks.Task

class NearbyConnectionsTransport(context: Context) : NearbyTransport {
    private val client = Nearby.getConnectionsClient(context.applicationContext)
    private val main = Handler(Looper.getMainLooper())
    override var listener: (TransportEvent) -> Unit = {}
    private var active = true
    private var endpoint: String? = null
    private var confirmed = false
    private var connected = false
    private var requested = false

    private fun emit(event: TransportEvent) { main.post { if (active) listener(event) } }
    private fun call(code: String, done: Completion, action: () -> Task<Void>) {
        if (!active) return
        try {
            action().addOnSuccessListener { if (active) done(null) }
                .addOnFailureListener { error ->
                    android.util.Log.e("ContinuityNearby", "$code: ${error.javaClass.simpleName}: ${error.message}", error)
                    if (active) done("$code: ${error.javaClass.simpleName}: ${error.message}")
                }
        } catch (error: SecurityException) {
            android.util.Log.e("ContinuityNearby", "PERMISSION_DENIED: ${error.message}", error)
            done("PERMISSION_DENIED: ${error.message}")
        } catch (error: Exception) {
            android.util.Log.e("ContinuityNearby", "$code: ${error.javaClass.simpleName}: ${error.message}", error)
            done("$code: ${error.javaClass.simpleName}: ${error.message}")
        }
    }
    private val payloads = object : PayloadCallback() {
        override fun onPayloadReceived(id: String, payload: Payload) {
            if (!active || id != endpoint || !confirmed || !connected) return
            val bytes = payload.asBytes()
            if (payload.type != Payload.Type.BYTES || bytes == null || bytes.size > 8192) {
                emit(TransportEvent.Error("INVALID_MESSAGE")); disconnect(id); return
            }
            emit(TransportEvent.BytesReceived(id, bytes))
        }
        override fun onPayloadTransferUpdate(id: String, update: PayloadTransferUpdate) {
            if (active && id == endpoint && update.status == PayloadTransferUpdate.Status.FAILURE)
                emit(TransportEvent.Error("SEND_FAILED"))
        }
    }
    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(id: String, info: ConnectionInfo) {
            if (!active) return
            if ((endpoint != null && endpoint != id) ||
                (requested && info.isIncomingConnection) || confirmed || connected) {
                runCatching { client.rejectConnection(id) }; return
            }
            endpoint = id
            stopDiscovery(); stopAdvertising()
            val digits = info.authenticationDigits
            if (digits.isBlank()) {
                emit(TransportEvent.Error("CONNECTION_FAILED")); disconnect(id); return
            }
            emit(TransportEvent.VerificationRequired(id, info.endpointName, digits))
        }
        override fun onConnectionResult(id: String, result: ConnectionResolution) {
            if (!active || endpoint != id) return
            if (result.status.isSuccess && confirmed) {
                connected = true; emit(TransportEvent.Connected(id))
            } else {
                emit(TransportEvent.Error(if (result.status.statusCode == ConnectionsStatusCodes.STATUS_CONNECTION_REJECTED)
                    "CONNECTION_REJECTED" else "CONNECTION_FAILED"))
            }
        }
        override fun onDisconnected(id: String) {
            if (active && endpoint == id) { connected = false; emit(TransportEvent.Disconnected(id)) }
        }
    }
    override fun startAdvertising(displayName: String, done: Completion) =
        call("TRANSPORT_UNAVAILABLE", done) {
            client.startAdvertising(displayName, SERVICE_ID, lifecycle,
                AdvertisingOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build())
        }
    override fun stopAdvertising() { runCatching { client.stopAdvertising() } }
    override fun startDiscovery(done: Completion) = call("TRANSPORT_UNAVAILABLE", done) {
        client.startDiscovery(SERVICE_ID, object : EndpointDiscoveryCallback() {
            override fun onEndpointFound(id: String, info: DiscoveredEndpointInfo) {
                if (info.serviceId == SERVICE_ID) emit(TransportEvent.PeerFound(id, info.endpointName))
            }
            override fun onEndpointLost(id: String) { emit(TransportEvent.PeerLost(id)) }
        }, DiscoveryOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build())
    }
    override fun stopDiscovery() { runCatching { client.stopDiscovery() } }
    override fun connect(endpointId: String, done: Completion) {
        if (endpoint != null) { done("CONNECTION_FAILED"); return }
        endpoint = endpointId; requested = true; stopDiscovery()
        call("CONNECTION_FAILED", done) { client.requestConnection("Requester", endpointId, lifecycle) }
    }
    override fun confirmConnection(endpointId: String, approved: Boolean, done: Completion) {
        if (endpoint != endpointId || confirmed) { done("CONNECTION_FAILED"); return }
        if (!approved) {
            call("CONNECTION_REJECTED", done) { client.rejectConnection(endpointId) }; return
        }
        confirmed = true
        call("CONNECTION_FAILED", done) { client.acceptConnection(endpointId, payloads) }
    }
    override fun send(endpointId: String, bytes: ByteArray, done: Completion) {
        if (!connected || endpointId != endpoint || bytes.size > 8192) { done("SEND_FAILED"); return }
        call("SEND_FAILED", done) { client.sendPayload(endpointId, Payload.fromBytes(bytes)) }
    }
    override fun disconnect(endpointId: String) { runCatching { client.disconnectFromEndpoint(endpointId) } }
    override fun close() {
        active = false; listener = {}
        main.removeCallbacksAndMessages(null)
        runCatching { client.stopDiscovery() }; runCatching { client.stopAdvertising() }
        runCatching { client.stopAllEndpoints() }
    }
    companion object { const val SERVICE_ID = "org.continuity.p0" }
}
