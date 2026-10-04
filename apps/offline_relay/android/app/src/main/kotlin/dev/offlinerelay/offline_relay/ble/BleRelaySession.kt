@file:Suppress("DEPRECATION", "MissingPermission")

package dev.offlinerelay.offline_relay.ble

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.io.ByteArrayOutputStream
import java.util.UUID

/** Android GATT session used only by the OfflineRelay host app. */
class BleRelaySession(
    context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        val SERVICE: UUID = UUID.fromString("41729610-0934-4e0e-b749-170442310001")
        val DATA: UUID = UUID.fromString("41729610-0934-4e0e-b749-170442310002")
        val ACK: UUID = UUID.fromString("41729610-0934-4e0e-b749-170442310003")
        private val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private const val TAG = "OfflineRelayBLE"
        private const val MAX_BYTES = 256
    }

    private enum class Role { NONE, CENTRAL, PERIPHERAL }

    private data class DiscoveredPeer(
        val device: BluetoothDevice,
        val peer: Map<String, Any?>,
    )

    private val context = context.applicationContext
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private val adapter = requireNotNull(manager.adapter) { "Bluetooth unavailable" }
    private val handler = Handler(Looper.getMainLooper())
    private val discovered = mutableMapOf<String, DiscoveredPeer>()
    private val peerIdsByAddress = mutableMapOf<String, String>()
    private val loggedScanAddresses = mutableSetOf<String>()
    private var role = Role.NONE
    private var active = true
    private var scanning = false
    private var advertising = false
    private var server: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var gatt: BluetoothGatt? = null
    private var remote: BluetoothDevice? = null
    private var data: BluetoothGattCharacteristic? = null
    private var ack: BluetoothGattCharacteristic? = null
    private var connectionId: String? = null
    private var peerInfo: Map<String, Any?> = emptyMap()
    private var notificationEnabled = false
    private var incomingAnnounced = false
    private var ready = false
    private var pendingConnect: MethodChannel.Result? = null
    private var pendingAdvertise: MethodChannel.Result? = null
    private var pendingSend: MethodChannel.Result? = null
    private var expectedAck = byteArrayOf()
    private var outbound = emptyList<ByteArray>()
    private var outboundIndex = 0
    private var outboundId = 0
    private var outboundLength = 0
    private var outboundIsPeripheral = false
    private var peripheralAckReceived = false
    private var nextMessageId = 0
    private var receiveId = -1
    private var receiveCount = 0
    private var receiveIndex = 0
    private val received = ByteArrayOutputStream()
    private var acknowledgement = byteArrayOf()
    private var timeout: Runnable? = null
    private var sendTimeout: Runnable? = null
    private var receiveTimeout: Runnable? = null
    private var ackWriteTimeout: Runnable? = null
    private var incomingAckPending = false
    private var pendingClose: MethodChannel.Result? = null

    private fun incomingAckCompleted() {
        incomingAckPending = false
        if (pendingClose != null) {
            // Allow the submitted GATT response to leave Android before closing the link.
            handler.postDelayed({ stop("local close", notify = true) }, 150)
        }
    }
    private val clientOperations = BleOperationQueue()
    private val radioReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1) == BluetoothAdapter.STATE_TURNING_OFF) {
                event { fail("Bluetooth is disabled. Turn it on and try again.") }
            }
        }
    }

    init {
        if (Build.VERSION.SDK_INT >= 33) {
            this.context.registerReceiver(radioReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED), Context.RECEIVER_NOT_EXPORTED)
        } else this.context.registerReceiver(radioReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
    }

    private fun queueClientOperation(operation: () -> Unit) {
        check(clientOperations.add(operation)) { "Too many pending GATT operations" }
    }

    private fun clientOperationDone() {
        clientOperations.complete()
    }

    private fun log(name: String, fields: Map<String, Any?> = emptyMap()) {
        val line = buildString {
            append(name)
            fields.forEach { (key, value) -> append(" $key=$value") }
        }
        Log.i(TAG, line)
    }

    private fun event(block: () -> Unit) {
        handler.post {
            if (active) try {
                block()
            } catch (error: Exception) {
                fail("${error.javaClass.simpleName}: ${error.message}")
            }
        }
    }

    private fun deadline(stage: String) {
        clearDeadline()
        timeout = Runnable { fail("timeout: $stage") }.also {
            handler.postDelayed(it, 15_000)
        }
    }

    private fun clearDeadline() {
        timeout?.let(handler::removeCallbacks)
        timeout = null
    }

    fun advertise(profile: Map<String, Any?>, result: MethodChannel.Result) {
        check(role == Role.NONE) { "Stop the current BLE role first" }
        check(adapter.isEnabled) { "Enable Bluetooth first" }
        check(adapter.isMultipleAdvertisementSupported) {
            "Peripheral advertising unsupported on this device"
        }
        role = Role.PERIPHERAL
        peerInfo = mapOf(
            "id" to (profile["id"] as? String ?: UUID.randomUUID().toString()),
            "label" to (profile["label"] as? String ?: "OfflineRelay user"),
            "metadata" to (profile["metadata"] as? Map<*, *> ?: emptyMap<String, String>()),
        )
        pendingAdvertise = result
        val service = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val dataCharacteristic = BluetoothGattCharacteristic(
            DATA,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        data = dataCharacteristic
        dataCharacteristic.addDescriptor(
            BluetoothGattDescriptor(
                CCCD,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        service.addCharacteristic(dataCharacteristic)
        val ackCharacteristic = BluetoothGattCharacteristic(
            ACK,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_READ or BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        ack = ackCharacteristic
        service.addCharacteristic(ackCharacteristic)
        server = requireNotNull(manager.openGattServer(context, serverCallback)) {
            "GATT server unavailable"
        }
        deadline("service registration")
        check(server!!.addService(service)) { "addService rejected" }
    }

    fun startDiscovery(result: MethodChannel.Result) {
        check(role == Role.NONE) { "Stop the current BLE role first" }
        check(adapter.isEnabled) { "Enable Bluetooth first" }
        role = Role.CENTRAL
        discovered.clear()
        peerIdsByAddress.clear()
        loggedScanAddresses.clear()
        val scanner = requireNotNull(adapter.bluetoothLeScanner) { "BLE scanner unavailable" }
        scanner.startScan(
            listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
            scanCallback,
        )
        scanning = true
        log("discovery_started", mapOf("service" to SERVICE))
        deadline("discovery")
        result.success(null)
    }

    fun stopDiscovery(result: MethodChannel.Result) {
        if (scanning) release { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        scanning = false
        if (role == Role.CENTRAL && gatt == null) role = Role.NONE
        if (gatt == null) clearDeadline()
        result.success(null)
    }

    fun connect(peerId: String, result: MethodChannel.Result) {
        check(active && gatt == null && role != Role.PERIPHERAL) { "A BLE connection is already active" }
        check(adapter.isEnabled) { "Enable Bluetooth first" }
        val peer = requireNotNull(discovered[peerId]) { "Nearby peer expired; scan again" }
        role = Role.CENTRAL
        release { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        scanning = false
        pendingConnect = result
        peerInfo = peer.peer
        remote = peer.device
        connectionId = UUID.randomUUID().toString()
        deadline("connection")
        gatt = peer.device.connectGatt(context, false, clientCallback, BluetoothDevice.TRANSPORT_LE)
        check(gatt != null) { "connectGatt returned null" }
    }

    fun send(id: String, bytes: ByteArray, result: MethodChannel.Result) {
        check(ready && connectionId == id) { "Connection is not ready" }
        check(pendingSend == null && outbound.isEmpty()) { "A message awaits its ACK" }
        require(bytes.isNotEmpty() && bytes.size <= MAX_BYTES) { "Message must be 1..256 bytes" }
        nextMessageId = (nextMessageId % 255) + 1
        outboundId = nextMessageId
        outboundLength = bytes.size
        val chunks = bytes.toList().chunked(16)
        outbound = chunks.mapIndexed { index, chunk ->
            byteArrayOf(1, outboundId.toByte(), index.toByte(), chunks.size.toByte()) +
                chunk.toByteArray()
        }
        outboundIndex = 0
        outboundIsPeripheral = role == Role.PERIPHERAL
        peripheralAckReceived = false
        pendingSend = result
        expectedAck = byteArrayOf(
            1,
            outboundId.toByte(),
            (outboundLength shr 8).toByte(),
            outboundLength.toByte(),
        )
        sendTimeout = Runnable { fail("timeout: message write / application ACK") }.also {
            handler.postDelayed(it, 15_000)
        }
        if (outboundIsPeripheral) sendNextNotification() else writeNext()
    }

    fun close(id: String, result: MethodChannel.Result) {
        if (connectionId == id && incomingAckPending) {
            if (pendingClose != null) { result.success(null); return }
            pendingClose = result
            deadline("final acknowledgement before close")
            return
        }
        if (connectionId == id) stop("local close", notify = true)
        result.success(null)
    }

    fun stopAdvertising(result: MethodChannel.Result) {
        if (advertising) release { advertiser?.stopAdvertising(advertiseCallback) }
        advertising = false
        advertiser = null
        if (role == Role.PERIPHERAL && remote == null) {
            release { server?.close() }
            server = null
            role = Role.NONE
        }
        result.success(null)
    }

    fun dispose() {
        stop("transport disposed", notify = true)
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) = event { fail("scan_error code=$errorCode") }

        override fun onScanResult(callbackType: Int, result: ScanResult) = event {
            if (!scanning) return@event
            val hasService = result.scanRecord?.serviceUuids?.contains(ParcelUuid(SERVICE)) == true
            val hasProfile = result.scanRecord?.getServiceData(ParcelUuid(SERVICE)) != null
            if (loggedScanAddresses.add(result.device.address)) {
                log("scan_result", mapOf("name" to result.scanRecord?.deviceName,
                    "service_match" to (hasService || hasProfile), "rssi" to result.rssi))
            }
            if (!hasService && !hasProfile) return@event
            val id = peerIdsByAddress.getOrPut(result.device.address) {
                UUID.randomUUID().toString()
            }
            val profile = decodeProfile(result.scanRecord?.getServiceData(ParcelUuid(SERVICE)))
            val label = profile?.first ?: try {
                result.device.name?.takeIf { it.isNotBlank() } ?: "Nearby OfflineRelay user"
            } catch (_: SecurityException) {
                "Nearby OfflineRelay user"
            }
            val peer = mapOf("id" to id, "label" to label,
                "metadata" to (profile?.second ?: emptyMap<String, String>()))
            val firstDiscovery = id !in discovered
            discovered[id] = DiscoveredPeer(result.device, peer)
            if (firstDiscovery) emit(mapOf("event" to "peerDiscovered", "peer" to peer))
            clearDeadline()
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) = event {
            advertising = true
            clearDeadline()
            log("advertising_started", mapOf("service" to SERVICE))
            pendingAdvertise?.success(null)
            pendingAdvertise = null
        }

        override fun onStartFailure(errorCode: Int) = event {
            pendingAdvertise?.error("advertise_error", "Advertising failed: $errorCode", null)
            pendingAdvertise = null
            fail("advertise_error code=$errorCode")
        }
    }

    private val clientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(client: BluetoothGatt, status: Int, newState: Int) = event {
            if (client !== gatt) return@event
            if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                stop("disconnect status=$status state=$newState", notify = true)
            } else if (newState == BluetoothProfile.STATE_CONNECTED) {
                remote = client.device
                log("connection_established", mapOf("role" to "central"))
                deadline("service discovery")
                check(client.discoverServices()) { "discoverServices rejected" }
            }
        }

        override fun onServicesDiscovered(client: BluetoothGatt, status: Int) = event {
            check(status == BluetoothGatt.GATT_SUCCESS) { "service_discovery status=$status" }
            val service = requireNotNull(client.getService(SERVICE)) { "Expected service missing" }
            data = requireNotNull(service.getCharacteristic(DATA)) { "Data characteristic missing" }
            ack = requireNotNull(service.getCharacteristic(ACK)) { "ACK characteristic missing" }
            check(data!!.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                "Peer does not support reverse data notifications"
            }
            check(client.setCharacteristicNotification(data, true)) {
                "Notification subscription rejected"
            }
            val descriptor = requireNotNull(data!!.getDescriptor(CCCD)) { "CCCD missing" }
            if (Build.VERSION.SDK_INT >= 33) {
                val statusCode = client.writeDescriptor(
                    descriptor,
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
                )
                check(statusCode == BluetoothGatt.GATT_SUCCESS) { "CCCD write rejected: $statusCode" }
            } else {
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                check(client.writeDescriptor(descriptor)) { "CCCD write rejected" }
            }
        }

        override fun onDescriptorWrite(
            client: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) = event {
            check(status == BluetoothGatt.GATT_SUCCESS && descriptor.uuid == CCCD) {
                "Notification subscription failed: $status"
            }
            ready = true
            clearDeadline()
            val id = requireNotNull(connectionId)
            pendingConnect?.success(mapOf("connectionId" to id, "peer" to peerInfo))
            pendingConnect = null
            log("characteristic_discovered", mapOf("data" to DATA, "ack" to ACK))
        }

        override fun onCharacteristicWrite(
            client: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) = event {
            check(status == BluetoothGatt.GATT_SUCCESS) { "write_error status=$status" }
            if (characteristic.uuid == ACK) {
                ackWriteTimeout?.let(handler::removeCallbacks)
                ackWriteTimeout = null
                incomingAckCompleted()
                clientOperationDone()
                return@event
            }
            check(characteristic.uuid == DATA && outbound.isNotEmpty() && !outboundIsPeripheral) {
                "Unexpected write callback"
            }
            outboundIndex++
            if (outboundIndex < outbound.size) writeNext() else {
                log("message_sent", mapOf("id" to outboundId, "bytes" to outboundLength))
                queueClientOperation { check(client.readCharacteristic(ack)) { "ACK read rejected" } }
            }
            clientOperationDone()
        }

        override fun onCharacteristicRead(
            client: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            val value = characteristic.value?.clone() ?: byteArrayOf()
            event {
                check(status == BluetoothGatt.GATT_SUCCESS && characteristic.uuid == ACK) {
                    "ack_read_error status=$status"
                }
                completeClientSend(value)
                clientOperationDone()
            }
        }

        override fun onCharacteristicRead(client: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            val copy = value.clone()
            event {
                check(status == BluetoothGatt.GATT_SUCCESS && characteristic.uuid == ACK) { "ack_read_error status=$status" }
                completeClientSend(copy)
                clientOperationDone()
            }
        }

        override fun onCharacteristicChanged(
            client: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            val value = characteristic.value?.clone() ?: byteArrayOf()
            event { if (characteristic.uuid == DATA) receiveFrame(value, false) }
        }

        override fun onCharacteristicChanged(
            client: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) = event { if (characteristic.uuid == DATA) receiveFrame(value.clone(), false) }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) = event {
            check(status == BluetoothGatt.GATT_SUCCESS) { "service_registration status=$status" }
            log("service_registered", mapOf("uuid" to service.uuid))
            advertiser = requireNotNull(adapter.bluetoothLeAdvertiser) { "Advertiser unavailable" }
            deadline("advertising start")
            advertiser!!.startAdvertising(
                AdvertiseSettings.Builder()
                    .setConnectable(true)
                    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                    .build(),
                AdvertiseData.Builder().addServiceUuid(ParcelUuid(SERVICE)).build(),
                AdvertiseData.Builder()
                    .addServiceData(ParcelUuid(SERVICE), encodeProfile(peerInfo))
                    .build(),
                advertiseCallback,
            )
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) = event {
            if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                if (remote != null && remote != device) {
                    server?.cancelConnection(device)
                    log("peer_rejected", mapOf("reason" to "one connection only"))
                } else {
                    remote = device
                    if (remote == device && connectionId != null) return@event
                    connectionId = UUID.randomUUID().toString()
                    val label = try {
                        device.name?.takeIf { it.isNotBlank() } ?: "Nearby OfflineRelay user"
                    } catch (_: SecurityException) {
                        "Nearby OfflineRelay user"
                    }
                    peerInfo = mapOf("id" to UUID.randomUUID().toString(), "label" to label,
                        "metadata" to emptyMap<String, String>())
                    notificationEnabled = false
                    incomingAnnounced = false
                    log("connection_established", mapOf("role" to "peripheral"))
                    deadline("notification subscription")
                }
            } else if (device == remote) {
                stop("disconnect status=$status state=$newState", notify = true)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) = event {
            val valid = device == remote && descriptor.uuid == CCCD && !preparedWrite && offset == 0 &&
                value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
            if (valid) {
                notificationEnabled = value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                if (notificationEnabled && !incomingAnnounced && connectionId != null) {
                    incomingAnnounced = true
                    ready = true
                    clearDeadline()
                    deadline("first application message")
                    emit(mapOf("event" to "incomingConnection", "connectionId" to connectionId,
                        "peer" to peerInfo))
                }
            }
            if (responseNeeded) server?.sendResponse(device, requestId,
                if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE, offset, null)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            val copy = value.clone()
            event {
                val validBase = device == remote && ready && !preparedWrite && offset == 0 && responseNeeded
                var status = BluetoothGatt.GATT_SUCCESS
                try {
                    require(validBase) { "Invalid GATT write" }
                    when (characteristic.uuid) {
                        DATA -> receiveFrame(copy, true)
                        ACK -> completePeripheralSend(copy)
                        else -> throw IllegalArgumentException("Unknown characteristic")
                    }
                } catch (error: IllegalArgumentException) {
                    status = BluetoothGatt.GATT_FAILURE
                    log("receive_error", mapOf("message" to error.message))
                    resetReceive()
                    acknowledgement = byteArrayOf()
                    receiveTimeout?.let(handler::removeCallbacks)
                    receiveTimeout = null
                }
                check(!responseNeeded || server?.sendResponse(device, requestId, status, offset, null) == true) {
                    "GATT write response rejected"
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) = event {
            val valid = device == remote && characteristic.uuid == ACK && offset == 0 &&
                acknowledgement.isNotEmpty()
            check(server?.sendResponse(device, requestId,
                if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE,
                offset, if (valid) acknowledgement else null) == true) { "ACK response rejected" }
            if (valid) incomingAckCompleted()
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) = event {
            if (device != remote || outbound.isEmpty()) return@event
            check(status == BluetoothGatt.GATT_SUCCESS) { "notification_error status=$status" }
            check(outboundIsPeripheral && outbound.isNotEmpty()) { "Unexpected notification callback" }
            outboundIndex++
            if (outboundIndex < outbound.size) sendNextNotification()
            else {
                log("message_sent", mapOf("id" to outboundId, "bytes" to outboundLength))
                if (peripheralAckReceived) finishPeripheralSend()
            }
        }

        override fun onExecuteWrite(device: BluetoothDevice, requestId: Int, execute: Boolean) = event {
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
        }
    }

    private fun writeNext() {
        val frame = outbound[outboundIndex].clone()
        queueClientOperation {
            val characteristic = requireNotNull(data)
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            characteristic.value = frame
            check(gatt?.writeCharacteristic(characteristic) == true) { "GATT write rejected" }
        }
    }

    // Legacy advertising is limited to 31 bytes. The scan response carries a
    // compact profile: version, role code, and at most 10 UTF-8 name bytes.
    private fun encodeProfile(profile: Map<String, Any?>): ByteArray {
        val metadata = profile["metadata"] as? Map<*, *> ?: emptyMap<String, String>()
        val roleCode = when (metadata["role"] as? String) {
            "offline_user" -> 1
            "internet_helper" -> 2
            else -> 0
        }
        var labelText = profile["label"] as? String ?: "OfflineRelay"
        while (labelText.toByteArray(StandardCharsets.UTF_8).size > 10) {
            labelText = labelText.dropLast(1)
        }
        val label = labelText.toByteArray(StandardCharsets.UTF_8)
        return byteArrayOf(1, roleCode.toByte(), label.size.toByte()) + label
    }

    private fun decodeProfile(bytes: ByteArray?): Pair<String, Map<String, String>>? {
        if (bytes == null || bytes.size < 3 || bytes[0].toInt() != 1) return null
        val length = bytes[2].toInt() and 0xff
        if (length == 0 || bytes.size != length + 3) return null
        val label = String(bytes, 3, length, StandardCharsets.UTF_8)
        val role = when (bytes[1].toInt() and 0xff) {
            1 -> "offline_user"
            2 -> "internet_helper"
            else -> ""
        }
        return label to if (role.isEmpty()) emptyMap() else mapOf("role" to role)
    }

    private fun sendNextNotification() {
        check(notificationEnabled) { "Peer has not enabled notifications" }
        val characteristic = requireNotNull(data)
        characteristic.value = outbound[outboundIndex]
        check(server?.notifyCharacteristicChanged(remote, characteristic, false) == true) {
            "GATT notification rejected"
        }
    }

    private fun completeClientSend(value: ByteArray) {
        check(outbound.isNotEmpty() && !outboundIsPeripheral && value.contentEquals(expectedAck)) {
            "Application ACK mismatch"
        }
        sendTimeout?.let(handler::removeCallbacks)
        sendTimeout = null
        pendingSend?.success(null)
        pendingSend = null
        log("acknowledgement_received", mapOf("id" to outboundId, "bytes" to outboundLength))
        outbound = emptyList()
    }

    private fun completePeripheralSend(value: ByteArray) {
        check(outbound.isNotEmpty() && outboundIsPeripheral && value.contentEquals(expectedAck)) {
            "Application ACK mismatch"
        }
        peripheralAckReceived = true
        // An ACK may arrive before the final local notification callback.
        if (outboundIndex >= outbound.size) finishPeripheralSend()
    }

    private fun finishPeripheralSend() {
        sendTimeout?.let(handler::removeCallbacks)
        sendTimeout = null
        pendingSend?.success(null)
        pendingSend = null
        log("acknowledgement_received", mapOf("id" to outboundId, "bytes" to outboundLength))
        outbound = emptyList()
    }

    private fun receiveFrame(frame: ByteArray, fromCentral: Boolean) {
        require(frame.size in 5..20 && frame[0].toInt() == 1) { "Invalid frame/version" }
        val id = frame[1].toInt() and 0xff
        val index = frame[2].toInt() and 0xff
        val count = frame[3].toInt() and 0xff
        require(id != 0 && count in 1..16 && index < count) { "Invalid frame header" }
        require(index == count - 1 || frame.size == 20) { "Short nonfinal frame" }
        if (index == 0) {
            require(receiveId == -1) { "Overlapping message" }
            acknowledgement = byteArrayOf()
            receiveId = id
            receiveCount = count
            receiveTimeout?.let(handler::removeCallbacks)
            receiveTimeout = Runnable { fail("timeout: reassembly") }.also { handler.postDelayed(it, 15_000) }
        }
        require(receiveId == id && receiveCount == count && receiveIndex == index) {
            "Out-of-order frame"
        }
        require(received.size() + frame.size - 4 <= MAX_BYTES) { "Message too large" }
        received.write(frame, 4, frame.size - 4)
        receiveIndex++
        if (receiveIndex == count) {
            val message = received.toByteArray()
            incomingAckPending = true
            if (role == Role.PERIPHERAL) clearDeadline()
            acknowledgement = byteArrayOf(
                1,
                id.toByte(),
                (message.size shr 8).toByte(),
                message.size.toByte(),
            )
            emit(mapOf("event" to "message", "connectionId" to connectionId,
                "message" to message))
            resetReceive()
            receiveTimeout?.let(handler::removeCallbacks)
            receiveTimeout = null
            if (!fromCentral) writeAckToServer()
        }
    }

    private fun writeAckToServer() {
        val value = acknowledgement.clone()
        queueClientOperation {
            ackWriteTimeout = Runnable { fail("timeout: acknowledgement write") }.also { handler.postDelayed(it, 15_000) }
            val characteristic = requireNotNull(ack)
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            characteristic.value = value
            check(gatt?.writeCharacteristic(characteristic) == true) { "ACK write rejected" }
        }
    }

    private fun resetReceive() {
        received.reset()
        receiveId = -1
        receiveCount = 0
        receiveIndex = 0
    }

    private fun fail(message: String) {
        emit(mapOf("event" to "error", "message" to message))
        stop(message, notify = true)
    }

    private fun stop(reason: String, notify: Boolean) {
        if (!active) return
        active = false
        clearDeadline()
        sendTimeout?.let(handler::removeCallbacks)
        receiveTimeout?.let(handler::removeCallbacks)
        ackWriteTimeout?.let(handler::removeCallbacks)
        sendTimeout = null
        receiveTimeout = null
        ackWriteTimeout = null
        clientOperations.clear()
        release { context.unregisterReceiver(radioReceiver) }
        pendingConnect?.error("ble_error", reason, null)
        pendingConnect = null
        pendingAdvertise?.error("ble_error", reason, null)
        pendingAdvertise = null
        pendingSend?.error("ble_error", reason, null)
        pendingSend = null
        pendingClose?.success(null)
        pendingClose = null
        incomingAckPending = false
        if (scanning) release { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        if (advertising) release { advertiser?.stopAdvertising(advertiseCallback) }
        release { gatt?.disconnect() }
        release { gatt?.close() }
        release { remote?.let { server?.cancelConnection(it) } }
        release { server?.close() }
        val oldId = connectionId
        scanning = false
        advertising = false
        ready = false
        notificationEnabled = false
        incomingAnnounced = false
        server = null
        advertiser = null
        gatt = null
        remote = null
        data = null
        ack = null
        connectionId = null
        outbound = emptyList()
        acknowledgement = byteArrayOf()
        resetReceive()
        if (notify && oldId != null) {
            emit(mapOf("event" to "disconnected", "connectionId" to oldId, "reason" to reason))
        }
        emit(mapOf("event" to "sessionEnded", "reason" to reason))
        role = Role.NONE
        active = false
    }

    private fun release(action: () -> Unit) {
        try {
            action()
        } catch (_: Exception) {
            // Continue releasing all remaining radio resources.
        }
    }
}
