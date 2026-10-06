// SPDX-License-Identifier: MIT
import Foundation
import RedragonCore

struct MicroRecovery: Codable {
  var baseline: Snapshot
  var installed: Snapshot
  var bindings: [MicroBinding]
  var backupURL: URL

  func validate() throws {
    try baseline.validateStructure()
    try installed.validateStructure()
    try MicroBinding.validate(bindings)
    _ = try baseline.preparedForRestore(on: installed)
    guard baseline.isKeyboard else { throw S136Error.message("El respaldo Micro debe ser de un teclado.") }
  }
}

struct MicroRecoveryRepository {
  let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("RedragonMac/micro-recovery.json")

  func load() throws -> MicroRecovery? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let value = try decoder.decode(MicroRecovery.self, from: Data(contentsOf: url))
    try value.validate()
    return value
  }
  func save(_ recovery: MicroRecovery) throws {
    try recovery.validate()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(recovery).write(to: url, options: .atomic)
  }
  func clear() throws {
    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
  }
}
