import Flutter
import Foundation

/// App-owned CoreBluetooth helper; independent of the Flutter channel listener.
/// This is not an iOS service or a promise of indefinite background execution.
final class BleHelperAvailability {
  private static let enabledKey = "offlinerelay.helper.enabled"
  private static let profileKey = "offlinerelay.helper.profile"
  private let defaults: UserDefaults
  private var state = BleHelperState()
  private let notifications = BleHelperNotifications()
  private var session: BleRelaySession?
  private var listener: (([String: Any]) -> Void)?
  private var generation = UUID()
  private var stopping = false

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  /// Called during app launch, before the Flutter engine/channel is required.
  func restoreAvailability() {
    notifications.clearOrphans()
    guard defaults.bool(forKey: Self.enabledKey), session == nil,
      let saved = defaults.dictionary(forKey: Self.profileKey),
      let profile = try? BleProfile.validate(saved) else { return }
    state.profile = profile
    start(profile) { _ in }
  }
  func attach(_ listener: @escaping ([String: Any]) -> Void) {
    self.listener = listener
    replay()
  }
  func detach() { listener = nil }
  func replay() {
    guard let listener = listener, state.enabled || session != nil || state.connection != nil else { return }
    // Do not turn an ordinary Offline User launch into helper mode.
    if state.profile != nil { listener(state.availabilityEvent) }
    if let connection = state.connection {
      listener(connection)
      if let bytes = state.request, let id = state.connectionID {
        listener(["event": "message", "connectionId": id, "message": FlutterStandardTypedData(bytes: bytes)])
      }
      if let accepted = state.accepted { listener(accepted) }
      if let id = state.connectionID {
        for bytes in state.drainUnreadMessages() {
          listener(["event": "message", "connectionId": id, "message": FlutterStandardTypedData(bytes: bytes)])
        }
      }
    }
  }
  func owns(_ id: String) -> Bool { state.connectionID == id }
  var hasSession: Bool { session != nil }

  func advertise(_ raw: [String: Any], result: @escaping FlutterResult) {
    do {
      let profile = try BleProfile.validate(raw)
      _ = try BleProfile.encode(profile)
      guard state.connectionID == nil else {
        result(FlutterError(code: "ble_error", message: "Close the current helper connection first", details: nil)); return
      }
      notifications.requestAuthorizationIfNeeded()
      notifications.clear()
      // Invalidate any old restart before stopping/replacing its manager.
      generation = UUID(); stopping = true
      session?.stop("helper profile restart"); session = nil
      stopping = false; state.profile = profile
      start(profile, result: result)
    } catch {
      result(FlutterError(code: "ble_error", message: error.localizedDescription, details: nil))
    }
  }
  private func start(_ profile: [String: Any], result: @escaping FlutterResult) {
    generation = UUID()
    let token = generation
    let next = BleRelaySession { [weak self] event in
      guard let self = self, self.generation == token else { return }
      self.onEvent(event)
    }
    session = next
    next.advertise(profile, restorationIdentifier: "dev.offlinerelay.helper.peripheral") { [weak self] value in
      guard let self = self, self.generation == token else { result(value); return }
      if value == nil {
        self.state.enabled = true
        self.defaults.set(profile, forKey: Self.profileKey)
        self.defaults.set(true, forKey: Self.enabledKey)
      } else {
        self.state.enabled = false
        self.defaults.set(false, forKey: Self.enabledKey)
      }
      self.listener?(self.state.availabilityEvent)
      result(value)
    }
  }
  func stopHelper(_ result: FlutterResult) {
    notifications.clear()
    stopping = true; state.enabled = false
    defaults.set(false, forKey: Self.enabledKey)
    session?.stop("helper availability disabled"); session = nil
    generation = UUID(); state.clearConnection()
    listener?(state.availabilityEvent); stopping = false; result(nil)
  }
  func stopAdvertising(_ result: FlutterResult) {
    // Shared controller calls this before accepting. Keep the established link
    // and enabled intent so it can return to advertising after close/reject.
    if let session = session { session.stopAdvertising(result) } else { result(nil) }
  }
  func close(_ id: String, result: FlutterResult) {
    if owns(id), let session = session { session.close(id, result: result) } else { result(nil) }
  }
  func send(_ id: String, bytes: Data, result: @escaping FlutterResult) {
    guard owns(id), let session = session else {
      result(FlutterError(code: "connection_missing", message: "Helper BLE connection is unavailable", details: nil)); return
    }
    session.send(id, bytes: bytes) { [weak self] value in
      if value == nil, let self = self, self.owns(id) {
        let requestID = self.state.requestID
        let event = self.state.sent(bytes)
        if requestID != nil && self.state.requestID == nil { self.notifications.clear() }
        if let event = event { self.listener?(event) }
      }
      result(value)
    }
  }
  private func onEvent(_ event: [String: Any]) {
    switch event["event"] as? String {
    case "incomingConnection":
      if state.connectionID != event["connectionId"] as? String { notifications.clear() }
      state.incoming(event)
    case "message":
      if let bytes = event["message"] as? FlutterStandardTypedData {
        if let request = state.receive(bytes.data, retainChat: listener == nil) {
          notifications.received(request, enabled: state.enabled)
        }
      }
    case "disconnected": notifications.clear()
    case "sessionEnded":
      notifications.clear()
      let shouldRestart = state.enabled && !stopping && state.connectionID != nil
      session = nil; state.clearConnection()
      if shouldRestart, let profile = state.profile {
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          guard let self = self, self.generation == token, self.state.enabled,
            !self.stopping, self.session == nil else { return }
          self.start(profile) { _ in }
        }
      } else if !stopping {
        state.enabled = false; defaults.set(false, forKey: Self.enabledKey)
        listener?(state.availabilityEvent)
      }
    default: break
    }
    listener?(event)
  }
}
