// SPDX-License-Identifier: MIT
import Foundation

/// Serializes mode requests. A second toggle reverses the requested mode, even
/// before the first activation has finished writing its recovery record.
public actor MicroModeRequestQueue {
  private struct Request {
    let target: Bool
    let completion: CheckedContinuation<MicroControlResponse, Never>
  }
  private var requests: [Request] = []
  private var processing = false
  private var revision: UInt64 = 0
  private let transition: @Sendable (Bool) async -> MicroControlResponse
  private let changed: @Sendable (Bool?, UInt64) async -> Void

  public init(transition: @escaping @Sendable (Bool) async -> MicroControlResponse,
              changed: @escaping @Sendable (Bool?, UInt64) async -> Void) {
    self.transition = transition; self.changed = changed
  }
  public func submit(_ command: MicroCommand, currentActive: Bool) async -> MicroControlResponse {
    guard [.on, .off, .toggle].contains(command) else {
      return .init(ok: false, status: .init(hardwareActive: currentActive, recoveryPending: currentActive,
        skinVisible: false, busy: processing, message: "Comando de transición no válido."), error: "Comando de transición no válido.")
    }
    let target = command == .on || (command == .toggle && !(requests.last?.target ?? currentActive))
    return await withCheckedContinuation { completion in
      requests.append(Request(target: target, completion: completion))
      revision += 1
      let update = revision
      Task { await changed(target, update) }
      if !processing {
        processing = true
        Task { await drain() }
      }
    }
  }
  private func drain() async {
    while let request = requests.first {
      let result = await transition(request.target)
      requests.removeFirst()
      revision += 1
      await changed(requests.last?.target, revision)
      request.completion.resume(returning: result)
    }
    processing = false
  }
}
