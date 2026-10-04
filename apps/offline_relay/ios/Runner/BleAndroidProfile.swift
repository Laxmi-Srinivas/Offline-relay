import Foundation

/// Decodes Android's existing scan-response service data, not a GATT profile.
/// Layout: version=1, role (1=requester, 2=helper), UTF-8 byte length, label.
enum BleAndroidProfile {
  static func peer(id: String, serviceData: Data) -> [String: Any]? {
    let bytes = Array(serviceData)
    guard bytes.count >= 4, bytes[0] == 1,
      (1...10).contains(Int(bytes[2])), bytes.count == Int(bytes[2]) + 3,
      let label = String(bytes: bytes.dropFirst(3), encoding: .utf8), !label.isEmpty else { return nil }
    let role: String
    switch bytes[1] {
    case 1: role = "offline_user"
    case 2: role = "internet_helper"
    default: return nil
    }
    return ["id": id, "label": label, "metadata": ["role": role]]
  }
}
