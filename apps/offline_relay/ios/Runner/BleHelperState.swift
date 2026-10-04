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
  mutating func receive(_ bytes: Data, retainChat: Bool) {
    guard let envelope = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
      envelope["version"] as? Int == 1 else { return }
    if envelope["type"] as? String == "connection_request",
      let id = envelope["id"] as? String, !id.isEmpty {
      request = bytes; requestID = id
      peerName = (envelope["body"] as? [String: Any])?["name"] as? String ?? "Nearby user"
      accepted = nil
    } else if retainChat, envelope["type"] as? String == "chat" {
      // Retain recent undelivered messages only; no unbounded background queue.
      if unreadMessages.count == 32 { unreadMessages.removeFirst() }
      unreadMessages.append(bytes)
    }
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
