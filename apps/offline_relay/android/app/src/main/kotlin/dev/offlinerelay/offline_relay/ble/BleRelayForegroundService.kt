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
import java.nio.ByteBuffer

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
    private val conversation = HelperConversation()
    private val requestAlerts = RequestAlertGate()
    private var eventListener: ((Map<String, Any?>) -> Unit)? = null
    private var session: BleRelaySession? = null
    private var profile: Map<String, Any?>? = null
    private val activeConnectionId: String? get() = conversation.connectionId
    private var activePeer: Map<String, Any?>? = null
    private var sessionEpoch = 0L
    private val handler by lazy { android.os.Handler(mainLooper) }
    private var requestDeadline: Runnable? = null
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
        val request = conversation.request
        listener(mapOf("event" to "helperSnapshot", "connectionId" to connectionId))
        if (connectionId != null && peer != null) {
            listener(mapOf("event" to "incomingConnection", "connectionId" to connectionId, "peer" to peer))
            if (request != null) {
                listener(mapOf("event" to "message", "connectionId" to connectionId, "message" to request))
            }
            if (conversation.accepted) {
                listener(mapOf(
                    "event" to "helperAccepted",
                    "connectionId" to connectionId,
                    "requestId" to conversation.requestId,
                    "peerName" to conversation.requestName,
                ))
            }
        }
        conversation.queuedChat.drain().forEach(listener)
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
                if (session === activeSession && ownsConnection(id)) handleOutgoingEnvelope(id, message)
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
        val oldId = activeConnectionId
        stopping = true
        ++sessionEpoch
        availabilityEnabled = false
        clearConversation()
        activePeer = null
        clearRequestNotification()
        session?.dispose()
        session = null
        if (oldId != null) emit(mapOf("event" to "disconnected", "connectionId" to oldId, "reason" to "Helper availability stopped"))
        emit(mapOf("event" to "helperSnapshot", "connectionId" to null))
        emit(helperStateEvent())
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopping = true
        availabilityEnabled = false
        ++sessionEpoch
        session?.dispose()
        session = null
        clearRequestNotification()
        clearConversation()
        isRunning = false
        super.onDestroy()
    }

    private fun startSession(
        advertisedProfile: Map<String, Any?>,
        result: MethodChannel.Result? = null,
    ) {
        val epoch = ++sessionEpoch
        session?.dispose()
        clearConversation()
        activePeer = null
        emit(mapOf("event" to "helperSnapshot", "connectionId" to null))
        session = BleRelaySession(applicationContext) { event ->
            if (epoch == sessionEpoch && !stopping) onSessionEvent(event)
        }
        session?.advertise(advertisedProfile, result ?: NoopResult)
        updateOngoingNotification("Available to nearby users")
    }

    private fun onSessionEvent(event: Map<String, Any?>) {
        when (event["event"]) {
            "incomingConnection" -> {
                val id = event["connectionId"] as? String ?: return
                conversation.begin(id)
                cancelRequestDeadline()
                requestDeadline = Runnable {
                    if (ownsConnection(id) && conversation.requestId == null) {
                        session?.close(id, NoopResult)
                    }
                }.also { handler.postDelayed(it, 15_000) }
                @Suppress("UNCHECKED_CAST")
                activePeer = event["peer"] as? Map<String, Any?>
                updateOngoingNotification("A nearby user is connecting")
            }
            "message" -> {
                if (!inspectIncomingEnvelope(event)) return
            }
            "disconnected" -> {
                if (event["connectionId"] != activeConnectionId) return
                clearRequestNotification()
                // Keep the ID until sessionEnded decides whether to resume advertising.
                conversation.queuedChat.clear()
                cancelRequestDeadline()
            }
            "sessionEnded" -> {
                val shouldResume = availabilityEnabled && !stopping &&
                    activeConnectionId != null && profile != null
                clearConversation()
                activePeer = null
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

    private fun inspectIncomingEnvelope(event: Map<String, Any?>): Boolean {
        val bytes = event["message"] as? ByteArray ?: return false
        val connectionId = event["connectionId"] as? String ?: return false
        if (!ownsConnection(connectionId)) return false
        try {
            val envelope = decodeEnvelope(bytes)
            val body = envelope.getJSONObject("body")
            return when (envelope.getString("type")) {
                "connection_request" -> {
                    val name = body.opt("name") as? String ?: return false
                    if (body.opt("role") != "offline_user") return false
                    if (!conversation.receiveRequest(connectionId, envelope.getString("id"), name, bytes)) return false
                    cancelRequestDeadline()
                    if (requestAlerts.allow(android.os.SystemClock.elapsedRealtime())) showRequestNotification(name)
                    true
                }
                "chat" -> conversation.permitsChat(connectionId) && body.opt("text") is String
                else -> false
            }
        } catch (error: Exception) {
            // JSONException messages can contain attacker-supplied chat bytes.
            Log.w(TAG, "Ignoring malformed app envelope")
            return false
        }
    }

    private fun decodeEnvelope(bytes: ByteArray): JSONObject {
        require(bytes.isNotEmpty() && bytes.size <= 256)
        val text = StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes)).toString()
        val envelope = JSONObject(text)
        require(envelope.length() == 4 && envelope.get("version") == 1)
        require(envelope.get("id") is String && envelope.getString("id").isNotBlank())
        require(envelope.get("type") is String && envelope.get("body") is JSONObject)
        return envelope
    }

    private fun handleOutgoingEnvelope(connectionId: String, bytes: ByteArray) {
        try {
            val envelope = decodeEnvelope(bytes)
            val type = envelope.optString("type")
            if (type != "connection_accept" && type != "connection_reject") return
            val requestId = envelope.getJSONObject("body").opt("requestId") as? String ?: return
            if (!conversation.resolve(connectionId, requestId, type == "connection_accept")) return
            val peerName = activePeerName()
            clearRequestNotification()
            if (type == "connection_accept") {
                updateOngoingNotification("Connected with $peerName")
                emit(mapOf(
                    "event" to "helperAccepted",
                    "connectionId" to connectionId,
                    "requestId" to requestId,
                    "peerName" to peerName,
                ))
            }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to inspect outgoing app envelope")
        }
    }

    private fun activePeerName(): String = conversation.requestName
        ?: (activePeer?.get("label") as? String)
        ?: (profile?.get("label") as? String)
        ?: "nearby user"

    private fun emit(event: Map<String, Any?>) {
        val listener = eventListener
        if (listener != null) listener(event)
        else if (event["event"] == "message") {
            val id = event["connectionId"] as? String ?: return
            val bytes = event["message"] as? ByteArray ?: return
            conversation.queueChat(id, bytes)
        }
        // Connection/request/approval/state are replayed from the current snapshot,
        // never from a historical queue of control events.
    }

    private fun cancelRequestDeadline() {
        requestDeadline?.let { handler.removeCallbacks(it) }
        requestDeadline = null
    }

    private fun clearConversation() {
        cancelRequestDeadline()
        conversation.clear()
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

    private fun showRequestNotification(name: String) {
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
