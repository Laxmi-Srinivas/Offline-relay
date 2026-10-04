import UIKit
import UserNotifications

/// Main-queue-owned local alerts only. Never controls CoreBluetooth availability.
final class BleHelperNotifications {
  static let prefix = "offlinerelay.request."
  private let center = UNUserNotificationCenter.current()
  private var state = BleHelperNotificationState()

  func requestAuthorizationIfNeeded() {
    center.getNotificationSettings { [weak self] settings in
      guard settings.authorizationStatus == .notDetermined else { return }
      self?.center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        NSLog("[BLE notifications] authorization granted=%@ error=%@", String(granted), error?.localizedDescription ?? "none")
      }
    }
  }

  func received(_ request: BleHelperRequest, enabled: Bool) {
    let previous = state.active?.id
    guard state.receive(request, enabled: enabled) else { return }
    if let previous = previous { remove(previous) }
    let token = state.token
    center.getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        guard let self = self else { return }
        let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        guard self.state.shouldSchedule(token: token, authorized: authorized,
          foreground: UIApplication.shared.applicationState == .active) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Someone nearby needs help"
        content.body = "\(request.peerName) sent you a connection request"
        content.sound = .default
        let notification = UNNotificationRequest(identifier: Self.prefix + request.id, content: content, trigger: nil)
        self.center.add(notification) { [weak self] error in
          DispatchQueue.main.async {
            guard let self = self else { return }
            // A clear can race with the asynchronous add. Remove late completions.
            if self.state.token != token { self.remove(request.id) }
            if let error = error { NSLog("[BLE notifications] scheduling error: %@", error.localizedDescription) }
          }
        }
      }
    }
  }

  func clear() {
    if let id = state.active?.id { remove(id) }
    state.clear()
  }
  private func remove(_ id: String) {
    let identifiers = [Self.prefix + id]
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }
  /// Process-local requests cannot be restored; remove orphaned alerts on launch.
  func clearOrphans() {
    center.getPendingNotificationRequests { [weak self] requests in
      DispatchQueue.main.async {
        guard let self = self else { return }
        let active = self.state.active.map { Self.prefix + $0.id }
        self.center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(Self.prefix) && $0 != active })
      }
    }
    center.getDeliveredNotifications { [weak self] notifications in
      DispatchQueue.main.async {
        guard let self = self else { return }
        let active = self.state.active.map { Self.prefix + $0.id }
        self.center.removeDeliveredNotifications(withIdentifiers: notifications.map { $0.request.identifier }.filter { $0.hasPrefix(Self.prefix) && $0 != active })
      }
    }
  }
}
