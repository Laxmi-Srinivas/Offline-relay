import Foundation

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
  if !condition() { fatalError(label) }
}
// Uses actual product helpers. No CoreBluetooth or radio delivery claim.
check(BleFraming.service == "41729610-0934-4e0e-b749-170442310001", "service")
check(BleFraming.frames(Data("Hello".utf8), id: 1) == [Data([1, 1, 0, 1, 72, 101, 108, 108, 111])], "validated Hello bytes")
for length in 1...256 {
  let message = Data((0..<length).map { UInt8($0) })
  var receiver = BleMessageReceiver()
  let frames = BleFraming.frames(message, id: 255)
  for (index, frame) in frames.enumerated() {
    check(frame.count <= 20, "frame limit")
    let result = try receiver.receive(frame)
    if index == frames.count - 1 {
      check(result == message, "arbitrary payload round trip")
      check(receiver.acknowledgement == Data([1, 255, UInt8(length >> 8), UInt8(length & 255)]), "ACK length")
    } else { check(result == nil && receiver.acknowledgement == nil, "withhold ACK") }
  }
}
for type in ["connection_request", "connection_accept", "connection_reject", "chat"] {
  let object: [String: Any] = ["version": 1, "id": String(repeating: "a", count: 32), "type": type, "body": ["text": "こんにちは"]]
  let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  var receiver = BleMessageReceiver()
  var received: Data?
  for frame in BleFraming.frames(bytes, id: 1) { received = try receiver.receive(frame) }
  check(received == bytes, "opaque envelope \(type)")
}
let frames = BleFraming.frames(Data((0...255).map { UInt8($0) }), id: 2)
func rejects(_ sequence: [Data]) {
  var receiver = BleMessageReceiver()
  do {
    for frame in sequence { _ = try receiver.receive(frame) }
    fatalError("Malformed sequence accepted")
  } catch {
    check(!receiver.isReceiving && receiver.acknowledgement == nil && receiver.payload.isEmpty, "failure reset")
  }
}
for bad in [Data(), Data([1, 1, 0, 1]), Data(repeating: 1, count: 21), Data([2, 1, 0, 1, 0]), Data([1, 0, 0, 1, 0]), Data([1, 1, 0, 17, 0]), Data([1, 1, 0, 2, 0])] { rejects([bad]) }
rejects([frames[1]]); rejects([frames[0], frames[0]]); rejects([frames[0], frames[2]])
var reverse = BleMessageReceiver(), forward = BleMessageReceiver()
_ = try forward.receive(frames[0])
let reverseMessage = try reverse.receive(BleFraming.frames(Data("reverse".utf8), id: 2)[0])
check(reverseMessage == Data("reverse".utf8) && forward.isReceiving, "independent duplex receive state")
forward.reset(); check(!forward.isReceiving && forward.acknowledgement == nil, "cleanup")
check(BleFraming.nextID(255) == 1, "ID rollover")
let profile: [String: Any] = ["id": "profile-id", "label": "Helper long name", "metadata": ["role": "internet_helper", "custom": "value"]]
let decoded = try BleProfile.decode(BleProfile.encode(profile))
check(decoded["id"] as? String == "profile-id" && decoded["label"] as? String == "Helper long name", "full profile")
check((decoded["metadata"] as? [String: String])?["custom"] == "value", "full metadata")
let name = BleProfile.advertisedName(profile)
check(name.utf8.count <= 10 && name.hasPrefix("ORH:"), "advertisement budget")
let discovered = BleProfile.discoveryPeer(id: "device-id", name: name)
check((discovered?["metadata"] as? [String: String])?["role"] == "internet_helper", "Dart helper filter")
check(BleProfile.discoveryPeer(id: "x", name: "Other device") == nil, "ignore unrelated profiles")
let unicode = BleProfile.advertisedName(["label": "👩🏽‍💻名名前", "metadata": ["role": "internet_helper"]])
check(unicode.utf8.count <= 10 && unicode.hasPrefix("ORH:"), "UTF-8 safe trimming")
print("PASS: product arbitrary bytes/envelopes, validated framing, ACKs, invalid order, duplex state, profile discovery/encoding")

// Actual native replay-state logic; radio restoration still requires devices.
var helperState = BleHelperState()
check(helperState.availabilityEvent["enabled"] as? Bool == false, "helper disabled initially")
helperState.profile = profile
helperState.enabled = true
check(helperState.availabilityEvent["displayName"] as? String == "Helper long name", "helper name replay")
helperState.incoming(["event": "incomingConnection", "connectionId": "helper-link", "peer": ["id": "nearby"]])
let request = try JSONSerialization.data(withJSONObject: ["version": 1, "id": "request-1", "type": "connection_request", "body": ["name": "Avery"]])
helperState.receive(request, retainChat: false)
check(helperState.request == request && helperState.peerName == "Avery", "pending request replay")
let reject = try JSONSerialization.data(withJSONObject: ["version": 1, "id": "reject-1", "type": "connection_reject", "body": ["requestId": "request-1"]])
check(helperState.sent(reject) == nil && helperState.enabled && helperState.request == nil, "reject preserves enabled intent")
helperState.clearConnection()
check(helperState.enabled && helperState.connectionID == nil, "close preserves availability for restart")
helperState.incoming(["event": "incomingConnection", "connectionId": "helper-link-2", "peer": ["id": "nearby"]])
helperState.receive(request, retainChat: false)
let wrongAccept = try JSONSerialization.data(withJSONObject: ["version": 1, "type": "connection_accept", "body": ["requestId": "wrong"]])
check(helperState.sent(wrongAccept) == nil && helperState.request != nil, "reject unrelated acceptance")
let accept = try JSONSerialization.data(withJSONObject: ["version": 1, "type": "connection_accept", "body": ["requestId": "request-1"]])
let accepted = helperState.sent(accept)
check(accepted?["connectionId"] as? String == "helper-link-2" && accepted?["requestId"] as? String == "request-1", "accepted identifiers")
check(accepted?["peerName"] as? String == "Avery" && helperState.request == nil && helperState.accepted != nil, "accepted snapshot replay")
let chat = try JSONSerialization.data(withJSONObject: ["version": 1, "type": "chat", "body": ["text": "Background message"]])
for _ in 0..<40 { helperState.receive(chat, retainChat: true) }
check(helperState.unreadMessages.count == 32, "bounded detached chat buffer")
check(helperState.drainUnreadMessages().count == 32 && helperState.unreadMessages.isEmpty, "drain replay once")
helperState.enabled = false; helperState.clearConnection()
check(helperState.availabilityEvent["enabled"] as? Bool == false && helperState.accepted == nil, "disable resets replay")
print("PASS: native helper availability/request/acceptance replay, reject/close retention, bounded detached messages, disable")

// Notification decisions use the same request descriptor as native replay.
var alerts = BleHelperNotificationState()
helperState.enabled = true
helperState.incoming(["connectionId": "notification-link"])
let validRequest = helperState.receive(request, retainChat: false)!
check(!alerts.receive(validRequest, enabled: false), "disabled helper never notifies")
check(alerts.receive(validRequest, enabled: true), "new request notification")
let alertToken = alerts.token
check(!alerts.receive(validRequest, enabled: true) && alerts.token == alertToken, "request ID deduplicated")
check(alerts.shouldSchedule(token: alertToken, authorized: true, foreground: false), "authorized background schedules")
check(!alerts.shouldSchedule(token: alertToken, authorized: true, foreground: true), "foreground suppresses duplicate UI")
check(!alerts.shouldSchedule(token: alertToken, authorized: false, foreground: false) && helperState.enabled, "permission denial does not disable BLE")
for resolution in [accept, reject] {
  helperState.receive(request, retainChat: false)
  let previous = helperState.requestID
  _ = helperState.sent(resolution)
  if previous != nil && helperState.requestID == nil { alerts.clear() }
  check(alerts.active == nil && !alerts.shouldSchedule(token: alertToken, authorized: true, foreground: false), "accept/reject cancels async notification")
}
for reason in ["disconnect", "session end", "disable"] {
  let next = BleHelperRequest(id: reason, peerName: "Next peer")
  check(alerts.receive(next, enabled: true), "another request can notify")
  let pending = alerts.token
  alerts.clear()
  check(alerts.active == nil && !alerts.shouldSchedule(token: pending, authorized: true, foreground: false), "cleanup invalidates \(reason)")
}
for invalid in [Data("bad JSON".utf8), Data("{\"version\":true,\"id\":\"x\",\"type\":\"connection_request\",\"body\":{}}".utf8)] {
  check(helperState.receive(invalid, retainChat: false) == nil, "malformed request cannot notify")
}
for object: [String: Any] in [
  ["version": 2, "id": "x", "type": "connection_request", "body": [:]],
  ["version": 1, "id": "", "type": "connection_request", "body": [:]],
  ["version": 1, "id": "x", "type": "connection_request", "body": "bad"],
  ["version": 1, "id": "x", "type": "connection_request", "body": [:], "extra": true],
  ["version": 1, "id": "x", "type": "chat", "body": [:]],
  ["version": 1, "id": "x", "type": "connection_request", "body": ["name": String(repeating: "x", count: 256)]]
] {
  let invalidBytes = try JSONSerialization.data(withJSONObject: object)
  check(helperState.receive(invalidBytes, retainChat: false) == nil, "invalid/non-request envelope cannot notify")
}
print("PASS: notification deduplication, authorization/foreground policy, resolution/cleanup, stale callbacks, malformed requests")

// Registry isolates simultaneous central links without involving helper services.
final class TestCentralLink {
  var receiver = BleMessageReceiver()
  var queued = [Data]()
}
let links = BleCentralConnections<TestCentralLink>()
let linkB = TestCentralLink(), linkC = TestCentralLink(), linkPending = TestCentralLink()
let tokenB = UUID(), tokenC = UUID(), tokenPending = UUID()
check(links.insert(peerID: "B", session: linkB, token: tokenB), "register B")
check(links.insert(peerID: "C", session: linkC, token: tokenC), "register C concurrently")
check(!links.insert(peerID: "B", session: linkC, token: UUID()), "duplicate peer rejected")
links.bind(peerID: "B", token: tokenB, connectionID: "connection-B")
links.bind(peerID: "C", token: tokenC, connectionID: "connection-C")
check(links.session(connectionID: "connection-B") === linkB && links.session(connectionID: "connection-C") === linkC, "route exact connection IDs")
_ = try linkB.receiver.receive(frames[0]); linkB.queued.append(frames[1])
check(!linkC.receiver.isReceiving && linkC.queued.isEmpty, "per-link frame and queue state isolated")
check(links.remove(peerID: "B", token: UUID()) == nil, "stale removal ignored")
check(links.remove(peerID: "B", token: tokenB) === linkB, "remove B only")
check(links.session(connectionID: "connection-C") === linkC, "C survives B rejection/disconnect")
check(links.insert(peerID: "D", session: linkPending, token: tokenPending), "connecting D")
check(links.takePending().first === linkPending, "cancel unresolved connecting links")
check(links.session(connectionID: "connection-C") === linkC, "pending cancellation preserves winner")
links.bind(peerID: "D", token: tokenPending, connectionID: "late-D")
check(links.session(connectionID: "late-D") == nil, "late readiness cannot restore removed loser")
check(links.takeAll().count == 1 && links.entries.isEmpty, "dispose/background cleans registry")
print("PASS: concurrent native central registry, independent frame/queue state, connection routing, stale callback protection, pending cancellation")
