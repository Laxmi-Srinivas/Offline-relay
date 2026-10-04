import Foundation

/// Product framing adapted from the physically validated iOS diagnostic helper.
enum BleFraming {
  static let service = "41729610-0934-4e0e-b749-170442310001"
  static let data = "41729610-0934-4e0e-b749-170442310002"
  static let ack = "41729610-0934-4e0e-b749-170442310003"
  static let hello = Data("Hello".utf8)
  static let larger = Data((0...255).map { UInt8($0) })

  static func frames(_ payload: Data, id: UInt8) -> [Data] {
    precondition(id != 0 && !payload.isEmpty && payload.count <= 256)
    let bytes = Array(payload)
    let count = (bytes.count + 15) / 16
    return (0..<count).map { index in
      Data([1, id, UInt8(index), UInt8(count)] +
        Array(bytes[(index * 16)..<min((index + 1) * 16, bytes.count)]))
    }
  }

  static func acknowledgement(id: UInt8, length: Int) -> Data {
    Data([1, id, UInt8((length >> 8) & 255), UInt8(length & 255)])
  }

  static func nextID(_ id: UInt8) -> UInt8 { id == 255 ? 1 : id + 1 }
}
