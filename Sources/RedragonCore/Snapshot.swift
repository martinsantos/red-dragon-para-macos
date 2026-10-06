// SPDX-License-Identifier: MIT
import Foundation

public struct Snapshot: Codable, Sendable {
  public var endpoint: Endpoint
  public var capabilities: [UInt8]
  public var configuration: [UInt8]
  public var keymap: [UInt8]
  public var macroData: [UInt8]?
  public var customColors: [UInt8]?
  public var capturedAt: Date = Date()
  public init(
    endpoint: Endpoint, capabilities: [UInt8], configuration: [UInt8], keymap: [UInt8],
    macroData: [UInt8]? = nil, customColors: [UInt8]? = nil, capturedAt: Date = Date()
  ) {
    self.endpoint = endpoint
    self.capabilities = capabilities
    self.configuration = configuration
    self.keymap = keymap
    self.capturedAt = capturedAt
    self.macroData = macroData
    self.customColors = customColors
  }
  public func sameContents(as other: Snapshot) -> Bool {
    configuration == other.configuration && keymap == other.keymap && macroData == other.macroData
      && customColors == other.customColors
  }
  /// Validate imported data before any view or hardware writer indexes it.
  public func validateStructure() throws {
    guard capabilities.count == 34, capabilities[0] == 0xaa, capabilities[1] == 0x55,
      capabilities[6] == 24, configuration.count == 99, (0..<5).contains(profile),
      (isKeyboard && capabilities[4] == 6 && capabilities[5] == 128 && endpoint.productID == 0x50b8
        && endpoint.target == 1)
        || (!isKeyboard && capabilities[8] == 1 && capabilities[4] == 32 && capabilities[5] == 42
          && ((endpoint.productID == 0x2225 && endpoint.target == 0)
            || (endpoint.productID == 0x50b8 && endpoint.target == 2))),
      keymap.count == Int(capabilities[5]) * 3,
      macroData == nil || macroData?.count == 3072,
      customColors == nil || (isKeyboard && customColors?.count == keymap.count)
    else {
      throw S136Error.message(
        "El respaldo tiene una estructura inválida o una revisión de hardware desconocida.")
    }
  }

  /// Old backups without optional buffers retain the current device's buffers.
  public func preparedForRestore(on current: Snapshot) throws -> Snapshot {
    try validateStructure()
    try current.validateStructure()
    guard endpoint.productID == current.endpoint.productID,
      endpoint.target == current.endpoint.target,
      capabilities == current.capabilities, profile == current.profile
    else {
      throw S136Error.message("El respaldo no corresponde a este dispositivo, revisión y perfil.")
    }
    var restored = self
    restored.endpoint = current.endpoint
    restored.macroData = macroData ?? current.macroData
    restored.customColors = customColors ?? current.customColors
    return restored
  }
  public mutating func setKeyColor(_ rgb: [UInt8], at slot: Int) throws {
    guard isKeyboard, configuration.count == 99, rgb.count == 3, (0..<keyCount).contains(slot),
      var colors = customColors, colors.count == keymap.count
    else { throw S136Error.message("Paleta de colores no disponible.") }
    colors.replaceSubrange(slot * 3..<slot * 3 + 3, with: rgb)
    customColors = colors
    configuration[1] = 19
    configuration[22] = 0
  }
  public var isKeyboard: Bool { capabilities.count >= 9 && capabilities[8] == 2 }
  public var profile: Int { Int(configuration.first ?? 0) }
  public var keyCount: Int { keymap.count / 3 }
  public func assignment(at slot: Int) -> Int {
    let i = slot * 3
    guard i >= 0, i + 2 < keymap.count else { return 0 }
    return Int(keymap[i]) << 16 | Int(keymap[i + 1]) << 8 | Int(keymap[i + 2])
  }
  public mutating func assign(_ code: Int, to slot: Int) throws {
    guard (0..<keyCount).contains(slot), (0...0xffffff).contains(code) else {
      throw S136Error.message("Asignación inválida.")
    }
    if isKeyboard && slot == 74 { throw S136Error.message("Fn está reservada por el firmware.") }
    keymap.replaceSubrange(
      slot * 3..<slot * 3 + 3,
      with: [UInt8(code >> 16), UInt8((code >> 8) & 255), UInt8(code & 255)])
  }
  public mutating func setLighting(
    mode: Int, brightness: Int, speed: Int, rainbow: Bool, rgb: [UInt8]
  ) throws {
    guard configuration.count == 99, (isKeyboard ? 1...19 : 0...3).contains(mode),
      (0...4).contains(brightness), (0...4).contains(speed), rgb.count == 3
    else {
      throw S136Error.message("Ajustes de iluminación inválidos.")
    }
    configuration[1] = UInt8(mode)
    configuration[2] = UInt8(brightness)
    configuration[3] = UInt8(speed)
    configuration[5] = rainbow ? (isKeyboard ? 255 : 1) : 0
    configuration.replaceSubrange(6..<9, with: rgb)
  }
  public static let dpiPresets = [800: 6, 1200: 16, 1600: 26, 2400: 46, 7200: 96]
  public func dpi(at index: Int) -> Int {
    let start = 14 + index * 9
    guard !isKeyboard, (0..<5).contains(index), start + 5 < configuration.count else { return 0 }
    return Int(configuration[start + 4]) | Int(configuration[start + 5]) << 8
  }
  public mutating func setDPI(_ dpi: Int, at index: Int) throws {
    guard !isKeyboard, configuration.count == 99, (0..<5).contains(index),
      let code = Self.dpiPresets[dpi]
    else {
      throw S136Error.message("Elegí un nivel de DPI verificado para el M693.")
    }
    let start = 14 + index * 9
    configuration[start + 2] = UInt8(code)
    configuration[start + 3] = 0
    configuration[start + 4] = UInt8(dpi & 255)
    configuration[start + 5] = UInt8(dpi >> 8)
  }
}
