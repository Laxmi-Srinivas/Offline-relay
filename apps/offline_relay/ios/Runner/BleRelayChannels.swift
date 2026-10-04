import Flutter
import Foundation
import UIKit

/// Phase 1 central-only implementation of the existing Android channel contract.
/// Adapted from ios-mvp 4cf4865; no helper service or old Dart controller is copied.
final class BleRelayChannels: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var session: BleRelaySession?
  private var generation = UUID()
  private var methods: FlutterMethodChannel!
  private var events: FlutterEventChannel!

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    methods = FlutterMethodChannel(name: "dev.offlinerelay/ble/methods", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "dev.offlinerelay/ble/events", binaryMessenger: messenger)
    events.setStreamHandler(self)
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "session_unavailable", message: "Open onya again.", details: nil)); return
      }
      self.handle(call, result: result)
    }
    NotificationCenter.default.addObserver(self, selector: #selector(background),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  @objc private func background() { stop("application left foreground") }
  private func stop(_ reason: String) {
    session?.stop(reason); session = nil; generation = UUID()
  }
  private func current() -> BleRelaySession {
    if let session = session { return session }
    let token = UUID(); generation = token
    let next = BleRelaySession { [weak self] event in
      guard let self = self, self.generation == token else { return }
      if event["event"] as? String == "sessionEnded" { self.session = nil }
      self.sink?(event)
    }
    session = next
    return next
  }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    func invalid(_ field: String) {
      result(FlutterError(code: "ble_error", message: "Missing \(field)", details: nil))
    }
    switch call.method {
    case "startDiscovery": current().startDiscovery(result)
    case "stopDiscovery":
      if let session = session { session.stopDiscovery(result) } else { result(nil) }
    case "connect":
      guard let id = args["peerId"] as? String else { invalid("peerId"); return }
      guard let session = session else {
        result(FlutterError(code: "ble_error", message: "Search for a nearby helper first.", details: nil)); return
      }
      session.connect(id, result: result)
    case "send":
      guard let id = args["connectionId"] as? String else { invalid("connectionId"); return }
      guard let bytes = args["message"] as? FlutterStandardTypedData else { invalid("message bytes"); return }
      guard let session = session else {
        result(FlutterError(code: "connection_missing", message: "Connection is unavailable.", details: nil)); return
      }
      session.send(id, bytes: bytes.data, result: result)
    case "close":
      guard let id = args["connectionId"] as? String else { invalid("connectionId"); return }
      if let session = session { session.close(id, result: result) } else { result(nil) }
    case "advertise":
      result(FlutterError(code: "ios_helper_unavailable",
        message: "Help Others on iPhone is not included in Phase 1. Connect to an Android helper.", details: nil))
    case "stopAdvertising", "stopHelper": result(nil)
    case "dispose": stop("transport disposed"); result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil; stop("transport listener detached")
    return nil
  }
}
