// SPDX-License-Identifier: MIT
import Foundation

/// Metadata-only reducer for the observed Codex Desktop JSONL event format.
/// This adapter is version-dependent; unknown events never imply success or failure.
public struct CodexRolloutState: Sendable {
  public private(set) var threadID: String?
  public private(set) var state = MicroState.disconnected
  public private(set) var lastEventAt: Date?
  public private(set) var pendingQuestions: Set<String> = []
  private var activeTurn: String?
  private var active = false
  public init() {}

  public mutating func consume(_ line: Data) {
    guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let payload = row["payload"] as? [String: Any] else { return }
    if row["type"] as? String == "session_meta" {
      if let id = payload["id"] as? String, UUID(uuidString: id) != nil { threadID = id }
      return
    }
    var relevant = false
    if row["type"] as? String == "event_msg" {
      switch payload["type"] as? String {
      case "task_started":
        activeTurn = payload["turn_id"] as? String
        active = true
        state = pendingQuestions.isEmpty ? .thinking : .attention
        relevant = true
      case "task_complete":
        if let turn = payload["turn_id"] as? String, let activeTurn, turn != activeTurn { return }
        active = false
        state = pendingQuestions.isEmpty ? .complete : .attention
        relevant = true
      case "turn_aborted":
        if let turn = payload["turn_id"] as? String, let activeTurn, turn != activeTurn { return }
        active = false
        pendingQuestions = []
        state = .idle
        relevant = true
      default: break
      }
    } else if row["type"] as? String == "response_item" {
      if payload["type"] as? String == "function_call",
         ["request_user_input", "request_user_input_async"].contains(payload["name"] as? String ?? ""),
         let id = payload["call_id"] as? String, active {
        pendingQuestions.insert(id)
        state = .attention
        relevant = true
      } else if payload["type"] as? String == "function_call_output",
                let id = payload["call_id"] as? String, pendingQuestions.contains(id),
                let output = payload["output"] as? String,
                let result = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
                let answers = result["answers"] as? [String: Any], !answers.isEmpty {
        pendingQuestions.remove(id)
        state = pendingQuestions.isEmpty ? (active ? .thinking : .complete) : .attention
        relevant = true
      } else if payload["type"] as? String == "message", payload["role"] as? String == "user" {
        let content = payload["content"] as? [[String: Any]] ?? []
        for part in content {
          guard let text = part["text"] as? String,
            let start = text.range(of: "<send_user_message_question_reply>"),
            let end = text.range(of: "</send_user_message_question_reply>", range: start.upperBound..<text.endIndex),
            let answers = try? JSONSerialization.jsonObject(with: Data(text[start.upperBound..<end.lowerBound].utf8)) as? [[String: Any]] else { continue }
          for answer in answers {
            guard let item = answer["questionItemId"] as? String,
                  let ids = try? JSONSerialization.jsonObject(with: Data(item.utf8)) as? [Any] else { continue }
            for id in ids.compactMap({ $0 as? String }) where pendingQuestions.contains(id) {
              pendingQuestions.remove(id)
              relevant = true
            }
          }
        }
        if relevant { state = pendingQuestions.isEmpty ? (active ? .thinking : .complete) : .attention }
      }
    }
    if relevant, let stamp = row["timestamp"] as? String {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      lastEventAt = formatter.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
    }
  }
}
