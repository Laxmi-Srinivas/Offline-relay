import CoreBluetooth
import Flutter
import Foundation

/// Phase 1 requester only. Central GATT logic is adapted from ios-mvp 4cf4865.
/// Complete messages are opaque bytes; encryption remains entirely in Flutter.
final class BleRelaySession: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  private var active = true
  private var central: CBCentralManager?
  private var powerAction: (() -> Void)?
  private var remote: CBPeripheral?
  private var peers: [String: (CBPeripheral, [String: Any])] = [:]
  private var peerInfo: [String: Any] = [:]
  private var connectionID: String?
  private var scanning = false
  private var ready = false
  private var dataCharacteristic: CBCharacteristic?
  private var ackCharacteristic: CBCharacteristic?
  private var receiver = BleMessageReceiver()
  private var pendingStart: FlutterResult?
  private var pendingConnect: FlutterResult?
  private var pendingSend: FlutterResult?
  private var nextID: UInt8 = 0
  private var outbound: [Data] = []
  private var outboundIndex = 0
  private var expectedACK = Data()
  private var pendingInboundACKs = 0
  private var closing = false
  private var pendingCloses: [FlutterResult] = []
  private let emit: ([String: Any]) -> Void
  private var timers: [String: DispatchWorkItem] = [:]
  private var timerTokens: [String: UUID] = [:]
  private struct Operation {
    let characteristic: CBCharacteristic
    let bytes: Data? // nil = read
    let done: (Data?, Error?) -> Void
  }
  private var operations: [Operation] = []
  private var operation: Operation?

  init(emit: @escaping ([String: Any]) -> Void) { self.emit = emit; super.init() }
  private func error(_ text: String) -> FlutterError {
    FlutterError(code: "ble_error", message: text, details: nil)
  }
  private func clear(_ key: String) {
    timers.removeValue(forKey: key)?.cancel(); timerTokens[key] = nil
  }
  private func deadline(_ key: String) {
    clear(key)
    let token = UUID(); timerTokens[key] = token
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.active, self.timerTokens[key] == token else { return }
      self.fail("timeout: \(key)")
    }
    timers[key] = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
  }
  private func fail(_ reason: String) {
    emit(["event": "error", "message": reason]); stop(reason)
  }

  func startDiscovery(_ result: @escaping FlutterResult) {
    guard active, pendingStart == nil, pendingConnect == nil, remote == nil, !scanning else {
      result(error("Stop the current BLE session first")); return
    }
    pendingStart = result; peers = [:]
    powerAction = { [weak self] in self?.scan() }
    deadline("Bluetooth readiness")
    if let central = central, central.state == .poweredOn {
      let action = powerAction; powerAction = nil; action?()
    } else { central = CBCentralManager(delegate: self, queue: .main) }
  }
  private func scan() {
    clear("Bluetooth readiness"); scanning = true
    central?.scanForPeripherals(withServices: [CBUUID(string: BleFraming.service)],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    deadline("discovery"); pendingStart?(nil); pendingStart = nil
  }
  func stopDiscovery(_ result: FlutterResult) {
    central?.stopScan(); scanning = false; clear("discovery")
    // Retain discovered handles after Flutter's presentation scan timer expires.
    if pendingStart != nil {
      clear("Bluetooth readiness"); powerAction = nil
      let pending = pendingStart; pendingStart = nil
      pending?(error("Search cancelled"))
    }
    result(nil)
  }
  func connect(_ id: String, result: @escaping FlutterResult) {
    guard active, !closing, pendingConnect == nil, remote == nil,
      let manager = central, manager.state == .poweredOn, let found = peers[id] else {
      result(error("Nearby peer expired; search again")); return
    }
    manager.stopScan(); scanning = false; clear("discovery")
    remote = found.0; peerInfo = found.1; connectionID = UUID().uuidString
    pendingConnect = result; found.0.delegate = self
    deadline("connection"); manager.connect(found.0, options: nil)
  }
  func send(_ id: String, bytes: Data, result: @escaping FlutterResult) {
    guard active, ready, !closing, connectionID == id else {
      result(error("Connection is not ready")); return
    }
    guard pendingSend == nil, outbound.isEmpty else {
      result(error("A message awaits its ACK")); return
    }
    guard !bytes.isEmpty, bytes.count <= 256 else {
      result(error("Message must be 1..256 bytes")); return
    }
    nextID = BleFraming.nextID(nextID); outbound = BleFraming.frames(bytes, id: nextID)
    outboundIndex = 0; expectedACK = BleFraming.acknowledgement(id: nextID, length: bytes.count)
    pendingSend = result; deadline("message write / application ACK"); writeNext()
  }
  func close(_ id: String, result: @escaping FlutterResult) {
    guard active, connectionID == id else { result(nil); return }
    closing = true; pendingCloses.append(result)
    // Receiving encrypted End Chat can cause Flutter to close immediately.
    // Keep the GATT queue alive until the final notification ACK write completes.
    if pendingInboundACKs == 0 { stop("local close") }
    else { deadline("final acknowledgement before close") }
  }
  func stop(_ reason: String) {
    guard active else { return }; active = false
    for key in Array(timers.keys) { clear(key) }
    let failure = error(reason)
    let start = pendingStart; pendingStart = nil
    let connect = pendingConnect; pendingConnect = nil
    let send = pendingSend; pendingSend = nil
    let closes = pendingCloses; pendingCloses = []
    central?.stopScan()
    if let remote = remote { remote.delegate = nil; central?.cancelPeripheralConnection(remote) }
    central?.delegate = nil
    remote = nil; ready = false; scanning = false; powerAction = nil
    dataCharacteristic = nil; ackCharacteristic = nil
    operations = []; operation = nil; outbound = []; receiver.reset(); peers = [:]
    pendingInboundACKs = 0
    let id = connectionID; connectionID = nil
    start?(failure); connect?(failure); send?(failure)
    if let id = id { emit(["event": "disconnected", "connectionId": id, "reason": reason]) }
    emit(["event": "sessionEnded", "reason": reason])
    for close in closes { close(nil) }
  }

  func centralManagerDidUpdateState(_ manager: CBCentralManager) {
    guard active, manager === central else { return }
    if manager.state == .poweredOn {
      let action = powerAction; powerAction = nil; action?()
    } else if manager.state == .unauthorized {
      // Avoid the unchanged controller's Android-specific permission wording.
      let denied = FlutterError(code: "ios_access_denied",
        message: "Allow onya access in iOS Settings > Privacy & Security to find nearby helpers.", details: nil)
      let start = pendingStart; pendingStart = nil
      let connect = pendingConnect; pendingConnect = nil
      start?(denied); connect?(denied)
      stop("Nearby access denied. Enable onya in iOS Settings > Privacy & Security.")
    } else if manager.state != .unknown && manager.state != .resetting {
      fail("Bluetooth is unavailable. Turn it on and search again.")
    } else if ready || scanning { fail("Bluetooth state lost. Search again.") }
  }
  func centralManager(_ manager: CBCentralManager, didDiscover peer: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber) {
    guard active, scanning, manager === central,
      let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
      let bytes = serviceData[CBUUID(string: BleFraming.service)],
      let map = BleAndroidProfile.peer(id: peer.identifier.uuidString, serviceData: bytes) else { return }
    let id = peer.identifier.uuidString
    let isNew = peers[id] == nil
    peers[id] = (peer, map)
    if isNew { emit(["event": "peerDiscovered", "peer": map]) }
    clear("discovery")
  }
  func centralManager(_ manager: CBCentralManager, didConnect peer: CBPeripheral) {
    guard active, manager === central, peer === remote else { return }
    clear("connection"); deadline("service discovery")
    peer.discoverServices([CBUUID(string: BleFraming.service)])
  }
  func centralManager(_ manager: CBCentralManager, didFailToConnect peer: CBPeripheral, error: Error?) {
    guard active, manager === central, peer === remote else { return }
    fail("Connection failed. Search again.")
  }
  func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peer: CBPeripheral, error: Error?) {
    guard active, manager === central, peer === remote else { return }
    stop("Peer disconnected")
  }
  func peripheral(_ peer: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    guard active, peer === remote else { return }
    if invalidatedServices.contains(where: { $0.uuid == CBUUID(string: BleFraming.service) }) {
      stop("Peer removed relay service")
    }
  }
  func peripheral(_ peer: CBPeripheral, didDiscoverServices error: Error?) {
    guard active, peer === remote else { return }
    guard error == nil,
      let service = peer.services?.first(where: { $0.uuid == CBUUID(string: BleFraming.service) && $0.isPrimary }) else {
      fail("Expected relay service missing"); return
    }
    peer.discoverCharacteristics([CBUUID(string: BleFraming.data), CBUUID(string: BleFraming.ack)], for: service)
  }
  func peripheral(_ peer: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard active, peer === remote else { return }
    guard error == nil,
      let data = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BleFraming.data) }),
      let ack = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BleFraming.ack) }),
      data.properties.contains(.write), data.properties.contains(.notify),
      ack.properties.contains(.read), ack.properties.contains(.write),
      peer.maximumWriteValueLength(for: .withResponse) >= 20 else {
      fail("Incompatible DATA/ACK properties"); return
    }
    dataCharacteristic = data; ackCharacteristic = ack
    peer.setNotifyValue(true, for: data)
  }
  func peripheral(_ peer: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    guard active, peer === remote, characteristic.uuid == CBUUID(string: BleFraming.data) else { return }
    guard error == nil, characteristic.isNotifying else { fail("Notification subscription failed"); return }
    guard !ready, let id = connectionID, pendingConnect != nil else { return }
    clear("service discovery"); ready = true
    let result = pendingConnect; pendingConnect = nil
    result?(["connectionId": id, "peer": peerInfo])
  }

  // Reused central queue: DATA writes, outbound ACK reads, and inbound ACK writes.
  private func enqueue(_ characteristic: CBCharacteristic, bytes: Data?, done: @escaping (Data?, Error?) -> Void) {
    operations.append(Operation(characteristic: characteristic, bytes: bytes, done: done)); pump()
  }
  private func pump() {
    guard active, operation == nil, !operations.isEmpty, let peer = remote else { return }
    let next = operations.removeFirst(); operation = next
    deadline("GATT operation")
    if let bytes = next.bytes { peer.writeValue(bytes, for: next.characteristic, type: .withResponse) }
    else { peer.readValue(for: next.characteristic) }
  }
  private func finished(_ characteristic: CBCharacteristic, bytes: Data?, error: Error?, isWrite: Bool) {
    guard let current = operation, current.characteristic === characteristic,
      (current.bytes != nil) == isWrite else { fail("Unexpected GATT completion"); return }
    clear("GATT operation"); operation = nil; current.done(bytes, error); pump()
  }
  private func writeNext() {
    guard let data = dataCharacteristic else { fail("Missing DATA"); return }
    enqueue(data, bytes: outbound[outboundIndex]) { [weak self] _, error in
      guard let self = self, self.active else { return }
      guard error == nil else { self.fail("DATA write failed"); return }
      self.outboundIndex += 1
      if self.outboundIndex < self.outbound.count { self.writeNext() }
      else if let ack = self.ackCharacteristic {
        self.enqueue(ack, bytes: nil) { [weak self] bytes, error in
          guard let self = self, self.active else { return }
          guard error == nil, let bytes = bytes else { self.fail("ACK read failed"); return }
          self.completeSend(bytes)
        }
      }
    }
  }
  private func completeSend(_ bytes: Data) {
    guard pendingSend != nil, outboundIndex == outbound.count, bytes == expectedACK else {
      fail("Application ACK mismatch"); return
    }
    clear("message write / application ACK"); outbound = []
    let result = pendingSend; pendingSend = nil; result?(nil)
  }
  func peripheral(_ peer: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard active, peer === remote else { return }
    finished(characteristic, bytes: nil, error: error, isWrite: true)
  }
  func peripheral(_ peer: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard active, peer === remote else { return }
    if characteristic.uuid == CBUUID(string: BleFraming.data) {
      guard ready, error == nil, let value = characteristic.value else {
        fail("DATA notification error"); return
      }
      do {
        let starting = !receiver.isReceiving
        let message = try receiver.receive(value)
        if starting { deadline("reassembly") }
        if let message = message, let ack = receiver.acknowledgement,
          let target = ackCharacteristic, let id = connectionID {
          clear("reassembly"); pendingInboundACKs += 1
          // Queue the ACK before Flutter can react to End Chat or rejection.
          enqueue(target, bytes: ack) { [weak self] _, error in
            guard let self = self, self.active else { return }
            guard error == nil else { self.fail("ACK write failed"); return }
            self.pendingInboundACKs -= 1
            if self.closing && self.pendingInboundACKs == 0 { self.stop("local close") }
          }
          emit(["event": "message", "connectionId": id, "message": FlutterStandardTypedData(bytes: message)])
        }
      } catch { fail("Invalid notification frame") }
    } else { finished(characteristic, bytes: characteristic.value, error: error, isWrite: false) }
  }
}
