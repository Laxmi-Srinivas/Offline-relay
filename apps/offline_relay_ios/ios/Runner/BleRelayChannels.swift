import Flutter
import Foundation
import UIKit

/// Same method/event map contract as main's Android MainActivity.
final class BleRelayChannels: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var session: BleRelaySession? // Discovery/profile probes only.
  private let connections = BleCentralConnections<BleRelaySession>()
  private var methods: FlutterMethodChannel!
  private var events: FlutterEventChannel!
  private let helper: BleHelperAvailability

  init(messenger: FlutterBinaryMessenger, helper: BleHelperAvailability) {
    self.helper = helper
    super.init()
    methods = FlutterMethodChannel(name: "dev.offlinerelay/ble/methods", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "dev.offlinerelay/ble/events", binaryMessenger: messenger)
    events.setStreamHandler(self)
    methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    NotificationCenter.default.addObserver(self, selector: #selector(background),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(foreground),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  @objc private func background() { stopCentral("application left foreground") }
  private func stopCentral(_ reason: String) {
    session?.stop(reason); session = nil
    for connection in Array(connections.entries.values) { connection.session.stop(reason) }
    _ = connections.takeAll()
  }
  private func connect(_ id: String, result: @escaping FlutterResult) {
    guard let peer = session?.discoveredPeer(id) else {
      result(FlutterError(code: "ble_error", message: "Nearby peer expired; start discovery first", details: nil)); return
    }
    let token = UUID()
    let next = BleRelaySession { [weak self] event in
      guard let self = self, self.connections.contains(peerID: id, token: token) else { return }
      var scoped = event
      if let connectionID = self.connections.entries[id]?.connectionID { scoped["connectionId"] = connectionID }
      // An individual link ending must not stop unrelated discovery/requests.
      if event["event"] as? String == "sessionEnded" {
        self.connections.remove(peerID: id, token: token)
      } else if event["event"] as? String != "error" || scoped["connectionId"] != nil {
        self.sink?(scoped)
      }
    }
    guard connections.insert(peerID: id, session: next, token: token) else {
      result(FlutterError(code: "ble_error", message: "A request to this helper is already pending", details: nil)); return
    }
    next.connectPeer(id, peer: peer) { [weak self, weak next] value in
      guard let self = self, self.connections.contains(peerID: id, token: token) else {
        next?.stop("cancelled pending connection")
        result(FlutterError(code: "ble_error", message: "Connection cancelled", details: nil)); return
      }
      if let map = value as? [String: Any], let connectionID = map["connectionId"] as? String {
        self.connections.bind(peerID: id, token: token, connectionID: connectionID)
      } else { self.connections.remove(peerID: id, token: token) }
      result(value)
    }
  }
  @objc private func foreground() { helper.replay() }
  private func current() -> BleRelaySession {
    if let session = session { return session }
    let next = BleRelaySession { [weak self] event in
      self?.sink?(event)
      if event["event"] as? String == "sessionEnded" { self?.session = nil }
    }
    session = next
    return next
  }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    func invalid(_ field: String) { result(FlutterError(code: "ble_error", message: "Missing \(field)", details: nil)) }
    switch call.method {
    case "advertise":
      guard let profile = args["profile"] as? [String: Any] else { invalid("profile"); return }
      helper.advertise(profile, result: result)
    case "startDiscovery": current().startDiscovery(result)
    case "stopDiscovery":
      // Discovery cancellation marks winner selection / leaving Nearby. Bound
      // connect futures that have not produced a Dart connection yet are cancelled.
      for pending in connections.takePending() { pending.stop("outgoing request cancelled") }
      if let session = session { session.stopDiscovery(result) } else { result(nil) }
    case "connect":
      guard let id = args["peerId"] as? String else { invalid("peerId"); return }
      connect(id, result: result)
    case "send":
      guard let id = args["connectionId"] as? String else { invalid("connectionId"); return }
      guard let bytes = args["message"] as? FlutterStandardTypedData else { invalid("message bytes"); return }
      if helper.owns(id) { helper.send(id, bytes: bytes.data, result: result) }
      else if let connection = connections.session(connectionID: id) { connection.send(id, bytes: bytes.data, result: result) }
      else { result(FlutterError(code: "connection_missing", message: "Connection is unavailable", details: nil)) }
    case "close":
      guard let id = args["connectionId"] as? String else { invalid("connectionId"); return }
      if helper.owns(id) { helper.close(id, result: result) }
      else if let connection = connections.session(connectionID: id) { connection.close(id, result: result) } else { result(nil) }
    case "stopAdvertising": helper.stopAdvertising(result)
    case "stopHelper": helper.stopHelper(result)
    case "dispose": stopCentral("transport disposed"); result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    helper.attach { [weak self] event in self?.sink?(event) }
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { helper.detach(); sink = nil; return nil }
}
