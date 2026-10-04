package dev.offlinerelay.offline_relay

import android.Manifest
import android.content.pm.PackageManager
import dev.offlinerelay.offline_relay.ble.BleRelaySession
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHODS = "dev.offlinerelay/ble/methods"
        private const val EVENTS = "dev.offlinerelay/ble/events"
        private const val BLE_PERMISSION_REQUEST = 41
    }

    private val blePermissions = arrayOf(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.BLUETOOTH_ADVERTISE,
    )
    private var eventSink: EventChannel.EventSink? = null
    private var session: BleRelaySession? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionAction: (() -> Unit)? = null

    private fun emit(event: Map<String, Any?>) {
        runOnUiThread {
            eventSink?.success(event)
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHODS)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "advertise" -> withBlePermissions(result) {
                            val profile = call.argument<Map<String, Any?>>("profile")
                                ?: throw IllegalArgumentException("Missing profile")
                            currentSession().advertise(profile, result)
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
                            currentSession().send(id, message, result)
                        }
                        "close" -> {
                            val id = call.argument<String>("connectionId")
                                ?: throw IllegalArgumentException("Missing connectionId")
                            session?.close(id, result) ?: result.success(null)
                        }
                        "stopAdvertising" -> session?.stopAdvertising(result) ?: result.success(null)
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
        if (requestCode != BLE_PERMISSION_REQUEST) return
        val result = pendingPermissionResult
        val action = pendingPermissionAction
        pendingPermissionResult = null
        pendingPermissionAction = null
        if (result == null || action == null) return
        if (blePermissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
            try {
                action()
            } catch (error: Exception) {
                result.error("ble_error", error.message ?: error.javaClass.simpleName, null)
            }
        } else {
            result.error("permission_denied", "Nearby Devices permission is required", null)
        }
    }

    override fun onStop() {
        session?.dispose()
        session = null
        super.onStop()
    }

    override fun onDestroy() {
        session?.dispose()
        session = null
        super.onDestroy()
    }
}
