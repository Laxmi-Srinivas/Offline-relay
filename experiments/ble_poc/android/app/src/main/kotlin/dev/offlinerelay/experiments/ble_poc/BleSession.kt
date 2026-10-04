@file:Suppress("DEPRECATION", "MissingPermission")

package dev.offlinerelay.experiments.ble_poc

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.io.ByteArrayOutputStream
import java.util.UUID

/** Disposable foreground experiment. Never imported by the product host. */
class BleSession(context: Context, private val log: (String) -> Unit) {
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private val adapter = requireNotNull(manager.adapter) { "Bluetooth unavailable" }
    private val context = context
    private val handler = Handler(Looper.getMainLooper())
    private var active = true
    private var scanning = false
    private var gatt: BluetoothGatt? = null
    private var server: BluetoothGattServer? = null
    private var remote: BluetoothDevice? = null
    private var data: BluetoothGattCharacteristic? = null
    private var ack: BluetoothGattCharacteristic? = null
    private var ready = false
    private var outbound: List<ByteArray> = emptyList()
    private var sentIndex = 0
    private var messageId = 0
    private var sentLength = 0
    private val received = ByteArrayOutputStream()
    private var receiveId = -1
    private var receiveCount = 0
    private var receiveIndex = 0
    private var acknowledgement = byteArrayOf()
    private var timeout: Runnable? = null

    companion object {
        val SERVICE: UUID = UUID.fromString("41729610-0934-4e0e-b749-170442310001")
        val DATA: UUID = UUID.fromString("41729610-0934-4e0e-b749-170442310002")
        val ACK: UUID = UUID.fromString("41729610-0934-4e0e-b749-170442310003")
    }

    // Platform callbacks may arrive on binder threads. Serialize all state here.
    private fun event(block: () -> Unit) {
        handler.post {
            if (active) try { block() } catch (error: Exception) {
                stop("${error.javaClass.simpleName}: ${error.message}")
            }
        }
    }

    private fun deadline(stage: String) {
        clearDeadline()
        timeout = Runnable { stop("timeout: $stage") }.also { handler.postDelayed(it, 15000) }
    }

    private fun clearDeadline() { timeout?.let { handler.removeCallbacks(it) }; timeout = null }

    fun discover() {
        check(adapter.isEnabled) { "Enable Bluetooth first" }
        scanning = true
        adapter.bluetoothLeScanner.startScan(
            listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scanCallback)
        log("discovery_started service=$SERVICE")
        deadline("discovery")
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) = event { stop("scan_error code=$errorCode") }
        override fun onScanResult(callbackType: Int, result: ScanResult) = event {
            if (scanning) {
                log("device_discovered address=${result.device.address} rssi=${result.rssi}")
                adapter.bluetoothLeScanner.stopScan(this)
                scanning = false
                deadline("connection")
                gatt = result.device.connectGatt(context, false, clientCallback, BluetoothDevice.TRANSPORT_LE)
                check(gatt != null) { "connectGatt returned null" }
            }
        }
    }

    fun advertise() {
        check(adapter.isEnabled) { "Enable Bluetooth first" }
        check(adapter.isMultipleAdvertisementSupported) { "Peripheral advertising unsupported on this device" }
        server = requireNotNull(manager.openGattServer(context, serverCallback)) { "GATT server unavailable" }
        val service = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(BluetoothGattCharacteristic(DATA,
            BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE))
        service.addCharacteristic(BluetoothGattCharacteristic(ACK,
            BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ))
        check(server!!.addService(service)) { "addService rejected" }
        deadline("service registration")
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) = event {
            clearDeadline(); log("advertising_started service=$SERVICE")
        }
        override fun onStartFailure(errorCode: Int) = event { stop("advertise_error code=$errorCode") }
    }

    fun send(payload: ByteArray) {
        check(ready && active) { "Central is not ready" }
        check(outbound.isEmpty()) { "A message is awaiting acknowledgement" }
        require(payload.isNotEmpty() && payload.size <= 256)
        messageId = (messageId % 255) + 1
        sentLength = payload.size
        val chunks = payload.toList().chunked(16)
        outbound = chunks.mapIndexed { index, bytes ->
            byteArrayOf(1, messageId.toByte(), index.toByte(), chunks.size.toByte()) + bytes.toByteArray()
        }
        sentIndex = 0
        deadline("message write / application ACK")
        writeNext()
    }

    private fun writeNext() {
        val characteristic = requireNotNull(data)
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = outbound[sentIndex]
        check(gatt!!.writeCharacteristic(characteristic)) { "writeCharacteristic rejected" }
    }

    private val clientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(client: BluetoothGatt, status: Int, newState: Int) = event {
            if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                stop("disconnect status=$status state=$newState (platform provides no further reason)")
            } else if (newState == BluetoothProfile.STATE_CONNECTED) {
                log("connection_established role=central")
                deadline("service discovery")
                check(client.discoverServices()) { "discoverServices rejected" }
            }
        }
        override fun onServicesDiscovered(client: BluetoothGatt, status: Int) = event {
            check(status == BluetoothGatt.GATT_SUCCESS) { "service_discovery status=$status" }
            val service = requireNotNull(client.getService(SERVICE)) { "Expected service missing" }
            log("service_discovered uuid=$SERVICE")
            data = requireNotNull(service.getCharacteristic(DATA)) { "Data characteristic missing" }
            ack = requireNotNull(service.getCharacteristic(ACK)) { "ACK characteristic missing" }
            check(data!!.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0)
            check(ack!!.properties and BluetoothGattCharacteristic.PROPERTY_READ != 0)
            log("characteristic_discovered data=$DATA ack=$ACK")
            clearDeadline(); ready = true
        }
        override fun onCharacteristicWrite(client: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) = event {
            check(status == BluetoothGatt.GATT_SUCCESS) { "write_error status=$status" }
            check(characteristic.uuid == DATA && outbound.isNotEmpty()) { "Unexpected write callback" }
            sentIndex++
            if (sentIndex < outbound.size) writeNext() else {
                log("message_sent id=$messageId bytes=$sentLength frames=${outbound.size}")
                check(client.readCharacteristic(ack)) { "ACK read rejected" }
            }
        }
        // Legacy callback retained for API 31/32; Android dispatches it on newer releases too.
        override fun onCharacteristicRead(client: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            val value = characteristic.value?.clone() ?: byteArrayOf()
            event {
                check(status == BluetoothGatt.GATT_SUCCESS) { "ack_read_error status=$status" }
                check(characteristic.uuid == ACK && outbound.isNotEmpty()) { "Unexpected ACK callback" }
                val expected = byteArrayOf(1, messageId.toByte(), (sentLength shr 8).toByte(), sentLength.toByte())
                check(value.contentEquals(expected)) { "Application ACK mismatch" }
                clearDeadline(); outbound = emptyList()
                log("acknowledgement_received id=$messageId bytes=$sentLength")
            }
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) = event {
            check(status == BluetoothGatt.GATT_SUCCESS) { "service_registration status=$status" }
            log("service_registered uuid=${service.uuid}")
            val advertiser = requireNotNull(adapter.bluetoothLeAdvertiser) { "Advertiser unavailable" }
            deadline("advertising start")
            advertiser.startAdvertising(AdvertiseSettings.Builder().setConnectable(true)
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).build(),
                AdvertiseData.Builder().addServiceUuid(ParcelUuid(SERVICE)).build(), advertiseCallback)
        }
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) = event {
            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                if (remote != null && remote != device) {
                    server?.cancelConnection(device); log("peer_rejected: one connection only")
                } else {
                    remote = device
                    log("connection_established role=peripheral address=${device.address}")
                }
            } else if (device == remote) stop("disconnect status=$status state=$newState")
            else log("peer_connection_state status=$status state=$newState")
        }
        override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int,
            characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean,
            responseNeeded: Boolean, offset: Int, value: ByteArray) {
            val frame = value.clone()
            event {
                var status = BluetoothGatt.GATT_SUCCESS
                try {
                    require(device == remote && characteristic.uuid == DATA && !preparedWrite && offset == 0)
                    require(responseNeeded) { "Only writes with response are supported" }
                    receive(frame)
                } catch (error: IllegalArgumentException) {
                    status = BluetoothGatt.GATT_FAILURE
                    log("receive_error: ${error.message}")
                    resetReceive(); acknowledgement = byteArrayOf(); clearDeadline()
                }
                if (responseNeeded) check(server!!.sendResponse(device, requestId, status, offset, null)) {
                    "sendResponse rejected"
                }
            }
        }
        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int,
            offset: Int, characteristic: BluetoothGattCharacteristic) = event {
            val valid = device == remote && characteristic.uuid == ACK && offset == 0 && acknowledgement.isNotEmpty()
            check(server!!.sendResponse(device, requestId,
                if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE,
                offset, if (valid) acknowledgement else null)) { "ACK sendResponse rejected" }
            if (valid) log("acknowledgement_response_submitted id=${acknowledgement[1].toInt() and 255}")
        }
        override fun onExecuteWrite(device: BluetoothDevice, requestId: Int, execute: Boolean) = event {
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
        }
    }

    private fun resetReceive() { received.reset(); receiveId = -1; receiveIndex = 0; receiveCount = 0 }

    private fun receive(frame: ByteArray) {
        require(frame.size in 5..20 && frame[0].toInt() == 1) { "Invalid frame/version" }
        val id = frame[1].toInt() and 255
        val index = frame[2].toInt() and 255
        val count = frame[3].toInt() and 255
        require(id != 0 && count in 1..16 && index < count)
        require(index == count - 1 || frame.size == 20) { "Short nonfinal frame" }
        if (index == 0) {
            require(receiveId == -1) { "Overlapping message" }
            acknowledgement = byteArrayOf()
            receiveId = id; receiveCount = count; deadline("reassembly")
        }
        require(receiveId == id && receiveCount == count && receiveIndex == index) { "Out-of-order frame" }
        require(received.size() + frame.size - 4 <= 256)
        received.write(frame, 4, frame.size - 4)
        receiveIndex++
        if (receiveIndex == count) {
            val bytes = received.toByteArray()
            require(bytes.contentEquals("Hello".toByteArray()) || bytes.contentEquals(ByteArray(256) { it.toByte() })) {
                "Payload differs from the two allowed test vectors"
            }
            log("message_received id=$id bytes=${bytes.size} exact_payload_verified=true" +
                if (bytes.size == 5) " text=Hello" else " vector=00..ff")
            acknowledgement = byteArrayOf(1, id.toByte(), (bytes.size shr 8).toByte(), bytes.size.toByte())
            resetReceive(); clearDeadline()
        }
    }

    fun stop(reason: String) {
        if (!active) return
        active = false; ready = false; clearDeadline()
        // Cleanup each resource even if permissions were revoked or Bluetooth disabled.
        fun release(action: () -> Unit) { try { action() } catch (error: Exception) { log("cleanup_error: ${error.message}") } }
        if (scanning) release { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        release { adapter.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback) }
        release { gatt?.disconnect() }; release { gatt?.close() }
        release { remote?.let { server?.cancelConnection(it) } }; release { server?.close() }
        gatt = null; server = null; remote = null; outbound = emptyList()
        acknowledgement = byteArrayOf(); resetReceive()
        log("disconnected_or_stopped reason=$reason")
    }
}
