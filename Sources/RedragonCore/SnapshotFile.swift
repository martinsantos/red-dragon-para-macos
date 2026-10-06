// SPDX-License-Identifier: MIT
import Foundation

public enum SnapshotFile {
  public static func load(_ url: URL) throws -> Snapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(Snapshot.self, from: Data(contentsOf: url))
    try snapshot.validateStructure()
    return snapshot
  }

  public static func save(_ snapshot: Snapshot, to url: URL) throws {
    try snapshot.validateStructure()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }
}
