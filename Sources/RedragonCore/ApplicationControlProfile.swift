// SPDX-License-Identifier: MIT
import Foundation

/// Standard F1–F4 emissions let the K628's physical 1–4 launch apps without Fn.
/// F5–F10 distinguish the six action-pad buttons from ordinary numeric typing.
public enum ApplicationControlProfile {
  public static let launcherSlots = Array(1...4)
  public static let launcherAssignments = (0..<4).map { 0x20003a + $0 }
  public static let padAssignments = (0..<6).map { 0x20003e + $0 }
  public static let padColors: [[UInt8]] = [[60,150,255], [255,170,35], [190,100,255], [90,215,215], [255,105,140], [80,220,130]]

  public static func prepareLaunchers(on current: Snapshot) throws -> Snapshot {
    var result = current
    for index in 0..<4 { try result.assign(launcherAssignments[index], to: launcherSlots[index]) }
    return result
  }
  public static func restoreLaunchers(baseline: Snapshot, installed: Snapshot, current: Snapshot) throws -> Snapshot {
    _ = try baseline.preparedForRestore(on: current)
    guard launcherSlots.allSatisfy({ current.assignment(at: $0) == installed.assignment(at: $0) }) else {
      throw S136Error.message("Los accesos 1–4 cambiaron fuera de la app. Se conserva el respaldo.")
    }
    var result = current
    for slot in launcherSlots { try result.assign(baseline.assignment(at: slot), to: slot) }
    return result
  }
  public static func preparePad(on current: Snapshot, preserveColors: Bool = false) throws -> Snapshot {
    var result = current
    for index in 0..<6 {
      try result.assign(padAssignments[index], to: CodexMicroProfile.slots[index])
      if !preserveColors { try result.setKeyColor(padColors[index], at: CodexMicroProfile.slots[index]) }
    }
    if result.configuration[2] == 0 { result.configuration[2] = 4 }
    return result
  }
  public static func restorePad(baseline: Snapshot, installed: Snapshot, current: Snapshot) throws -> Snapshot {
    // The same six positions, lighting fields and conflict checks as the chat pad.
    try CodexMicroProfile.restore(baseline: baseline, installed: installed, current: current)
  }
}

public enum ApplicationPadAction: String, Codable, CaseIterable, Sendable {
  case usage, attention, dictation, model, review, newChat, search, settings
  public var title: String {
    switch self {
    case .usage: "Ver uso"; case .attention: "Pregunta pendiente"; case .dictation: "Dictar"
    case .model: "Modelo"; case .review: "Revisar cambios"; case .newChat: "Nuevo chat"; case .search: "Buscar chats"; case .settings: "Ajustes"
    }
  }
  public static func actions(for skin: KeyboardSkin) -> [Self] {
    skin == .claude ? [.usage, .newChat, .dictation, .model, .search, .settings]
      : [.usage, .attention, .dictation, .model, .review, .newChat]
  }
}

public enum ApplicationProfileRouting {
  public static func skin(for bundleID: String) -> KeyboardSkin? {
    switch bundleID {
    case "com.openai.codex": .codex
    case "com.anthropic.claudefordesktop": .claude
    case "com.google.Chrome", "net.whatsapp.WhatsApp": .apps
    default: nil
    }
  }
  /// First press recovers the last window; subsequent presses cycle while Chrome is frontmost.
  public static func chromeIndex(count: Int, remembered: Int?, focused: Int?, isFrontmost: Bool) -> Int? {
    guard count > 0 else { return nil }
    let valid: (Int?) -> Int? = { value in value.flatMap { (0..<count).contains($0) ? $0 : nil } }
    let current = valid(focused) ?? valid(remembered) ?? 0
    return isFrontmost ? (current + 1) % count : (valid(remembered) ?? valid(focused) ?? 0)
  }
}
