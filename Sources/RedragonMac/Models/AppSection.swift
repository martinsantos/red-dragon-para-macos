// SPDX-License-Identifier: MIT
import Foundation

enum AppSection: String, CaseIterable, Identifiable {
  case mapping = "Teclas y botones"
  case lighting = "Iluminación"
  case dpi = "DPI y respuesta"
  case macros = "Macros"
  case backup = "Respaldo"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .mapping: "keyboard"
    case .lighting: "lightbulb"
    case .dpi: "speedometer"
    case .macros: "repeat"
    case .backup: "externaldrive"
    }
  }
}
