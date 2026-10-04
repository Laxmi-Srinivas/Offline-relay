import CoreBluetooth
import Foundation

/// Disposable foreground central. Each role restart gets a new manager/delegate.
final class BleCentralSession: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  private enum Stage { case power, scanning, connecting, services, characteristics, ready, writing, ack, stopped }
  private var stage: Stage = .power
  private var manager: CBCentralManager!
  private var peer: CBPeripheral?
  private var dataCharacteristic: CBCharacteristic?
  private var ackCharacteristic: CBCharacteristic?
  private var timer: DispatchWorkItem?
  private var deadlineGeneration = 0
  private var id: UInt8 = 0
  private var frames: [Data] = []
  private var index = 0
  private var length = 0
  private let log: (String) -> Void

  init(log: @escaping (String) -> Void) {
    self.log = log
    super.init()
    manager = CBCentralManager(delegate: self, queue: .main)
    deadline("Bluetooth readiness")
  }

  private func deadline(_ name: String) {
    clearDeadline()
    let generation = deadlineGeneration
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.stage != .stopped,
        self.deadlineGeneration == generation else { return }
      self.log("timeout stage=\(name)")
      self.stop("timeout: \(name)")
    }
    timer = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
  }

  private func clearDeadline() {
    deadlineGeneration += 1
    timer?.cancel()
    timer = nil
  }

  private func fail(_ reason: String) {
    log("error: \(reason)")
    stop(reason)
  }

  func stop(_ reason: String) {
    guard stage != .stopped else { return }
    stage = .stopped
    clearDeadline()
    if manager.isScanning { manager.stopScan(); log("scan_stopped reason=\(reason)") }
    if let peer = peer {
      peer.delegate = nil
      manager.cancelPeripheralConnection(peer)
      log("disconnect_requested identifier=\(peer.identifier)")
    }
    manager.delegate = nil
    peer = nil
    dataCharacteristic = nil
    ackCharacteristic = nil
    frames = []
    log("disconnected_or_stopped reason=\(reason)")
  }

  func send(_ payload: Data) throws {
    guard stage == .ready else {
      throw NSError(domain: "OfflineRelayBLE", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Central is not ready or awaiting acknowledgement"])
    }
    guard payload == BleProtocol.hello || payload == BleProtocol.larger else {
      throw NSError(domain: "OfflineRelayBLE", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported test vector"])
    }
    guard let peer = peer, peer.maximumWriteValueLength(for: .withResponse) >= 20 else {
      throw NSError(domain: "OfflineRelayBLE", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "20-byte writes with response unavailable"])
    }
    id = BleProtocol.nextID(id)
    length = payload.count
    frames = BleProtocol.frames(payload, id: id)
    index = 0
    stage = .writing
    deadline("message write / application ACK")
    writeNext()
  }

  private func writeNext() {
    guard let peer = peer, let characteristic = dataCharacteristic else {
      fail("Missing write target"); return
    }
    log("frame_send id=\(id) index=\(index) count=\(frames.count) bytes=\(frames[index].count)")
    peer.writeValue(frames[index], for: characteristic, type: .withResponse)
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard stage != .stopped, central === manager else { return }
    log("bluetooth_state state=\(central.state.rawValue) authorization=\(CBManager.authorization.rawValue)")
    switch central.state {
    case .poweredOn:
      guard stage == .power else { return }
      stage = .scanning
      central.scanForPeripherals(withServices: [CBUUID(string: BleProtocol.service)],
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
      log("scan_started service=\(BleProtocol.service)")
      deadline("discovery")
    case .unknown, .resetting:
      if stage != .power { fail("Bluetooth state lost: \(central.state.rawValue)") }
    default: fail("Bluetooth unavailable: state=\(central.state.rawValue)")
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber) {
    guard stage == .scanning, central === manager else { return }
    log("device_discovered identifier=\(peripheral.identifier) rssi=\(RSSI)")
    central.stopScan()
    log("scan_stopped reason=peer discovered")
    peer = peripheral
    peripheral.delegate = self
    stage = .connecting
    deadline("connection")
    log("connection_started identifier=\(peripheral.identifier)")
    central.connect(peripheral, options: nil)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard central === manager, peripheral === peer, stage == .connecting else { return }
    log("connection_established role=central")
    stage = .services
    deadline("service discovery")
    peripheral.discoverServices([CBUUID(string: BleProtocol.service)])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
    error: Error?) {
    guard stage != .stopped, central === manager, peripheral === peer else { return }
    fail("connection_failed: \(String(describing: error))")
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?) {
    guard stage != .stopped, central === manager, peripheral === peer else { return }
    log("disconnect error=\(String(describing: error))")
    stop("peer disconnected")
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard peripheral === peer, stage == .services else { return }
    guard error == nil, let service = peripheral.services?.first(where: {
      $0.uuid == CBUUID(string: BleProtocol.service) && $0.isPrimary
    }) else { fail("service_discovery: \(String(describing: error)); expected primary service required"); return }
    log("service_discovered uuid=\(service.uuid)")
    stage = .characteristics
    // Keep the same deadline across service and characteristic discovery.
    peripheral.discoverCharacteristics([CBUUID(string: BleProtocol.data), CBUUID(string: BleProtocol.ack)],
      for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
    error: Error?) {
    guard peripheral === peer, stage == .characteristics,
      service.uuid == CBUUID(string: BleProtocol.service) else { return }
    guard error == nil,
      let data = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BleProtocol.data) }),
      let ack = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BleProtocol.ack) }),
      data.properties.contains(.write), ack.properties.contains(.read) else {
      fail("characteristic_discovery: \(String(describing: error)); DATA write and ACK read required"); return
    }
    dataCharacteristic = data
    ackCharacteristic = ack
    clearDeadline()
    stage = .ready
    log("characteristic_discovered data=\(data.uuid) ack=\(ack.uuid)")
    log("central_ready")
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
    error: Error?) {
    guard peripheral === peer, stage == .writing else { return }
    guard characteristic === dataCharacteristic, error == nil else {
      fail("write_error: \(String(describing: error))"); return
    }
    log("frame_write_confirmed id=\(id) index=\(index)")
    index += 1
    if index < frames.count { writeNext() } else {
      log("message_sent id=\(id) bytes=\(length) frames=\(frames.count)")
      stage = .ack
      guard let ack = ackCharacteristic else { fail("Missing ACK characteristic"); return }
      log("ack_read_started id=\(id)")
      peripheral.readValue(for: ack)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?) {
    guard peripheral === peer, stage == .ack else { return }
    let value = characteristic.value ?? Data()
    log("ack_receive bytes=\(value.map { String(format: "%02x", $0) }.joined())")
    guard characteristic === ackCharacteristic, error == nil,
      value == BleProtocol.acknowledgement(id: id, length: length) else {
      fail("ack_read_error or Application ACK mismatch: \(String(describing: error))"); return
    }
    clearDeadline()
    frames = []
    stage = .ready
    log("acknowledgement_received id=\(id) bytes=\(length)")
  }
}
