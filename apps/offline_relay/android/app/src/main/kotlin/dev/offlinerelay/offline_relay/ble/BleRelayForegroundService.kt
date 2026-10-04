@file:Suppress("MissingPermission")

package dev.offlinerelay.offline_relay.ble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import dev.offlinerelay.offline_relay.MainActivity
import dev.offlinerelay.offline_relay.R
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.ArrayDeque

/** Owns helper advertising and its one peripheral GATT connection independently of Activity. */
class BleRelayForegroundService : Service() {
    companion object {
        @Volatile
        var isRunning: Boolean = false
            private set

        private const val TAG = "OfflineRelayHelper"
        private const val ONGOING_CHANNEL = "helper_availability"
        private const val REQUEST_CHANNEL = "help_requests"
        private const val ONGOING_NOTIFICATION_ID = 7310
        private const val REQUEST_NOTIFICATION_ID = 7311
    }

    inner class LocalBinder : Binder() {
        fun service(): BleRelayForegroundService = this@BleRelayForegroundService
    }

    private val binder = LocalBinder()
    private val queuedEvents = ArrayDeque<Map<String, Any?>>()
    private val notifiedRequestIds = mutableSetOf<String>()
    private var eventListener: ((Map<String, Any?>) -> Unit)? = null
    private var session: BleRelaySession? = null
    private var profile: Map<String, Any?>? = null
    private var activeConnectionId: String? = null
    private var activePeer: Map<String, Any?>? = null
    private var pendingRequest: ByteArray? = null
    private var pendingRequestId: String? = null
    private var pendingRequestName: String? = null
    private var acceptedRequestId: String? = null
    private var acceptedPeerName: String? = null
    private var availabilityEnabled = false
    private var stopping = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isRunning = true
        startForeground(ONGOING_NOTIFICATION_ID, ongoingNotification())
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder = binder

    fun attach(listener: (Map<String, Any?>) -> Unit) {
        eventListener = listener
        listener(helperStateEvent())
        val connectionId = activeConnectionId
        val peer = activePeer
        val request = pendingRequest
        if (connectionId != null && peer != null) {
            listener(mapOf("event" to "incomingConnection", "connectionId" to connectionId, "peer" to peer))
            if (request != null) {
                listener(mapOf("event" to "message", "connectionId" to connectionId, "message" to request))
            }
            if (acceptedRequestId != null) {
                listener(mapOf(
                    "event" to "helperAccepted",
                    "connectionId" to connectionId,
                    "requestId" to acceptedRequestId,
                    "peerName" to acceptedPeerName,
                ))
            }
        }
        queuedEvents.forEach(listener)
        queuedEvents.clear()
    }

    fun detach(listener: (Map<String, Any?>) -> Unit) {
        if (eventListener === listener) eventListener = null
    }

    fun advertise(profile: Map<String, Any?>, result: MethodChannel.Result) {
        availabilityEnabled = true
        stopping = false
        this.profile = profile.toMap()
        clearRequestNotification()
        notifyState()
        startSession(profile, result)
    }

    fun stopAdvertising(result: MethodChannel.Result) {
        session?.stopAdvertising(result) ?: result.success(null)
        updateOngoingNotification(
            if (activeConnectionId == null) "Available to nearby users"
            else "Connected with ${activePeerName()}",
        )
    }

    fun ownsConnection(id: String): Boolean = activeConnectionId == id

    fun send(id: String, message: ByteArray, result: MethodChannel.Result) {
        val activeSession = session
        if (activeSession == null || !ownsConnection(id)) {
            result.error("connection_missing", "Helper BLE connection is unavailable", null)
            return
        }
        activeSession.send(id, message, object : MethodChannel.Result {
            override fun success(resultValue: Any?) {
                handleOutgoingEnvelope(message)
                result.success(resultValue)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                result.error(errorCode, errorMessage, errorDetails)
            }

            override fun notImplemented() = result.notImplemented()
        })
    }

    fun close(id: String, result: MethodChannel.Result) {
        if (ownsConnection(id)) session?.close(id, result) ?: result.success(null)
        else result.success(null)
    }

    fun stopAvailability() {
        if (stopping) return
        stopping = true
        availabilityEnabled = false
        activeConnectionId = null
        activePeer = null
        pendingRequest = null
        pendingRequestId = null
        pendingRequestName = null
        acceptedRequestId = null
        acceptedPeerName = null
        clearRequestNotification()
        session?.dispose()
        session = null
        emit(helperStateEvent())
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopping = true
        availabilityEnabled = false
        session?.dispose()
        session = null
        clearRequestNotification()
        isRunning = false
        super.onDestroy()
    }

    private fun startSession(
        advertisedProfile: Map<String, Any?>,
        result: MethodChannel.Result? = null,
    ) {
        session?.dispose()
        session = BleRelaySession(applicationContext, ::onSessionEvent)
        session?.advertise(advertisedProfile, result ?: NoopResult)
        updateOngoingNotification("Available to nearby users")
    }

    private fun onSessionEvent(event: Map<String, Any?>) {
        when (event["event"]) {
            "incomingConnection" -> {
                activeConnectionId = event["connectionId"] as? String
                @Suppress("UNCHECKED_CAST")
                activePeer = event["peer"] as? Map<String, Any?>
                updateOngoingNotification("A nearby user is connecting")
            }
            "message" -> inspectIncomingEnvelope(event)
            "disconnected" -> {
                clearRequestNotification()
                pendingRequest = null
                pendingRequestId = null
                pendingRequestName = null
                acceptedRequestId = null
                acceptedPeerName = null
            }
            "sessionEnded" -> {
                val shouldResume = availabilityEnabled && !stopping &&
                    activeConnectionId != null && profile != null
                activeConnectionId = null
                activePeer = null
                pendingRequest = null
                pendingRequestId = null
                pendingRequestName = null
                acceptedRequestId = null
                acceptedPeerName = null
                clearRequestNotification()
                session = null
                if (shouldResume) {
                    android.os.Handler(mainLooper).postDelayed({
                        val savedProfile = profile
                        if (availabilityEnabled && !stopping && session == null && savedProfile != null) {
                            startSession(savedProfile)
                        }
                    }, 500)
                }
            }
        }
        emit(event)
    }

    private fun inspectIncomingEnvelope(event: Map<String, Any?>) {
        val bytes = event["message"] as? ByteArray ?: return
        val connectionId = event["connectionId"] as? String ?: return
        try {
            val envelope = JSONObject(String(bytes, StandardCharsets.UTF_8))
            if (envelope.optInt("version") != 1 || envelope.optString("type") != "connection_request") return
            val requestId = envelope.optString("id").takeIf { it.isNotBlank() } ?: return
            val body = envelope.optJSONObject("body") ?: JSONObject()
            val name = body.optString("name", "Someone nearby").ifBlank { "Someone nearby" }
            activeConnectionId = connectionId
            pendingRequest = bytes.clone()
            pendingRequestId = requestId
            pendingRequestName = name
            acceptedRequestId = null
            acceptedPeerName = null
            if (notifiedRequestIds.add(requestId)) showRequestNotification(requestId, name)
        } catch (error: Exception) {
            Log.w(TAG, "Ignoring malformed app envelope", error)
        }
    }

    private fun handleOutgoingEnvelope(bytes: ByteArray) {
        try {
            val envelope = JSONObject(String(bytes, StandardCharsets.UTF_8))
            val type = envelope.optString("type")
            if (type != "connection_accept" && type != "connection_reject") return
            val requestId = envelope.optJSONObject("body")?.optString("requestId")
            val peerName = activePeerName()
            if (type == "connection_accept") {
                acceptedRequestId = requestId
                acceptedPeerName = peerName
            } else {
                acceptedRequestId = null
                acceptedPeerName = null
            }
            if (requestId == pendingRequestId || requestId.isNullOrBlank()) {
                pendingRequest = null
                pendingRequestId = null
                pendingRequestName = null
                clearRequestNotification()
            }
            if (type == "connection_accept") {
                updateOngoingNotification("Connected with $peerName")
                emit(mapOf(
                    "event" to "helperAccepted",
                    "connectionId" to activeConnectionId,
                    "requestId" to requestId,
                    "peerName" to peerName,
                ))
            }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to inspect outgoing app envelope", error)
        }
    }

    private fun activePeerName(): String = acceptedPeerName
        ?: pendingRequestName
        ?: (activePeer?.get("label") as? String)
        ?: (profile?.get("label") as? String)
        ?: "nearby user"

    private fun emit(event: Map<String, Any?>) {
        val listener = eventListener
        if (listener != null) listener(event) else queuedEvents.addLast(event)
    }

    private fun helperStateEvent(): Map<String, Any?> = mapOf(
        "event" to "helperState",
        "enabled" to availabilityEnabled,
        "displayName" to (profile?.get("label") as? String),
    )

    private fun notifyState() = emit(helperStateEvent())

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(ONGOING_CHANNEL, "Helper availability", NotificationManager.IMPORTANCE_LOW)
                .apply { description = "Shows when OfflineRelay is available to nearby users." },
        )
        manager.createNotificationChannel(
            NotificationChannel(REQUEST_CHANNEL, "Nearby help requests", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Alerts you when someone nearby asks for help." },
        )
    }

    private fun ongoingNotification(text: String = "Available to nearby users"): Notification =
        Notification.Builder(this, ONGOING_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("OfflineRelay · Help Others")
            .setContentText(text)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setContentIntent(mainPendingIntent())
            .build()

    private fun updateOngoingNotification(text: String) {
        if (!availabilityEnabled) return
        getSystemService(NotificationManager::class.java)
            .notify(ONGOING_NOTIFICATION_ID, ongoingNotification(text))
    }

    private fun showRequestNotification(requestId: String, name: String) {
        val notification = Notification.Builder(this, REQUEST_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Someone nearby needs help")
            .setContentText("$name sent you a connection request")
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(mainPendingIntent())
            .build()
        getSystemService(NotificationManager::class.java).notify(REQUEST_NOTIFICATION_ID, notification)
    }

    private fun clearRequestNotification() {
        getSystemService(NotificationManager::class.java).cancel(REQUEST_NOTIFICATION_ID)
    }

    private fun mainPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private object NoopResult : MethodChannel.Result {
        override fun success(result: Any?) = Unit
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
        override fun notImplemented() = Unit
    }
}
