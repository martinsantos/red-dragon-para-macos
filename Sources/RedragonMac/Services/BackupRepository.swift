// SPDX-License-Identifier: MIT
import Foundation
import RedragonCore

struct BackupRepository {
  let directory: URL

  init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("RedragonMac/Backups", isDirectory: true)
  }

  func createDirectory() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func save(_ snapshot: Snapshot) throws -> URL {
    try createDirectory()
    let kind = snapshot.isKeyboard ? "keyboard" : "mouse"
    let name = "\(kind)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json"
    let url = directory.appendingPathComponent(name)
    try SnapshotFile.save(snapshot, to: url)
    return url
  }

  func load(_ url: URL, for current: Snapshot) throws -> Snapshot {
    try SnapshotFile.load(url).preparedForRestore(on: current)
  }
}
