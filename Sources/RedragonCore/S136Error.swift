// SPDX-License-Identifier: MIT
import Foundation

public enum S136Error: LocalizedError {
  case message(String)
  public var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}
