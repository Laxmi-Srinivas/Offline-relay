package dev.offlinerelay.experiments.ble_poc

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.pm.PackageManager
import android.util.Log

class MainActivity : FlutterActivity() {
    private var sink: EventChannel.EventSink? = null
    private var session: BleSession? = null
    private val permissions = arrayOf(Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)

    private fun log(message: String) {
        val line = "${System.currentTimeMillis()} $message"
        Log.i("OfflineRelayBLE", line)
        sink?.success(line)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "offlinerelay.poc/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
                override fun onCancel(arguments: Any?) { sink = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "offlinerelay.poc/commands")
            .setMethodCallHandler { call, result ->
                try {
                    if (call.method == "stop") {
                        session?.stop("user stop"); session = null
                    } else if (permissions.any { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }) {
                        requestPermissions(permissions, 10)
                        log("permission_requested: grant Nearby Devices, then retry role button")
                    } else when (call.method) {
                        "advertise", "discover" -> {
                            session?.stop("role restart")
                            session = BleSession(this, ::log)
                            if (call.method == "advertise") session!!.advertise() else session!!.discover()
                        }
                        "hello" -> requireNotNull(session) { "Start central first" }.send("Hello".toByteArray())
                        "larger" -> requireNotNull(session) { "Start central first" }.send(ByteArray(256) { it.toByte() })
                        else -> { result.notImplemented(); return@setMethodCallHandler }
                    }
                    result.success(null)
                } catch (error: Exception) {
                    log("error: ${error.javaClass.simpleName}: ${error.message}")
                    session?.stop("command failed"); session = null
                    result.error("ble_error", error.message, null)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 10) {
            val granted = this.permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
            log(if (granted) "permission_granted: retry role button" else "permission_denied: Nearby Devices required")
        }
    }

    override fun onStop() {
        session?.stop("activity left foreground"); session = null
        super.onStop()
    }
}
