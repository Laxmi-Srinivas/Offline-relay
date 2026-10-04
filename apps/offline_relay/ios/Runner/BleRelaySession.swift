import CoreBluetooth
import Flutter
import Foundation

/// Product adapter derived from the validated diagnostic sessions.
/// DATA write/notify + ACK read/write implement main's duplex transport.
final class BleRelaySession: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate {
  private enum Role { case none, central, peripheral }
  private var role: Role = .none
  private var active = true
  private var central: CBCentralManager?
  private var peripheral: CBPeripheralManager?
  private var powerAction: (() -> Void)?
  private var remote: CBPeripheral?
  private var remoteCentral: CBCentral?
  private var peers: [String: (CBPeripheral, [String: Any])] = [:]
  private var probe: CBPeripheral?
  private var probeQueue: [CBPeripheral] = []
  private var probeSeen: Set<UUID> = []
  private var probePeer: [String: Any]?
  private var peerInfo: [String: Any] = [:]
  private var connectionID: String?
  private var scanning = false
  private var ready = false
  private var service: CBMutableService?
  private var dataCharacteristic: CBCharacteristic?
  private var ackCharacteristic: CBCharacteristic?
  private var profileCharacteristic: CBCharacteristic?
  private var profileBytes = Data()
  private var localProfile: [String: Any] = [:]
  private var receiver = BleMessageReceiver()
  private var pendingStart: FlutterResult?
  private var pendingConnect: FlutterResult?
  private var pendingSend: FlutterResult?
  private var nextID: UInt8 = 0
  private var outbound: [Data] = []
  private var outboundIndex = 0
  private var expectedACK = Data()
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
  private func log(_ text: String) { NSLog("OfflineRelayBLE %lld %@", Int64(Date().timeIntervalSince1970 * 1000), text) }
  private func error(_ text: String) -> FlutterError { FlutterError(code: "ble_error", message: text, details: nil) }
  private func clear(_ key: String) { timers.removeValue(forKey: key)?.cancel(); timerTokens[key] = nil }
  private func deadline(_ key: String, onTimeout: (() -> Void)? = nil) {
    clear(key)
    let token = UUID(); timerTokens[key] = token
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.active, self.timerTokens[key] == token else { return }
      if let onTimeout = onTimeout { onTimeout() } else { self.fail("timeout: \(key)") }
    }
    timers[key] = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
  }
  private func fail(_ reason: String) { emit(["event": "error", "message": reason]); stop(reason) }

  func advertise(_ profile: [String: Any], restorationIdentifier: String? = nil, result: @escaping FlutterResult) {
    guard active, role == .none else { result(error("Stop the current BLE role first")); return }
    do { localProfile = try BleProfile.validate(profile); profileBytes = try BleProfile.encode(profile) }
    catch { result(self.error(error.localizedDescription)); return }
    role = .peripheral; pendingStart = result
    powerAction = { [weak self] in self?.registerService() }
    deadline("Bluetooth readiness")
    let options: [String: Any]? = restorationIdentifier.map { [CBPeripheralManagerOptionRestoreIdentifierKey: $0] }
    peripheral = CBPeripheralManager(delegate: self, queue: .main, options: options)
  }
  func peripheralManager(_ manager: CBPeripheralManager, willRestoreState dictionary: [String: Any]) {
    guard active, manager === peripheral, role == .peripheral else { return }
    let restored = (dictionary[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService])?
      .first(where: { $0.uuid == CBUUID(string: BleFraming.service) })
    let characteristics = restored?.characteristics ?? []
    let data = characteristics.first(where: { $0.uuid == CBUUID(string: BleFraming.data) }) as? CBMutableCharacteristic
    let ack = characteristics.first(where: { $0.uuid == CBUUID(string: BleFraming.ack) }) as? CBMutableCharacteristic
    let profile = characteristics.first(where: { $0.uuid == CBUUID(string: BleProfile.characteristic) }) as? CBMutableCharacteristic
    // Wire IDs, incomplete transfers, request correlation, and Dart connections
    // are not process-persistent. Invalidate restored live links instead of
    // pretending their in-flight chat can resume with reset ACK/message IDs.
    guard let service = restored, let data = data, let ack = ack, let profile = profile,
      data.properties.contains(.write), data.properties.contains(.notify),
      ack.properties.contains(.read), ack.properties.contains(.write),
      profile.properties.contains(.read), data.subscribedCentrals?.isEmpty != false else {
      powerAction = { [weak self] in
        guard let self = self else { return }
        self.peripheral?.removeAllServices(); self.registerService()
      }
      log("restoration_rebuild availability only; old chat invalidated")
      return
    }
    self.service = service; dataCharacteristic = data; ackCharacteristic = ack; profileCharacteristic = profile
    powerAction = { [weak self] in
      guard let self = self, let manager = self.peripheral else { return }
      self.clear("Bluetooth readiness")
      if manager.isAdvertising {
        self.pendingStart?(nil); self.pendingStart = nil
      } else {
        self.deadline("advertising start")
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BleFraming.service)],
          CBAdvertisementDataLocalNameKey: BleProfile.advertisedName(self.localProfile)])
      }
    }
    log("restoration_adopted published services")
  }
  private func registerService() {
    clear("Bluetooth readiness")
    let data = CBMutableCharacteristic(type: CBUUID(string: BleFraming.data),
      properties: [.write, .notify], value: nil, permissions: [.writeable])
    let ack = CBMutableCharacteristic(type: CBUUID(string: BleFraming.ack),
      properties: [.read, .write], value: nil, permissions: [.readable, .writeable])
    let profile = CBMutableCharacteristic(type: CBUUID(string: BleProfile.characteristic),
      properties: [.read], value: nil, permissions: [.readable])
    let service = CBMutableService(type: CBUUID(string: BleFraming.service), primary: true)
    service.characteristics = [data, ack, profile]
    self.service = service; dataCharacteristic = data; ackCharacteristic = ack
    profileCharacteristic = profile
    deadline("service registration"); peripheral?.add(service)
    log("service_created data=write,notify ack=read,write profile=read")
  }
  func startDiscovery(_ result: @escaping FlutterResult) {
    guard active, role == .none || (role == .central && remote == nil && !scanning) else {
      result(error("Stop the current BLE role first")); return
    }
    role = .central; pendingStart = result; peers = [:]; probeSeen = []
    powerAction = { [weak self] in self?.scan() }
    deadline("Bluetooth readiness")
    if let central = central, central.state == .poweredOn { let action = powerAction; powerAction = nil; action?() }
    else { central = CBCentralManager(delegate: self, queue: .main) }
  }
  private func scan() {
    clear("Bluetooth readiness"); scanning = true
    central?.scanForPeripherals(withServices: [CBUUID(string: BleFraming.service)],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    deadline("discovery"); pendingStart?(nil); pendingStart = nil
    log("discovery_started")
  }
  func stopDiscovery(_ result: FlutterResult) {
    central?.stopScan(); scanning = false; clear("discovery"); cancelProbe()
    result(nil); log("discovery_stopped")
  }
  func connect(_ id: String, result: @escaping FlutterResult) {
    guard active, role == .central, scanning, remote == nil, let found = peers[id] else {
      result(error("Nearby peer expired; start discovery first")); return
    }
    central?.stopScan(); scanning = false; clear("discovery"); cancelProbe()
    remote = found.0; peerInfo = found.1; connectionID = UUID().uuidString
    pendingConnect = result; remote?.delegate = self
    deadline("connection"); central?.connect(found.0, options: nil)
  }
  func send(_ id: String, bytes: Data, result: @escaping FlutterResult) {
    guard active, ready, connectionID == id else { result(error("Connection is not ready")); return }
    guard pendingSend == nil, outbound.isEmpty else { result(error("A message awaits its ACK")); return }
    guard !bytes.isEmpty, bytes.count <= 256 else { result(error("Message must be 1..256 bytes")); return }
    nextID = BleFraming.nextID(nextID); outbound = BleFraming.frames(bytes, id: nextID)
    outboundIndex = 0; expectedACK = BleFraming.acknowledgement(id: nextID, length: bytes.count)
    pendingSend = result; deadline("message write / application ACK")
    if role == .central { writeNext() } else { notifyNext() }
  }
  func close(_ id: String, result: FlutterResult) { if connectionID == id { stop("local close") }; result(nil) }
  func stopAdvertising(_ result: FlutterResult) {
    peripheral?.stopAdvertising(); log("advertising_stopped")
    if role == .peripheral && remoteCentral == nil { stop("advertising stopped") }
    result(nil)
  }
  func stop(_ reason: String) {
    guard active else { return }; active = false
    for key in Array(timers.keys) { clear(key) }
    let failure = error(reason)
    pendingStart?(failure); pendingStart = nil
    pendingConnect?(failure); pendingConnect = nil
    pendingSend?(failure); pendingSend = nil
    central?.stopScan(); cancelProbe()
    if let remote = remote { remote.delegate = nil; central?.cancelPeripheralConnection(remote) }
    central?.delegate = nil
    peripheral?.stopAdvertising(); peripheral?.removeAllServices(); peripheral?.delegate = nil
    remote = nil; remoteCentral = nil; ready = false; scanning = false; powerAction = nil
    operations = []; operation = nil; outbound = []; receiver.reset(); peers = [:]
    if let id = connectionID { emit(["event": "disconnected", "connectionId": id, "reason": reason]) }
    connectionID = nil; emit(["event": "sessionEnded", "reason": reason]); log("cleanup \(reason)")
  }

  private func state(_ state: CBManagerState) {
    log("bluetooth_state \(state.rawValue)")
    if state == .poweredOn { let action = powerAction; powerAction = nil; action?() }
    else if state == .unauthorized {
      let denied = FlutterError(code: "permission_denied", message: "Bluetooth permission is required", details: nil)
      pendingStart?(denied); pendingStart = nil
      pendingConnect?(denied); pendingConnect = nil
      fail("Bluetooth permission is required")
    }
    else if state != .unknown && state != .resetting { fail("Bluetooth unavailable: \(state.rawValue)") }
    else if ready || scanning { fail("Bluetooth state lost") }
  }
  func centralManagerDidUpdateState(_ manager: CBCentralManager) {
    guard active, manager === central else { return }; state(manager.state)
  }
  func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
    guard active, manager === peripheral else { return }; state(manager.state)
  }
  func centralManager(_ manager: CBCentralManager, didDiscover peer: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber) {
    guard active, scanning, manager === central else { return }
    // CoreBluetooth packs local names on a best-effort basis. Read the full
    // profile before surfacing a peer, without subscribing or issuing requests.
    if probeSeen.insert(peer.identifier).inserted { probeQueue.append(peer); nextProbe() }
  }
  private func nextProbe() {
    guard active, scanning, probe == nil, remote == nil, !probeQueue.isEmpty else { return }
    let next = probeQueue.removeFirst(); probe = next; probePeer = nil; next.delegate = self
    deadline("profile discovery") { [weak self] in
      guard let self = self, let peer = self.probe else { return }
      self.log("profile_probe_timeout")
      self.central?.cancelPeripheralConnection(peer)
      // Cancellation normally yields didDisconnect; bound even missing callbacks.
      self.finishProbe(peer)
    }
    central?.connect(next, options: nil)
  }
  private func finishProbe(_ peer: CBPeripheral) {
    guard peer === probe else { return }
    clear("profile discovery"); peer.delegate = nil; probe = nil
    if scanning, var map = probePeer {
      let id = peer.identifier.uuidString; map["id"] = id
      peers[id] = (peer, map); emit(["event": "peerDiscovered", "peer": map]); clear("discovery")
    }
    probePeer = nil; nextProbe()
  }
  private func cancelProbe() {
    clear("profile discovery"); probeQueue = []; probePeer = nil
    if let probe = probe { probe.delegate = nil; central?.cancelPeripheralConnection(probe) }
    probe = nil
  }

  func centralManager(_ manager: CBCentralManager, didConnect peer: CBPeripheral) {
    guard active, manager === central else { return }
    if peer === probe { peer.discoverServices([CBUUID(string: BleFraming.service)]); return }
    guard peer === remote else { return }
    clear("connection"); deadline("service discovery")
    peer.discoverServices([CBUUID(string: BleFraming.service)]); log("connection_established role=central")
  }
  func centralManager(_ manager: CBCentralManager, didFailToConnect peer: CBPeripheral, error: Error?) {
    guard active, manager === central else { return }
    if peer === probe { finishProbe(peer); return }
    guard peer === remote else { return }; fail("connection_failed: \(String(describing: error))")
  }
  func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peer: CBPeripheral, error: Error?) {
    guard active, manager === central else { return }
    if peer === probe { finishProbe(peer); return }
    guard peer === remote else { return }; stop("disconnect: \(String(describing: error))")
  }
  func peripheral(_ peer: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    guard active, peer === remote else { return }
    if invalidatedServices.contains(where: { $0.uuid == CBUUID(string: BleFraming.service) }) { stop("Peer removed relay service") }
  }
  func peripheral(_ peer: CBPeripheral, didDiscoverServices error: Error?) {
    guard active else { return }
    if peer === probe {
      if error == nil, let service = peer.services?.first(where: { $0.uuid == CBUUID(string: BleFraming.service) }) {
        peer.discoverCharacteristics([CBUUID(string: BleProfile.characteristic)], for: service)
      } else { central?.cancelPeripheralConnection(peer) }
      return
    }
    guard peer === remote else { return }
    guard error == nil, let service = peer.services?.first(where: { $0.uuid == CBUUID(string: BleFraming.service) && $0.isPrimary }) else {
      fail("Expected service missing: \(String(describing: error))"); return
    }
    peer.discoverCharacteristics(nil, for: service)
  }
  func peripheral(_ peer: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard active else { return }
    if peer === probe {
      if error == nil, let profile = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BleProfile.characteristic) && $0.properties.contains(.read) }) {
        peer.readValue(for: profile)
      } else { central?.cancelPeripheralConnection(peer) }
      return
    }
    guard peer === remote else { return }
    guard error == nil,
      let data = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BleFraming.data) }),
      let ack = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BleFraming.ack) }),
      data.properties.contains(.write), data.properties.contains(.notify),
      ack.properties.contains(.read), ack.properties.contains(.write),
      peer.maximumWriteValueLength(for: .withResponse) >= 20 else { fail("Incompatible DATA/ACK properties"); return }
    dataCharacteristic = data; ackCharacteristic = ack
    if let profile = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BleProfile.characteristic) }) {
      enqueue(profile, bytes: nil) { [weak self] bytes, error in
        guard let self = self, self.active else { return }
        do {
          guard error == nil, let bytes = bytes else { throw error ?? NSError(domain: "Profile read", code: 1) }
          self.peerInfo = try BleProfile.decode(bytes)
          peer.setNotifyValue(true, for: data)
        } catch { self.fail("Profile read failed: \(error)") }
      }
    } else { peer.setNotifyValue(true, for: data) }
  }
  func peripheral(_ peer: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    guard active, peer === remote, characteristic.uuid == CBUUID(string: BleFraming.data) else { return }
    guard error == nil, characteristic.isNotifying else { fail("Notification subscription failed"); return }
    clear("service discovery"); ready = true
    pendingConnect?(["connectionId": connectionID!, "peer": peerInfo]); pendingConnect = nil
    log("connection_ready role=central")
  }

  // Serialize central GATT reads/writes, including ACKs for reverse notifications.
  private func enqueue(_ characteristic: CBCharacteristic, bytes: Data?, done: @escaping (Data?, Error?) -> Void) {
    operations.append(Operation(characteristic: characteristic, bytes: bytes, done: done)); pump()
  }
  private func pump() {
    guard active, operation == nil, !operations.isEmpty, let peer = remote else { return }
    let next = operations.removeFirst(); operation = next
    if let bytes = next.bytes { peer.writeValue(bytes, for: next.characteristic, type: .withResponse) }
    else { peer.readValue(for: next.characteristic) }
  }
  private func finished(_ characteristic: CBCharacteristic, bytes: Data?, error: Error?, isWrite: Bool) {
    guard let current = operation, current.characteristic.uuid == characteristic.uuid,
      (current.bytes != nil) == isWrite else { fail("Unexpected GATT completion"); return }
    operation = nil; current.done(bytes, error); pump()
  }
  private func writeNext() {
    guard let data = dataCharacteristic else { fail("Missing DATA"); return }
    enqueue(data, bytes: outbound[outboundIndex]) { [weak self] _, error in
      guard let self = self, self.active else { return }
      guard error == nil else { self.fail("DATA write failed: \(String(describing: error))"); return }
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
  private func notifyNext() {
    guard let manager = peripheral, let peer = remoteCentral,
      let data = dataCharacteristic as? CBMutableCharacteristic else { fail("Missing notification peer"); return }
    while outboundIndex < outbound.count {
      if !manager.updateValue(outbound[outboundIndex], for: data, onSubscribedCentrals: [peer]) { return }
      outboundIndex += 1
    }
    log("notifications_submitted frames=\(outbound.count)")
  }
  private func completeSend(_ bytes: Data) {
    guard pendingSend != nil, outboundIndex == outbound.count, bytes == expectedACK else { fail("Application ACK mismatch"); return }
    clear("message write / application ACK"); outbound = []
    let result = pendingSend; pendingSend = nil; result?(nil); log("acknowledgement_received")
  }
  func peripheral(_ peer: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard active, peer === remote else { return }; finished(characteristic, bytes: nil, error: error, isWrite: true)
  }
  func peripheral(_ peer: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard active else { return }
    if peer === probe {
      if characteristic.uuid == CBUUID(string: BleProfile.characteristic), error == nil,
        let bytes = characteristic.value { probePeer = try? BleProfile.decode(bytes) }
      central?.cancelPeripheralConnection(peer)
      return
    }
    guard peer === remote else { return }
    if characteristic.uuid == CBUUID(string: BleFraming.data) {
      guard error == nil, let value = characteristic.value else { fail("DATA notification error"); return }
      do {
        let starting = !receiver.isReceiving
        let message = try receiver.receive(value)
        if starting { deadline("reassembly") }
        if let message = message, let ack = receiver.acknowledgement, let target = ackCharacteristic {
          clear("reassembly")
          emit(["event": "message", "connectionId": connectionID!, "message": FlutterStandardTypedData(bytes: message)])
          enqueue(target, bytes: ack) { [weak self] _, error in if let error = error { self?.fail("ACK write failed: \(error)") } }
        }
      } catch { fail("Invalid notification frame: \(error)") }
    } else { finished(characteristic, bytes: characteristic.value, error: error, isWrite: false) }
  }

  func peripheralManager(_ manager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    guard active, manager === peripheral, service === self.service else { return }
    guard error == nil else { fail("service_registration: \(String(describing: error))"); return }
    clear("service registration"); deadline("advertising start")
    manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BleFraming.service)],
      CBAdvertisementDataLocalNameKey: BleProfile.advertisedName(localProfile)])
  }
  func peripheralManagerDidStartAdvertising(_ manager: CBPeripheralManager, error: Error?) {
    guard active, manager === peripheral else { return }
    guard error == nil else { pendingStart?(FlutterError(code: "advertise_error", message: error?.localizedDescription, details: nil)); pendingStart = nil; fail("Advertising failed"); return }
    clear("advertising start"); pendingStart?(nil); pendingStart = nil; log("advertising_started")
  }
  func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
    guard active, manager === peripheral, characteristic.uuid == CBUUID(string: BleFraming.data) else { return }
    guard remoteCentral == nil || remoteCentral?.identifier == central.identifier else { log("peer_rejected"); return }
    guard !ready else { return }
    guard central.maximumUpdateValueLength >= 20 else { fail("Peer notification capacity below 20 bytes"); return }
    remoteCentral = central; connectionID = UUID().uuidString; ready = true
    peerInfo = ["id": central.identifier.uuidString, "label": "Nearby OfflineRelay user", "metadata": [String: String]()]
    emit(["event": "incomingConnection", "connectionId": connectionID!, "peer": peerInfo]); log("connection_ready role=peripheral")
  }
  func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
    guard active, manager === peripheral, central.identifier == remoteCentral?.identifier,
      characteristic.uuid == CBUUID(string: BleFraming.data) else { return }; stop("Peer unsubscribed")
  }
  func peripheralManagerIsReady(toUpdateSubscribers manager: CBPeripheralManager) {
    guard active, manager === peripheral, pendingSend != nil else { return }; notifyNext()
  }
  func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    guard active, manager === peripheral, let first = requests.first else { return }
    var candidate = receiver
    var messages: [Data] = []
    var acks: [Data] = []
    let wasReceiving = receiver.isReceiving
    do {
      for request in requests {
        guard ready, request.central.identifier == remoteCentral?.identifier, request.offset == 0,
          let bytes = request.value else { throw BleMessageReceiver.Failure.malformed }
        if request.characteristic.uuid == CBUUID(string: BleFraming.data) {
          if let message = try candidate.receive(bytes) { messages.append(message) }
        } else if request.characteristic.uuid == CBUUID(string: BleFraming.ack) {
          guard pendingSend != nil, outboundIndex == outbound.count, bytes == expectedACK, acks.isEmpty else {
            throw BleMessageReceiver.Failure.malformed
          }
          acks.append(bytes)
        } else { throw BleMessageReceiver.Failure.malformed }
      }
      receiver = candidate
      if receiver.isReceiving { if !wasReceiving { deadline("reassembly") } } else { clear("reassembly") }
      manager.respond(to: first, withResult: .success)
      for message in messages { emit(["event": "message", "connectionId": connectionID!, "message": FlutterStandardTypedData(bytes: message)]) }
      for ack in acks { completeSend(ack) }
    } catch {
      manager.respond(to: first, withResult: .unlikelyError)
      receiver.reset(); clear("reassembly"); log("receive_error \(error)")
    }
  }
  func peripheralManager(_ manager: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
    guard active, manager === peripheral else { return }
    if request.characteristic.uuid == CBUUID(string: BleProfile.characteristic) {
      guard request.offset <= profileBytes.count else { manager.respond(to: request, withResult: .invalidOffset); return }
      request.value = Data(profileBytes.dropFirst(request.offset)); manager.respond(to: request, withResult: .success)
    } else if request.characteristic.uuid == CBUUID(string: BleFraming.ack),
      request.central.identifier == remoteCentral?.identifier, request.offset == 0, let ack = receiver.acknowledgement {
      request.value = ack; manager.respond(to: request, withResult: .success)
    } else { manager.respond(to: request, withResult: .unlikelyError) }
  }
}
