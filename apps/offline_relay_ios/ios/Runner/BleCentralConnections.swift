import Foundation

/// Main-queue registry: every peer owns an isolated GATT session. Tokens reject
/// late events/results after that peer is removed or replaced.
final class BleCentralConnections<Session: AnyObject> {
  struct Entry {
    let token: UUID
    let session: Session
    var connectionID: String?
  }
  private(set) var entries: [String: Entry] = [:]
  func insert(peerID: String, session: Session, token: UUID) -> Bool {
    guard entries[peerID] == nil else { return false }
    entries[peerID] = Entry(token: token, session: session)
    return true
  }
  func contains(peerID: String, token: UUID) -> Bool { entries[peerID]?.token == token }
  func bind(peerID: String, token: UUID, connectionID: String) {
    guard contains(peerID: peerID, token: token) else { return }
    entries[peerID]?.connectionID = connectionID
  }
  func session(connectionID: String) -> Session? {
    entries.values.first(where: { $0.connectionID == connectionID })?.session
  }
  @discardableResult func remove(peerID: String, token: UUID) -> Session? {
    guard contains(peerID: peerID, token: token) else { return nil }
    return entries.removeValue(forKey: peerID)?.session
  }
  func takePending() -> [Session] {
    let pending = entries.filter { $0.value.connectionID == nil }
    for id in pending.keys { entries[id] = nil }
    return pending.values.map { $0.session }
  }
  func takeAll() -> [Session] {
    let sessions = entries.values.map { $0.session }; entries = [:]; return sessions
  }
}
