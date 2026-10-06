// SPDX-License-Identifier: MIT
import Foundation

public struct KeyChoice: Identifiable, Hashable, Sendable {
  public let name: String
  public let code: Int
  public var id: Int { code }
  public init(_ name: String, _ code: Int) {
    self.name = name
    self.code = code
  }
}
public enum KeyCatalog {
  public static let keys: [KeyChoice] = {
    var result = [KeyChoice("Sin acción", 0x200000)]
    for (i, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
      result.append(KeyChoice(String(letter), 0x200004 + i))
    }
    for i in 1...9 { result.append(KeyChoice(String(i), 0x20001d + i)) }
    result.append(KeyChoice("0", 0x200027))
    let names = [
      0x28: "Enter", 0x29: "Esc", 0x2a: "Borrar ←", 0x2b: "Tab", 0x2c: "Espacio", 0x2d: "− / _",
      0x2e: "= / +",
      0x2f: "[", 0x30: "]", 0x31: "\\", 0x32: "ISO # / ~", 0x33: "Ñ / ;", 0x34: "Acento / ‘",
      0x35: "` / ~",
      0x36: ",", 0x37: ".", 0x38: "/", 0x39: "Caps Lock", 0x46: "Imprimir pantalla",
      0x47: "Scroll Lock", 0x48: "Pausa",
      0x49: "Insert", 0x4a: "Inicio", 0x4b: "Página arriba", 0x4c: "Suprimir", 0x4d: "Fin",
      0x4e: "Página abajo",
      0x4f: "→", 0x50: "←", 0x51: "↓", 0x52: "↑", 0x53: "Num Lock", 0x54: "Num /", 0x55: "Num *",
      0x56: "Num −",
      0x57: "Num +", 0x58: "Num Enter", 0x62: "Num 0", 0x63: "Num .", 0x64: "ISO < / >",
      0x65: "Menú",
    ]
    result += names.sorted { $0.key < $1.key }.map { KeyChoice($0.value, 0x200000 + $0.key) }
    for i in 1...24 {
      result.append(KeyChoice("F\(i)", (i <= 12 ? 0x200039 + i : 0x200068 + i - 13)))
    }
    for i in 1...9 { result.append(KeyChoice("Num \(i)", 0x200058 + i)) }
    result += [
      KeyChoice("Control izquierdo", 0x200100), KeyChoice("Shift izquierdo", 0x200200),
      KeyChoice("Option izquierdo", 0x200400), KeyChoice("Command izquierdo", 0x200800),
      KeyChoice("Control derecho", 0x201000), KeyChoice("Shift derecho", 0x202000),
      KeyChoice("Option derecho", 0x204000), KeyChoice("Command derecho", 0x208000),
    ]
    return result
  }()
  public static let mouse = [
    KeyChoice("Clic izquierdo", 0x100100), KeyChoice("Clic derecho", 0x100200),
    KeyChoice("Clic central", 0x100400), KeyChoice("Atrás", 0x100800),
    KeyChoice("Adelante", 0x101000),
    KeyChoice("DPI +", 0x130100), KeyChoice("DPI −", 0x130200),
  ]
  public static func name(_ code: Int) -> String {
    if code >> 16 == 0x71 { return "Macro \(((code >> 8) & 255)+1) · ×\(code & 255)" }
    if code >> 16 == 0x70 { return "Macro \(((code >> 8) & 255)+1)" }
    if code == 0xa00100 { return "Fn" }
    return (keys + mouse).first { $0.code == code }?.name ?? String(format: "Acción %06X", code)
  }
  // Baseline read from this S136, not assumptions based on another Redragon model.
  private static let keyboardBaseline: [Int] = [
    0x200029, 0x20001e, 0x20001f, 0x200020, 0x200021, 0x200022, 0x200023, 0x200024, 0x200025,
    0x200026, 0x200027, 0x20002d, 0x20002e, 0x20002a, 0x200053, 0x200057,
    0x20002b, 0x200014, 0x20001a, 0x200008, 0x200015, 0x200017, 0x20001c, 0x200018, 0x20000c,
    0x200012, 0x200013, 0x20002f, 0x200030, 0x200031, 0x20005f, 0x200060,
    0x200039, 0x200004, 0x200016, 0x200007, 0x200009, 0x20000a, 0x20000b, 0x20000d, 0x20000e,
    0x20000f, 0x200033, 0x200034, 0x200032, 0x200028, 0x20005c, 0x20005d,
    0x200200, 0x200064, 0x20001d, 0x20001b, 0x200006, 0x200019, 0x200005, 0x200011, 0x200010,
    0x200036, 0x200037, 0x200038, 0x200087, 0x202000, 0x200052, 0x200059,
    0x200100, 0x200800, 0x200400, 0x200091, 0x20008b, 0x20002c, 0x20008a, 0x200088, 0x200090,
    0x204000, 0xa00100, 0x200065, 0x201000, 0x200050, 0x200051, 0x20004f,
    0x200056, 0x200061, 0x20005e, 0x20005a, 0x20005b, 0x200062, 0x200063,
  ]
  public static func physicalName(slot: Int, keyboard: Bool) -> String {
    if keyboard {
      if slot == 65 { return "Win izquierdo" }
      if slot == 66 { return "Alt izquierdo" }
      if slot == 73 { return "Alt derecho" }
      return slot < keyboardBaseline.count ? name(keyboardBaseline[slot]) : "Posición \(slot+1)"
    }
    let names = [
      "Izquierdo", "Rueda", "Derecho", "Función extra", "Lateral adelante", "Lateral atrás",
      "DPI +", "DPI −",
    ]
    return slot < names.count ? names[slot] : "Posición \(slot+1)"
  }
  public static func visibleSlots(_ snapshot: Snapshot) -> [Int] {
    if snapshot.isKeyboard {
      return KeyboardLayout.keys.map(\.slot).filter { $0 < snapshot.keyCount }
    }
    return [0, 1, 2, 4, 5, 6, 7].filter { $0 < snapshot.keyCount }
  }
  public static let keyboardModes: [KeyChoice] = [
    "Onda", "Nubes", "Remolino", "Espectro", "Respiración", "Color fijo", "Reactivo",
    "Ondas al pulsar", "Línea al pulsar", "Estrellas", "Flor", "Onda vertical", "Huracán",
    "Acumulación", "Estrellas lentas", "Visor", "Ascenso", "Onda circular", "Personalizado",
  ].enumerated().map { KeyChoice($0.element, $0.offset + 1) }
  public static let mouseModes: [KeyChoice] = [
    KeyChoice("Onda", 0), KeyChoice("Espectro", 1), KeyChoice("Respiración", 2),
    KeyChoice("Color fijo", 3),
  ]
}
