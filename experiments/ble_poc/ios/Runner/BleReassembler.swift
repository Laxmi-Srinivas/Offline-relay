import Foundation

/// Bounded value-type receiver; a request batch can be validated before commit.
struct BleReassembler {
  enum Failure: Error { case malformed, ordering, payload }
  private(set) var acknowledgement: Data?
  private(set) var payload = Data()
  private var messageID: UInt8?
  private var count = 0
  private var nextIndex = 0
  var isReceiving: Bool { messageID != nil }

  mutating func reset() { self = BleReassembler() }

  /// On failure discard both the incomplete message and any stale ACK.
  mutating func receive(_ frame: Data) throws -> Data? {
    do { return try append(frame) } catch { reset(); throw error }
  }

  private mutating func append(_ frame: Data) throws -> Data? {
    let bytes = Array(frame)
    guard (5...20).contains(bytes.count), bytes[0] == 1 else { throw Failure.malformed }
    let id = bytes[1], index = Int(bytes[2]), total = Int(bytes[3])
    guard id != 0, (1...16).contains(total), index < total,
      index == total - 1 || bytes.count == 20 else { throw Failure.malformed }
    if index == 0 {
      guard messageID == nil else { throw Failure.ordering }
      acknowledgement = nil
      messageID = id
      count = total
    }
    guard messageID == id, count == total, nextIndex == index,
      payload.count + bytes.count - 4 <= 256 else { throw Failure.ordering }
    payload.append(contentsOf: bytes.dropFirst(4))
    nextIndex += 1
    guard nextIndex == count else { return nil }
    let complete = payload
    guard complete == BleProtocol.hello || complete == BleProtocol.larger else { throw Failure.payload }
    acknowledgement = BleProtocol.acknowledgement(id: id, length: complete.count)
    payload = Data()
    messageID = nil
    count = 0
    nextIndex = 0
    return complete
  }
}
