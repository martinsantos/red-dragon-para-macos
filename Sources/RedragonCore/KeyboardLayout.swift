// SPDX-License-Identifier: MIT
import Foundation

public struct PhysicalKey: Identifiable, Sendable {
  public let slot: Int
  public let row: Int
  public let column: Double
  public let width: Double
  public var id: Int { slot }
  public var label: String {
    switch slot {
    case 13: "⌫"
    case 14: "Num"
    case 15: "+"
    case 16: "Tab"
    case 32: "Caps"
    case 45: "Enter"
    case 48, 61: "Shift"
    case 64, 76: "Ctrl"
    case 65: "Win"
    case 66, 73: "Alt"
    case 69: "Espacio"
    case 74: "Fn"
    case 80: "−"
    case 85: "0"
    case 86: "."
    default:
      KeyCatalog.physicalName(slot: slot, keyboard: true)
        .replacingOccurrences(of: "Num ", with: "")
        .replacingOccurrences(of: "− / _", with: "−")
        .replacingOccurrences(of: "= / +", with: "=")
        .replacingOccurrences(of: "Ñ / ;", with: ";")
        .replacingOccurrences(of: "Acento / ‘", with: "'")
    }
  }
}

/// The K628's 78 physical keys aligned with verified firmware matrix slots.
/// ISO-only and firmware-only slots are omitted from this ANSI diagram.
public enum KeyboardLayout {
  public static let columns = 18.0
  public static let rowCount = 5
  public static let keys: [PhysicalKey] = {
    let rows: [[(Int, Double)]] = [
      [(0, 1)] + (1...12).map { ($0, 1.0) } + [(13, 2), (14, 1), (15, 1), (80, 1)],
      [(16, 1.5)] + (17...28).map { ($0, 1.0) } + [(29, 1.5), (30, 1), (31, 1), (81, 1)],
      [(32, 1.75)] + (33...43).map { ($0, 1.0) } + [(45, 2.25), (46, 1), (47, 1), (82, 1)],
      [(48, 2.25)] + (50...59).map { ($0, 1.0) } + [
        (61, 1.75), (62, 1), (63, 1), (83, 1), (84, 1),
      ],
      [
        (64, 1.25), (65, 1.25), (66, 1.25), (69, 6.25), (73, 1), (74, 1), (76, 1), (77, 1), (78, 1),
        (79, 1), (85, 1), (86, 1),
      ],
    ]
    return rows.enumerated().flatMap { row, entries in
      var column = 0.0
      return entries.map { slot, width in
        defer { column += width }
        return PhysicalKey(slot: slot, row: row, column: column, width: width)
      }
    }
  }()
}
