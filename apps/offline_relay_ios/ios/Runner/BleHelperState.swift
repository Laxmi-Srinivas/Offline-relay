import Foundation

/// Native replay state, independent of Flutter and radio lifetime. Chat history
/// and connection IDs are never persisted across process death.
struct BleHelperState {
  var enabled = false
  var profile: [String: Any]?
  private(set) var connection: [String: Any]?
  private(set) var request: Data?
  private(set) var requestID: String?
  private(set) var peerName: String?
  private(set) var accepted: [String: Any]?
  private(set) var unreadMessages: [Data] = []

  var connectionID: String? { connection?["connectionId"] as? String }
  var availabilityEvent: [String: Any] {
    var event: [String: Any] = ["event": "helperState", "enabled": enabled]
    if let name = profile?["label"] as? String { event["displayName"] = name }
    return event
  }
  mutating func incoming(_ event: [String: Any]) {
    if connectionID != event["connectionId"] as? String { clearConnection() }
    connection = event
  }
  @discardableResult
  mutating func receive(_ bytes: Data, retainChat: Bool) -> BleHelperRequest? {
    guard let envelope = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
      envelope["version"] as? Int == 1 else { return nil }
    if envelope["type"] as? String == "connection_request",
      let id = envelope["id"] as? String, !id.isEmpty,
      bytes.count <= 256, envelope.count == 4,
      let version = envelope["version"] as? NSNumber, String(cString: version.objCType) != "c",
      let body = envelope["body"] as? [String: Any] {
      request = bytes; requestID = id
      peerName = body["name"] as? String ?? "Nearby user"
      accepted = nil
      return BleHelperRequest(id: id, peerName: peerName ?? "Nearby user")
    } else if retainChat, envelope["type"] as? String == "chat" {
      // Retain recent undelivered messages only; no unbounded background queue.
      if unreadMessages.count == 32 { unreadMessages.removeFirst() }
      unreadMessages.append(bytes)
    }
    return nil
  }
  mutating func sent(_ bytes: Data) -> [String: Any]? {
    guard let envelope = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
      envelope["version"] as? Int == 1,
      let body = envelope["body"] as? [String: Any],
      let id = body["requestId"] as? String, id == requestID,
      let connectionID = connectionID else { return nil }
    let type = envelope["type"] as? String
    guard type == "connection_accept" || type == "connection_reject" else { return nil }
    let name = peerName ?? "Nearby user"
    request = nil; requestID = nil
    if type == "connection_accept" {
      accepted = ["event": "helperAccepted", "connectionId": connectionID,
        "requestId": id, "peerName": name]
      return accepted
    }
    accepted = nil
    return nil
  }
  mutating func clearConnection() {
    connection = nil; request = nil; requestID = nil; peerName = nil
    accepted = nil; unreadMessages = []
  }
  mutating func drainUnreadMessages() -> [Data] {
    let messages = unreadMessages; unreadMessages = []; return messages
  }
}

struct BleHelperRequest {
  let id: String
  let peerName: String
}

/// Pure scheduling policy. Permission and foreground status never mutate BLE state.
struct BleHelperNotificationState {
  private(set) var active: BleHelperRequest?
  private(set) var token = UUID()
  private var seen: [String] = []

  mutating func receive(_ request: BleHelperRequest, enabled: Bool) -> Bool {
    guard enabled, !seen.contains(request.id) else { return false }
    seen.append(request.id)
    if seen.count > 256 { seen.removeFirst() }
    active = request; token = UUID()
    return true
  }
  func shouldSchedule(token: UUID, authorized: Bool, foreground: Bool) -> Bool {
    active != nil && self.token == token && authorized && !foreground
  }
  mutating func clear() {
    active = nil; token = UUID()
  }
}
