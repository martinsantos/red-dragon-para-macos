// SPDX-License-Identifier: MIT
import Foundation

public struct MacroEvent: Hashable, Sendable {
  public var delay: UInt16
  public var type: UInt8
  public var button: UInt8
  public var down: Bool
  public init(delay: UInt16 = 10, type: UInt8 = 0, button: UInt8, down: Bool) {
    self.delay = delay
    self.type = type
    self.button = button
    self.down = down
  }
  public var bytes: [UInt8] {
    [UInt8(delay & 255), UInt8(delay >> 8), type | (down ? 128 : 0), button]
  }
}
public struct MacroDefinition: Sendable {
  public var events: [MacroEvent]
  var reserved: [UInt8] = [0, 0]
  public init(events: [MacroEvent] = []) { self.events = events }
}
public struct MacroTable: Sendable {
  public var definitions: [MacroDefinition] = []
  private var original: [UInt8]
  public init(bytes: [UInt8]) throws {
    guard bytes.count >= 16 else {
      throw S136Error.message("No se pudo leer la memoria de macros.")
    }
    original = bytes
    if bytes.prefix(16).allSatisfy({ $0 == 0 }) { return }
    let length = Int(bytes[2]) | Int(bytes[3]) << 8
    let count = Int(bytes[4]) | Int(bytes[5]) << 8
    guard bytes[0] == 0xaa, bytes[1] == 0x55, (16...bytes.count).contains(length), count <= 255,
      16 + count * 2 <= length
    else {
      throw S136Error.message(
        "El formato de las macros existentes no está reconocido. Se conservan sin modificar.")
    }
    for i in 0..<count {
      let offset = Int(bytes[16 + i * 2]) | Int(bytes[17 + i * 2]) << 8
      guard offset >= 16 + count * 2, offset + 4 <= length else {
        throw S136Error.message("Índice de macro inválido.")
      }
      let n = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
      guard offset + 4 + n * 4 <= length else {
        throw S136Error.message("Secuencia de macro inválida.")
      }
      var definition = MacroDefinition()
      definition.reserved = Array(bytes[offset + 2..<offset + 4])
      for j in 0..<n {
        let p = offset + 4 + j * 4
        definition.events.append(
          MacroEvent(
            delay: UInt16(bytes[p]) | UInt16(bytes[p + 1]) << 8, type: bytes[p + 2] & 127,
            button: bytes[p + 3], down: bytes[p + 2] & 128 != 0))
      }
      definitions.append(definition)
    }
  }
  public func encoded() throws -> [UInt8] {
    let length = 16 + definitions.count * 2 + definitions.reduce(0) { $0 + 4 + $1.events.count * 4 }
    guard definitions.count <= 255, length <= original.count else {
      throw S136Error.message("La memoria de macros está llena (\(original.count) bytes).")
    }
    var result = original
    func word(_ value: Int, at i: Int) {
      result[i] = UInt8(value & 255)
      result[i + 1] = UInt8(value >> 8)
    }
    result[0] = 0xaa
    result[1] = 0x55
    word(length, at: 2)
    word(definitions.count, at: 4)
    var offset = 16 + definitions.count * 2
    for (i, d) in definitions.enumerated() {
      word(offset, at: 16 + i * 2)
      word(d.events.count, at: offset)
      result.replaceSubrange(offset + 2..<offset + 4, with: d.reserved)
      for (j, event) in d.events.enumerated() {
        result.replaceSubrange(offset + 4 + j * 4..<offset + 8 + j * 4, with: event.bytes)
      }
      offset += 4 + d.events.count * 4
    }
    return result
  }
}
extension Snapshot {
  public mutating func appendMacro(
    events: [MacroEvent], to slot: Int, repetitions: Int = 1, replacing existingIndex: Int? = nil
  ) throws {
    guard (1...255).contains(repetitions), !events.isEmpty, let macroData else {
      throw S136Error.message("Configurá una secuencia y una repetición válida.")
    }
    var held = Set<Int>()
    for event in events {
      guard event.type <= 1, event.button != 0 else {
        throw S136Error.message("Sólo se admiten teclas y clics en las macros nuevas.")
      }
      let id = Int(event.type) * 256 + Int(event.button)
      if event.down {
        guard held.insert(id).inserted else {
          throw S136Error.message("Una tecla ya está presionada en la secuencia.")
        }
      } else {
        guard held.remove(id) != nil else {
          throw S136Error.message("Falta la pulsación antes de soltar una tecla.")
        }
      }
    }
    guard held.isEmpty else {
      throw S136Error.message("La secuencia debe soltar todas las teclas y botones.")
    }
    var table = try MacroTable(bytes: macroData)
    if let existingIndex, !table.definitions.indices.contains(existingIndex) {
      throw S136Error.message("La macro seleccionada ya no existe.")
    }
    let index = existingIndex ?? table.definitions.count
    guard index >= 0, index <= table.definitions.count, index < 255 else {
      throw S136Error.message("Se alcanzó el límite de macros.")
    }
    if let existingIndex {
      table.definitions[existingIndex].events = events
    } else {
      table.definitions.append(MacroDefinition(events: events))
    }
    let encoded = try table.encoded()
    try assign(0x710000 | index << 8 | repetitions, to: slot)
    self.macroData = encoded
  }
}
