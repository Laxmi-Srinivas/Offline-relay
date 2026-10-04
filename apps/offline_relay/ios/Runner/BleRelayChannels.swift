import Flutter
import Foundation
import UIKit

/// Same method/event map contract as main's Android MainActivity.
final class BleRelayChannels: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var session: BleRelaySession?
  private var methods: FlutterMethodChannel!
  private var events: FlutterEventChannel!

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    methods = FlutterMethodChannel(name: "dev.offlinerelay/ble/methods", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "dev.offlinerelay/ble/events", binaryMessenger: messenger)
    events.setStreamHandler(self)
    methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    NotificationCenter.default.addObserver(self, selector: #selector(background),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  @objc private func background() { session?.stop("application left foreground"); session = nil }
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
      current().advertise(profile, result: result)
    case "startDiscovery": current().startDiscovery(result)
    case "stopDiscovery": if let session = session { session.stopDiscovery(result) } else { result(nil) }
    case "connect":
      guard let id = args["peerId"] as? String else { invalid("peerId"); return }
      current().connect(id, result: result)
    case "send":
      guard let id = args["connectionId"] as? String else { invalid("connectionId"); return }
      guard let bytes = args["message"] as? FlutterStandardTypedData else { invalid("message bytes"); return }
      current().send(id, bytes: bytes.data, result: result)
    case "close":
      guard let id = args["connectionId"] as? String else { invalid("connectionId"); return }
      if let session = session { session.close(id, result: result) } else { result(nil) }
    case "stopAdvertising": if let session = session { session.stopAdvertising(result) } else { result(nil) }
    case "dispose": session?.stop("transport disposed"); session = nil; result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
}
