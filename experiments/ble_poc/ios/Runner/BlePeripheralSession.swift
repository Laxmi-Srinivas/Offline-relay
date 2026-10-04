import CoreBluetooth
import Foundation

/// Foreground experiment only. CoreBluetooth has no generic peripheral-role
/// link disconnect callback; partial state/peer ownership expire after 15s.
final class BlePeripheralSession: NSObject, CBPeripheralManagerDelegate {
  private enum Stage { case power, registering, advertising, ready, stopped }
  private var stage: Stage = .power
  private var manager: CBPeripheralManager!
  private var service: CBMutableService?
  private var dataCharacteristic: CBMutableCharacteristic?
  private var ackCharacteristic: CBMutableCharacteristic?
  private var receiver = BleReassembler()
  private var centralID: UUID?
  private var timer: DispatchWorkItem?
  private var timerGeneration = 0
  private let log: (String) -> Void

  init(log: @escaping (String) -> Void) {
    self.log = log
    super.init()
    manager = CBPeripheralManager(delegate: self, queue: .main)
    deadline("Bluetooth readiness", fatal: true)
  }

  private func clearDeadline() {
    timerGeneration += 1
    timer?.cancel()
    timer = nil
  }

  private func deadline(_ name: String, fatal: Bool) {
    clearDeadline()
    let generation = timerGeneration
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.stage != .stopped,
        generation == self.timerGeneration else { return }
      self.log("timeout stage=\(name)")
      if fatal { self.stop("timeout: \(name)") }
      else { self.resetInteraction("\(name) expired; link disconnect is not observable") }
    }
    timer = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
  }

  private func resetInteraction(_ reason: String) {
    clearDeadline()
    receiver.reset()
    centralID = nil
    log("peripheral_state_reset reason=\(reason)")
  }

  func stop(_ reason: String) {
    guard stage != .stopped else { return }
    stage = .stopped
    resetInteraction(reason)
    if manager.isAdvertising { manager.stopAdvertising(); log("advertising_stopped reason=\(reason)") }
    manager.removeAllServices()
    manager.delegate = nil
    service = nil
    dataCharacteristic = nil
    ackCharacteristic = nil
    log("cleanup role=peripheral reason=\(reason)")
  }

  private func fail(_ reason: String) { log("error: \(reason)"); stop(reason) }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    guard peripheral === manager, stage != .stopped else { return }
    log("bluetooth_state role=peripheral state=\(peripheral.state.rawValue) authorization=\(CBManager.authorization.rawValue)")
    switch peripheral.state {
    case .poweredOn:
      guard stage == .power else { return }
      let data = CBMutableCharacteristic(type: CBUUID(string: BleProtocol.data),
        properties: [.write], value: nil, permissions: [.writeable])
      let ack = CBMutableCharacteristic(type: CBUUID(string: BleProtocol.ack),
        properties: [.read], value: nil, permissions: [.readable])
      let service = CBMutableService(type: CBUUID(string: BleProtocol.service), primary: true)
      service.characteristics = [data, ack]
      self.service = service
      dataCharacteristic = data
      ackCharacteristic = ack
      stage = .registering
      log("service_created uuid=\(service.uuid) data=\(data.uuid) ack=\(ack.uuid)")
      deadline("service registration", fatal: true)
      peripheral.add(service)
    case .unknown, .resetting:
      if stage != .power { fail("Bluetooth state lost: \(peripheral.state.rawValue)") }
    default: fail("Bluetooth unavailable: state=\(peripheral.state.rawValue)")
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    guard peripheral === manager, stage == .registering, service === self.service else { return }
    guard error == nil else { fail("service_registration: \(String(describing: error))"); return }
    log("service_registered uuid=\(service.uuid)")
    stage = .advertising
    deadline("advertising start", fatal: true)
    peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BleProtocol.service)]])
    log("advertising_start_requested service=\(BleProtocol.service)")
  }

  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    guard peripheral === manager, stage == .advertising else { return }
    guard error == nil else { fail("advertise_error: \(String(describing: error))"); return }
    clearDeadline()
    stage = .ready
    log("advertising_started service=\(BleProtocol.service)")
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    guard peripheral === manager, stage == .ready, let first = requests.first else { return }
    // Apple requires one response per callback and atomic handling of a batch.
    var candidate = receiver
    var candidateID = centralID
    var diagnostics: [String] = []
    let wasReceiving = receiver.isReceiving
    do {
      for request in requests {
        let id = request.central.identifier
        log("central_interaction operation=write identifier=\(id)")
        guard candidateID == nil || candidateID == id else {
          peripheral.respond(to: first, withResult: .unlikelyError)
          log("error: peer_rejected one logical peer only")
          return
        }
        guard request.characteristic === dataCharacteristic, request.offset == 0,
          let value = request.value else { throw BleReassembler.Failure.malformed }
        candidateID = id
        log("data_write bytes=\(value.count) offset=\(request.offset)")
        let complete = try candidate.receive(value)
        diagnostics.append("frame_assembled id=\(value[1]) index=\(value[2]) count=\(value[3])")
        if let complete = complete, let ack = candidate.acknowledgement {
          diagnostics.append("message_received id=\(value[1]) bytes=\(complete.count) exact_payload_verified=true" +
            (complete == BleProtocol.hello ? " text=Hello" : " vector=00..ff"))
          diagnostics.append("ack_created bytes=\(ack.map { String(format: "%02x", $0) }.joined())")
        }
      }
      receiver = candidate
      centralID = candidateID
      diagnostics.forEach(log)
      if receiver.isReceiving {
        if !wasReceiving { deadline("reassembly", fatal: false) }
      } else { deadline("idle peer / ACK lease", fatal: false) }
      peripheral.respond(to: first, withResult: .success)
    } catch {
      resetInteraction("invalid DATA batch")
      log("error: receive_error \(error)")
      peripheral.respond(to: first, withResult: .unlikelyError)
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
    guard peripheral === manager, stage == .ready else { return }
    log("central_interaction operation=read identifier=\(request.central.identifier)")
    guard centralID == request.central.identifier, request.characteristic === ackCharacteristic,
      request.offset == 0, let ack = receiver.acknowledgement else {
      log("error: ACK unavailable, wrong peer/characteristic, or nonzero offset")
      peripheral.respond(to: request, withResult: .unlikelyError)
      return
    }
    request.value = ack
    peripheral.respond(to: request, withResult: .success)
    log("ack_read_response id=\(ack[1]) bytes=\(ack.count)")
    deadline("idle peer / ACK lease", fatal: false)
  }
}
