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
