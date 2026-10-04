package dev.offlinerelay.offline_relay

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import dev.offlinerelay.offline_relay.ble.BleRelayForegroundService
import dev.offlinerelay.offline_relay.ble.BleRelaySession
import dev.offlinerelay.offline_relay.ble.BoundedEventBuffer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHODS = "dev.offlinerelay/ble/methods"
        private const val EVENTS = "dev.offlinerelay/ble/events"
        private const val BLE_PERMISSION_REQUEST = 41
        private const val NOTIFICATION_PERMISSION_REQUEST = 42
    }

    private val blePermissions = arrayOf(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.BLUETOOTH_ADVERTISE,
    )
    private var eventSink: EventChannel.EventSink? = null
    private val unattachedEvents = BoundedEventBuffer()
    private var session: BleRelaySession? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionAction: (() -> Unit)? = null
    private var helperBinder: BleRelayForegroundService.LocalBinder? = null
    private var helperBound = false
    private var pendingHelperAction: (() -> Unit)? = null
    private val helperEventListener: (Map<String, Any?>) -> Unit = ::emit

    private val helperConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            helperBinder = service as? BleRelayForegroundService.LocalBinder
            if (eventSink != null) helperBinder?.service()?.attach(helperEventListener)
            pendingHelperAction?.also {
                pendingHelperAction = null
                it()
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            helperBinder = null
            emit(mapOf("event" to "helperSnapshot", "connectionId" to null))
            emit(mapOf("event" to "helperState", "enabled" to false))
        }
    }

    private fun emit(event: Map<String, Any?>) {
        runOnUiThread {
            val sink = eventSink
            if (sink != null) sink.success(event) else unattachedEvents.add(event)
            if (event["event"] == "disconnected" || event["event"] == "sessionEnded") {
                session = null
            }
        }
    }

    private fun currentSession(): BleRelaySession {
        if (session == null) session = BleRelaySession(applicationContext, ::emit)
        return requireNotNull(session)
    }

    private fun withBlePermissions(result: MethodChannel.Result, action: () -> Unit) {
        if (blePermissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
            try {
                action()
            } catch (error: Exception) {
                result.error("ble_error", error.message ?: error.javaClass.simpleName, null)
            }
            return
        }
        pendingPermissionResult = result
        pendingPermissionAction = action
        requestPermissions(blePermissions, BLE_PERMISSION_REQUEST)
    }

    private fun withHelpPermissions(result: MethodChannel.Result, action: () -> Unit) {
        withBlePermissions(result) {
            if (Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                pendingPermissionResult = result
                pendingPermissionAction = action
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
            } else {
                action()
            }
        }
    }

    private fun startHelperService(profile: Map<String, Any?>, result: MethodChannel.Result) {
        val action = {
            val binder = helperBinder
            if (binder == null) {
                result.error("service_unavailable", "Helper service did not bind", null)
            } else {
                binder.service().advertise(profile, result)
            }
        }
        if (helperBinder != null) {
            action()
            return
        }
        pendingHelperAction = action
        try {
            val intent = Intent(this, BleRelayForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
            else startService(intent)
            bindHelperService()
        } catch (error: Exception) {
            pendingHelperAction = null
            result.error("service_start_failed", error.message ?: error.javaClass.simpleName, null)
        }
    }

    private fun bindHelperService() {
        if (helperBound) return
        helperBound = bindService(
            Intent(this, BleRelayForegroundService::class.java),
            helperConnection,
            Context.BIND_AUTO_CREATE,
        )
    }

    private fun unbindHelperService() {
        if (!helperBound) return
        helperBinder?.service()?.detach(helperEventListener)
        unbindService(helperConnection)
        helperBound = false
        helperBinder = null
    }

    override fun onStart() {
        super.onStart()
        if (BleRelayForegroundService.isRunning) bindHelperService()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                    unattachedEvents.drain().forEach(events::success)
                    helperBinder?.service()?.attach(helperEventListener)
                }

                override fun onCancel(arguments: Any?) {
                    helperBinder?.service()?.detach(helperEventListener)
                    eventSink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHODS)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "advertise" -> withHelpPermissions(result) {
                            val profile = call.argument<Map<String, Any?>>("profile")
                                ?: throw IllegalArgumentException("Missing profile")
                            startHelperService(profile, result)
                        }
                        "startDiscovery" -> withBlePermissions(result) {
                            currentSession().startDiscovery(result)
                        }
                        "stopDiscovery" -> session?.stopDiscovery(result) ?: result.success(null)
                        "connect" -> withBlePermissions(result) {
                            val peerId = call.argument<String>("peerId")
                                ?: throw IllegalArgumentException("Missing peerId")
                            currentSession().connect(peerId, result)
                        }
                        "send" -> withBlePermissions(result) {
                            val id = call.argument<String>("connectionId")
                                ?: throw IllegalArgumentException("Missing connectionId")
                            val message = call.argument<ByteArray>("message")
                                ?: throw IllegalArgumentException("Missing message bytes")
                            val helper = helperBinder?.service()
                            if (helper?.ownsConnection(id) == true) helper.send(id, message, result)
                            else session?.send(id, message, result)
                                ?: result.error("connection_missing", "BLE connection is unavailable", null)
                        }
                        "close" -> {
                            val id = call.argument<String>("connectionId")
                                ?: throw IllegalArgumentException("Missing connectionId")
                            val helper = helperBinder?.service()
                            if (helper?.ownsConnection(id) == true) helper.close(id, result)
                            else session?.close(id, result) ?: result.success(null)
                        }
                        "stopAdvertising" -> {
                            val helper = helperBinder?.service()
                            if (helper != null) helper.stopAdvertising(result)
                            else session?.stopAdvertising(result) ?: result.success(null)
                        }
                        "stopHelper" -> {
                            val helper = helperBinder?.service()
                            if (helper != null) {
                                helper.stopAvailability()
                                unbindHelperService()
                            } else {
                                stopService(Intent(this, BleRelayForegroundService::class.java))
                            }
                            result.success(null)
                        }
                        "dispose" -> {
                            session?.dispose()
                            session = null
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("ble_error", error.message ?: error.javaClass.simpleName, null)
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != BLE_PERMISSION_REQUEST && requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val result = pendingPermissionResult
        val action = pendingPermissionAction
        pendingPermissionResult = null
        pendingPermissionAction = null
        if (result == null || action == null) return
        val granted = when (requestCode) {
            BLE_PERMISSION_REQUEST -> blePermissions.all {
                checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
            }
            else -> Build.VERSION.SDK_INT < 33 ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        }
        if (granted) {
            try {
                action()
            } catch (error: Exception) {
                result.error("ble_error", error.message ?: error.javaClass.simpleName, null)
            }
        } else {
            val message = if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
                "Notification permission is required to receive nearby help requests"
            } else {
                "Nearby Devices permission is required"
            }
            result.error("permission_denied", message, null)
        }
    }

    override fun onStop() {
        unbindHelperService()
        session?.dispose()
        session = null
        super.onStop()
    }

    override fun onDestroy() {
        unbindHelperService()
        session?.dispose()
        session = null
        super.onDestroy()
    }
}
