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
for type in ["connection_request", "connection_accept", "connection_reject", "connection_cancel", "key_exchange", "secure_message", "end_chat"] {
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

// Android scan-response fixtures: existing version/role/length/name bytes.
func profile(_ bytes: [UInt8]) -> [String: Any]? {
  BleAndroidProfile.peer(id: "corebluetooth-device-id", serviceData: Data(bytes))
}
let helper = profile([1, 2, 6] + Array("Helper".utf8))!
check(helper["id"] as? String == "corebluetooth-device-id", "opaque discovery handle")
check(helper["label"] as? String == "Helper", "Android compact label")
check((helper["metadata"] as? [String: String])?["role"] == "internet_helper", "existing Flutter helper filter")
let requester = profile([1, 1, 4] + Array("User".utf8))!
check((requester["metadata"] as? [String: String])?["role"] == "offline_user", "requester not mislabeled helper")
let unicodeLabel = "名🌍"
let unicode = profile([1, 2, UInt8(unicodeLabel.utf8.count)] + Array(unicodeLabel.utf8))!
check(unicode["label"] as? String == unicodeLabel, "UTF-8 byte length, not character count")
check(profile([1, 2, 10] + Array("0123456789".utf8)) != nil, "Android ten-byte label maximum")
for invalid: [UInt8] in [[], [1], [1, 2, 0], [2, 2, 1, 65], [1, 0, 1, 65],
  [1, 3, 1, 65], [1, 2, 2, 65], [1, 2, 1, 65, 66], [1, 2, 1, 255],
  [1, 2, 11] + Array("01234567890".utf8)] {
  check(profile(invalid) == nil, "malformed/unknown Android profile ignored")
}
print("PASS: Android profile fixtures, UTF-8, roles, arbitrary Relay bytes, framing, ACKs and malformed frames")
