// SPDX-License-Identifier: MIT
import Foundation

public enum MicroCommand: String, Codable, Sendable, CaseIterable {
  case on, off, toggle, status, show
}

public struct MicroControlRequest: Codable, Sendable {
  public let version: Int
  public let command: MicroCommand
  public init(_ command: MicroCommand) { version = 1; self.command = command }
  public func validate() throws {
    guard version == 1 else { throw S136Error.message("Versión de comando no compatible.") }
  }
}

public struct MicroControlStatus: Codable, Sendable {
  public var hardwareActive: Bool
  public var recoveryPending: Bool
  public var skinVisible: Bool
  public var busy: Bool
  public var message: String
  public init(hardwareActive: Bool, recoveryPending: Bool, skinVisible: Bool, busy: Bool, message: String) {
    self.hardwareActive = hardwareActive; self.recoveryPending = recoveryPending
    self.skinVisible = skinVisible; self.busy = busy; self.message = message
  }
}

public struct MicroControlResponse: Codable, Sendable {
  public let ok: Bool
  public let status: MicroControlStatus
  public let error: String?
  public init(ok: Bool, status: MicroControlStatus, error: String? = nil) {
    self.ok = ok; self.status = status; self.error = error
  }
}

/// Observe transitions, not replayed history. The first state of each route is a baseline.
public struct MicroAttentionTracker: Sendable {
  private var previous: [Int: MicroState] = [:]
  private var previousQuestions: [Int: Set<String>] = [:]
  public init() {}
  public mutating func update(_ states: [Int: MicroState], questions: [Int: Set<String>] = [:]) -> [Int] {
    let alerts = states.keys.sorted().filter {
      states[$0] == .attention && previous[$0] != nil && previous[$0] != .disconnected
        && (previous[$0] != .attention || !(questions[$0] ?? []).subtracting(previousQuestions[$0] ?? []).isEmpty)
    }
    previous = states
    previousQuestions = questions
    return alerts
  }
}
