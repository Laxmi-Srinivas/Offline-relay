import Foundation

// Runs the actual production framing helper on macOS; no BLE evidence.
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
  if !condition() { fatalError(label) }
}
check(BleProtocol.frames(BleProtocol.hello, id: 1) == [Data([1, 1, 0, 1, 0x48, 0x65, 0x6c, 0x6c, 0x6f])], "Hello wire bytes")
check(BleProtocol.acknowledgement(id: 1, length: 5) == Data([1, 1, 0, 5]), "Hello ACK")
let frames = BleProtocol.frames(BleProtocol.larger, id: 2)
check(frames.count == 16, "256-byte frame count")
for (index, frame) in frames.enumerated() {
  check(frame.count == 20, "20-byte frame")
  check(Array(frame.prefix(4)) == [1, 2, UInt8(index), 16], "frame header")
  check(Array(frame.dropFirst(4)) == (index * 16..<index * 16 + 16).map { UInt8($0) }, "exact payload chunk")
}
check(Data(frames.flatMap { Array($0.dropFirst(4)) }) == Data((0...255).map { UInt8($0) }), "reassembly")
check(BleProtocol.acknowledgement(id: 2, length: 256) == Data([1, 2, 1, 0]), "big-endian length")
check(BleProtocol.acknowledgement(id: 2, length: 256) != Data([1, 1, 1, 0]), "wrong ID differs")
check(BleProtocol.acknowledgement(id: 2, length: 256) != Data([1, 2, 0, 1]), "wrong length differs")
check(BleProtocol.nextID(0) == 1 && BleProtocol.nextID(254) == 255 && BleProtocol.nextID(255) == 1, "ID cycle")
for length in [1, 16, 17, 255, 256] {
  let payload = Data((0..<length).map { UInt8($0) })
  let chunks = BleProtocol.frames(payload, id: 255)
  check(chunks.count == (length + 15) / 16, "boundary count")
  check(chunks.dropLast().allSatisfy { $0.count == 20 }, "nonfinal size")
  check(Data(chunks.flatMap { Array($0.dropFirst(4)) }) == payload, "boundary round trip")
}
print("PASS: native Hello, 00..ff, ACK, frame boundaries, ID rollover")

var receiver = BleReassembler()
let receivedHello = try receiver.receive(BleProtocol.frames(BleProtocol.hello, id: 1)[0])
check(receivedHello == BleProtocol.hello, "receive Hello")
check(receiver.acknowledgement == Data([1, 1, 0, 5]), "receiver Hello ACK")
for (index, frame) in frames.enumerated() {
  let result = try receiver.receive(frame)
  if index < 15 {
    check(result == nil && receiver.acknowledgement == nil && receiver.isReceiving, "ACK withheld until complete")
  } else {
    check(result == BleProtocol.larger && !receiver.isReceiving, "complete larger vector")
    check(receiver.acknowledgement == Data([1, 2, 1, 0]), "receiver larger ACK")
  }
}
func rejects(_ sequence: [Data], _ label: String) {
  var receiver = BleReassembler()
  do {
    for frame in sequence { _ = try receiver.receive(frame) }
    fatalError("accepted invalid sequence: \(label)")
  } catch {
    check(receiver.acknowledgement == nil && !receiver.isReceiving && receiver.payload.isEmpty, "reset after \(label)")
    do {
      let result = try receiver.receive(BleProtocol.frames(BleProtocol.hello, id: 255)[0])
      check(result == BleProtocol.hello, "recovery after \(label)")
    } catch { fatalError("recovery failed: \(label)") }
  }
}
for bad in [Data(), Data([1, 1, 0, 1]), Data(repeating: 1, count: 21),
  Data([2, 1, 0, 1, 0]), Data([1, 0, 0, 1, 0]), Data([1, 1, 0, 0, 0]),
  Data([1, 1, 0, 17, 0]), Data([1, 1, 1, 1, 0]), Data([1, 1, 0, 2, 0]),
  Data([1, 1, 0, 1, 0])] { rejects([bad], "malformed/vector") }
rejects([frames[1]], "missing first")
rejects([frames[0], frames[0]], "overlap/duplicate")
rejects([frames[0], frames[2]], "skipped frame")
var wrongID = Array(frames[1]); wrongID[1] = 3
rejects([frames[0], Data(wrongID)], "changed ID")
var wrongCount = Array(frames[1]); wrongCount[3] = 15
rejects([frames[0], Data(wrongCount)], "changed count")
var corrupt = frames
var final = Array(corrupt[15]); final[19] = 0; corrupt[15] = Data(final)
rejects(corrupt, "corrupt completed vector")
var incomplete = BleReassembler()
_ = try incomplete.receive(frames[0])
check(incomplete.acknowledgement == nil, "incomplete has no ACK")
incomplete.reset() // same reset used for timeout/restart cleanup
check(!incomplete.isReceiving && incomplete.payload.isEmpty && incomplete.acknowledgement == nil, "timeout reset")
_ = try incomplete.receive(BleProtocol.frames(BleProtocol.hello, id: 1)[0])
incomplete.reset()
check(incomplete.acknowledgement == nil, "cleanup clears completed ACK")
// Value semantics allow an invalid ATT batch to be discarded atomically.
var committed = BleReassembler()
var candidate = committed
_ = try candidate.receive(frames[0])
check(!committed.isReceiving && committed.payload.isEmpty, "uncommitted batch isolated")
print("PASS: peripheral reassembly, exact vectors, ACK timing, malformed/order rejection, reset, atomic candidate")
