import Flutter
import Foundation
import UIKit

final class BlePocChannels: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var session: BleCentralSession?
  private var commands: FlutterMethodChannel!
  private var events: FlutterEventChannel!

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    events = FlutterEventChannel(name: "offlinerelay.poc/events", binaryMessenger: messenger)
    events.setStreamHandler(self)
    commands = FlutterMethodChannel(name: "offlinerelay.poc/commands", binaryMessenger: messenger)
    commands.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      self.command(call.method, result: result)
    }
    NotificationCenter.default.addObserver(self, selector: #selector(background),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  private func log(_ message: String) {
    let line = "\(Int64(Date().timeIntervalSince1970 * 1000)) \(message)"
    NSLog("OfflineRelayBLE %@", line)
    sink?(line)
  }

  @objc private func background() {
    session?.stop("application left foreground")
    session = nil
  }

  private func command(_ method: String, result: FlutterResult) {
    do {
      switch method {
      case "discover":
        session?.stop("role restart")
        session = BleCentralSession { [weak self] message in self?.log(message) }
      case "stop":
        session?.stop("user stop")
        session = nil
      case "hello", "larger":
        guard let session = session else {
          throw NSError(domain: "OfflineRelayBLE", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Start central first"])
        }
        try session.send(method == "hello" ? BleProtocol.hello : BleProtocol.larger)
      case "advertise":
        log("error: unsupported_role: iOS central only")
        result(FlutterError(code: "unsupported_role", message: "iOS POC implements central only", details: nil))
        return
      default: result(FlutterMethodNotImplemented); return
      }
      result(nil)
    } catch {
      log("error: \(error.localizedDescription)")
      session?.stop("command failed")
      session = nil
      result(FlutterError(code: "ble_error", message: error.localizedDescription, details: nil))
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
