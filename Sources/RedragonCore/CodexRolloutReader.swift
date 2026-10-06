// SPDX-License-Identifier: MIT
import Foundation

public actor CodexRolloutReader {
  private var offset: UInt64 = 0
  private var buffer = Data()
  private var skippingLongLine = false
  private var reducer = CodexRolloutState()
  private let url: URL
  public init(url: URL) { self.url = url }

  public func read() throws -> CodexRolloutState {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let size = try file.seekToEnd()
    if size < offset { offset = 0; buffer = Data(); reducer = CodexRolloutState(); skippingLongLine = false }
    try file.seek(toOffset: offset)
    // Stream complete lines; never retain conversation text or tool output.
    while let data = try file.read(upToCount: 65_536), !data.isEmpty {
      offset += UInt64(data.count)
      buffer.append(data)
      while let end = buffer.firstIndex(of: 10) {
        if !skippingLongLine { reducer.consume(Data(buffer[..<end])) }
        buffer.removeSubrange(...end)
        skippingLongLine = false
      }
      if buffer.count > 1_048_576 { buffer = Data(); skippingLongLine = true }
    }
    return reducer
  }
}
