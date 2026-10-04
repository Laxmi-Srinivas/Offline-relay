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
