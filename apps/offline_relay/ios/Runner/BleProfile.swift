import Foundation

/// iOS advertisement supports service UUIDs/local name, not custom service data.
/// A compact role/name lets Dart filter helpers; the full profile is read at connect.
enum BleProfile {
  static let characteristic = "41729610-0934-4e0e-b749-170442310004"
  static func validate(_ map: [String: Any]) throws -> [String: Any] {
    guard let id = map["id"] as? String, !id.isEmpty,
      let label = map["label"] as? String, !label.isEmpty,
      let metadata = map["metadata"] as? [String: String] else {
      throw NSError(domain: "OfflineRelayBLE", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Malformed profile"])
    }
    return ["id": id, "label": label, "metadata": metadata]
  }
  static func encode(_ profile: [String: Any]) throws -> Data {
    let data = try JSONSerialization.data(withJSONObject: validate(profile), options: [.sortedKeys])
    guard data.count <= 512 else {
      throw NSError(domain: "OfflineRelayBLE", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Profile exceeds 512 bytes"])
    }
    return data
  }
  static func decode(_ data: Data) throws -> [String: Any] {
    guard let map = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw NSError(domain: "OfflineRelayBLE", code: 3)
    }
    return try validate(map)
  }
  static func advertisedName(_ profile: [String: Any]) -> String {
    let metadata = profile["metadata"] as? [String: String] ?? [:]
    let prefix = metadata["role"] == "internet_helper" ? "ORH:" : "ORU:"
    var label = profile["label"] as? String ?? "User"
    while label.utf8.count > 6 { label.removeLast() }
    return prefix + label
  }
  static func discoveryPeer(id: String, name: String) -> [String: Any]? {
    guard name.hasPrefix("ORH:") || name.hasPrefix("ORU:") else { return nil }
    let label = String(name.dropFirst(4))
    return ["id": id, "label": label.isEmpty ? "Nearby user" : label,
      "metadata": ["role": name.hasPrefix("ORH:") ? "internet_helper" : "offline_user"]]
  }
}
