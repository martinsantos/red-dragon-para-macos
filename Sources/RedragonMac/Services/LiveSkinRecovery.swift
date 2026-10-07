// SPDX-License-Identifier: MIT
import Foundation
import RedragonCore

struct LiveSkinRecovery: Codable {
  let baseline: Snapshot
  let installed: Snapshot
  let skin: KeyboardSkin
}
struct LiveSkinRepository {
  private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("RedragonMac/live-skin.json")
  func load() throws -> LiveSkinRecovery? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let value = try decoder.decode(LiveSkinRecovery.self, from: Data(contentsOf: url))
    try value.baseline.validateStructure()
    _ = try value.installed.preparedForRestore(on: value.baseline)
    guard value.baseline.isKeyboard else { throw S136Error.message("La recuperación de skin debe ser de un teclado.") }
    return value
  }
  func save(_ value: LiveSkinRecovery) throws {
    try value.baseline.validateStructure()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(value).write(to: url, options: .atomic)
  }
  func clear() throws { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
}
