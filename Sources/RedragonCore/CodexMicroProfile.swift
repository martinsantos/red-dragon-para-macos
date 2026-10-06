// SPDX-License-Identifier: MIT
import Foundation

public enum MicroState: String, Codable, CaseIterable, Sendable {
  case disconnected, idle, thinking, attention, complete, failed

  public var title: String {
    switch self {
    case .disconnected: "Sin conexión"
    case .idle: "En reposo"
    case .thinking: "Trabajando"
    case .attention: "Necesita tu respuesta"
    case .complete: "Terminó"
    case .failed: "Error"
    }
  }
  public var rgb: [UInt8] {
    switch self {
    case .disconnected: [0, 0, 0]
    case .idle: [230, 230, 230]
    case .thinking: [30, 110, 255]
    case .attention: [255, 160, 20]
    case .complete: [40, 220, 110]
    case .failed: [255, 50, 65]
    }
  }
  public static func runtime(_ status: [String: Any]) -> Self {
    switch status["type"] as? String {
    case "idle": return .idle
    case "systemError": return .failed
    case "active":
      let flags = status["activeFlags"] as? [String] ?? []
      return flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput")
        ? .attention : .thinking
    default: return .disconnected
    }
  }
}

public struct MicroBinding: Codable, Equatable, Sendable, Identifiable {
  public enum Action: String, Codable, CaseIterable, Sendable {
    case recentChat, localChat, prompt, indicator
    public var title: String {
      switch self {
      case .recentChat: "Chat reciente de Codex"
      case .localChat: "Abrir el chat conectado"
      case .prompt: "Copiar prefunción"
      case .indicator: "Solo indicador (sin acción)"
      }
    }
  }
  public var number: Int
  public var title: String
  public var action: Action
  public var prompt: String
  public var threadID: String
  public var id: Int { number }

  public static let defaults: [Self] = (1...6).map { number in
    let names = ["Chat 1", "Chat 2", "Chat 3", "Chat 4", "Chat 5", "Chat 6"]
    let prompts = [
      "Revisá los cambios actuales y señalá los problemas concretos.",
      "Investigá este error y proponé una corrección con una prueba relevante.",
      "Implementá la tarea que describo a continuación y verificá el resultado.",
      "Explicá cómo funciona este código con un ejemplo breve.",
      "Revisá qué falta para terminar esta tarea y continuá con el siguiente paso.",
      "Documentá el cambio y prepará una descripción breve para revisarlo.",
    ]
    return Self(number: number, title: names[number - 1], action: .recentChat,
                prompt: prompts[number - 1], threadID: "")
  }

  public static func validate(_ bindings: [Self]) throws {
    guard bindings.count == 6, bindings.map(\.number) == Array(1...6),
      bindings.allSatisfy({ $0.title.count <= 80 && $0.prompt.count <= 8000 && $0.threadID.count <= 128 })
    else { throw S136Error.message("El perfil Micro necesita seis botones válidos, numerados del 1 al 6.") }
  }
}

/// Uses the verified K628 matrix. Only six numpad keys and palette 1 are changed.
public enum CodexMicroProfile {
  public static let slots = [63, 83, 84, 46, 47, 82] // Num 1…6
  public static let displayOrder = [4, 5, 6, 1, 2, 3]

  public static func prepare(_ original: Snapshot, bindings: [MicroBinding], liveLighting: Bool = false, launcherColors: Bool = false) throws -> Snapshot {
    try original.validateStructure()
    try MicroBinding.validate(bindings)
    guard original.isKeyboard, original.customColors != nil else {
      throw S136Error.message("El modo Micro requiere el teclado K628 con su paleta disponible.")
    }
    var result = original
    for (index, binding) in bindings.enumerated() {
      // Keep standard keypad usages for app actions. F13 emissions were not
      // observed on the test unit; Carbon reserves these six keypad keys in Micro.
      let code: Int
      switch binding.action {
      case .recentChat: code = 0x200c1e + index
      case .localChat, .prompt: code = 0x200059 + index
      case .indicator: code = 0x200000
      }
      try result.assign(code, to: slots[index])
      try result.setKeyColor(binding.action == .recentChat ? [230, 230, 230] : [165, 95, 255], at: slots[index])
    }
    if result.configuration[2] == 0 { result.configuration[2] = 4 }
    if liveLighting { result.configuration[1] = 29 }
    if launcherColors {
      for i in 0..<4 { try result.setKeyColor(SkinPalette.launcherColors[i], at: i+1) }
    }
    return result
  }

  public static func withStates(_ states: [MicroState], on current: Snapshot) throws -> Snapshot {
    guard states.count == 6 else { throw S136Error.message("Se requieren seis estados Micro.") }
    var result = current
    for i in 0..<6 { try result.setKeyColor(states[i].rgb, at: slots[i]) }
    return result
  }

  /// Refuse restoration if an external app changed the six keys, profile or palette.
  /// Non-Micro changes are preserved when merging the original fields back.
  public static func restore(baseline: Snapshot, installed: Snapshot, current: Snapshot, launcherColors: Bool = false) throws -> Snapshot {
    try installed.validateStructure()
    _ = try baseline.preparedForRestore(on: current)
    guard installed.profile == current.profile, installed.capabilities == current.capabilities else {
      throw S136Error.message("Seleccioná el dispositivo y perfil donde activaste Micro.")
    }
    let configFields = [1, 2, 22]
    let colorSlots = slots + (launcherColors ? Array(1...4) : [])
    guard slots.allSatisfy({ installed.assignment(at: $0) == current.assignment(at: $0) }),
      configFields.allSatisfy({ installed.configuration[$0] == current.configuration[$0] }),
      colorSlots.allSatisfy({ slot in
        installed.customColors.map { Array($0[slot * 3..<slot * 3 + 3]) }
          == current.customColors.map { Array($0[slot * 3..<slot * 3 + 3]) }
      })
    else {
      throw S136Error.message("Los ajustes Micro cambiaron fuera de la app. Recuperá el respaldo desde Respaldo para elegir qué restaurar.")
    }
    var result = current
    for field in configFields { result.configuration[field] = baseline.configuration[field] }
    for slot in slots {
      try result.assign(baseline.assignment(at: slot), to: slot)
    }
    for slot in colorSlots {
      if var colors = result.customColors, let before = baseline.customColors {
        colors.replaceSubrange(slot * 3..<slot * 3 + 3, with: before[slot * 3..<slot * 3 + 3])
        result.customColors = colors
      }
    }
    return result
  }
}
