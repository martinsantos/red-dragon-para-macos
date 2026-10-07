// SPDX-License-Identifier: MIT
import Foundation

enum AppSection: String, CaseIterable, Identifiable {
  case mapping = "Teclas y botones"
  case lighting = "Iluminación"
  case dpi = "DPI y respuesta"
  case macros = "Macros"
  case backup = "Respaldo"
  case skins = "Skins"
  case micro = "Codex Micro"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .mapping: "keyboard"
    case .lighting: "lightbulb"
    case .dpi: "speedometer"
    case .macros: "repeat"
    case .backup: "externaldrive"
    case .skins: "paintpalette"
    case .micro: "circle.hexagongrid"
    }
  }
}
