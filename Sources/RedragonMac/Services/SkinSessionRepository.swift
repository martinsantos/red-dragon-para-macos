// SPDX-License-Identifier: MIT
import Foundation
import RedragonCore

struct SkinSessionState: Codable {
  var session: KeyboardSkinSession?
  var pending: SkinTransitionJournal?
}
struct SkinSessionRepository {
  private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("RedragonMac/skin-session.json")
  func load() throws -> SkinSessionState? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let value = try decoder.decode(SkinSessionState.self, from: Data(contentsOf: url))
    try value.session?.validate()
    if let pending = value.pending {
      _ = try pending.before.preparedForRestore(on: pending.after)
      try pending.previous?.validate(); try pending.proposed?.validate()
    }
    return value
  }
  func save(_ state: SkinSessionState) throws {
    try state.session?.validate()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(state).write(to: url, options: .atomic)
  }
}
