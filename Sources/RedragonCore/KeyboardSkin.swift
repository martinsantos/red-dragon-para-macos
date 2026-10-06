// SPDX-License-Identifier: MIT
import Foundation

public enum KeyboardSkin: String, Codable, CaseIterable, Sendable, Identifiable {
  case normal, codex, boca, music
  public var id: String { rawValue }
  public var title: String {
    switch self { case .normal: "Normal"; case .codex: "Codex Micro"; case .boca: "Boca"; case .music: "Música" }
  }
  public var next: Self {
    let all = Self.allCases
    return all[(all.firstIndex(of: self)! + 1) % all.count]
  }
}

/// Independent, temporary palettes. Never changes mappings, macros or persistent RGB.
public enum SkinPalette {
  public static let launcherColors: [[UInt8]] = [[40,220,160], [255,140,70], [80,140,255], [40,220,80]]
  public static func colors(for skin: KeyboardSkin, baseline: [UInt8], bands: [Float] = [], launchers: Bool) -> [UInt8] {
    var result = baseline.count == 384 ? baseline : [UInt8](repeating: 0, count: 384)
    if skin == .boca || skin == .music {
      for key in KeyboardLayout.keys {
        let rgb: [UInt8]
        if skin == .boca { rgb = key.row == 2 ? [255,190,0] : [0,45,220] }
        else {
          let band = bands.isEmpty ? 0 : min(bands.count - 1, Int(key.column / KeyboardLayout.columns * Double(bands.count)))
          let level = bands.isEmpty ? Float(0) : min(1, max(0, bands[band]))
          let height = Float(KeyboardLayout.rowCount - key.row) / Float(KeyboardLayout.rowCount)
          let intensity = level >= height - 0.18 ? level : 0
          rgb = [UInt8(220 * intensity * height), UInt8(210 * intensity * (1 - height)), UInt8(255 * intensity)]
        }
        result.replaceSubrange(key.slot * 3..<key.slot * 3 + 3, with: rgb)
      }
    }
    if launchers {
      for i in 0..<4 { result.replaceSubrange((i+1)*3..<(i+1)*3+3, with: launcherColors[i]) }
    }
    return result
  }
}

/// Enter the vendor's host-driven lighting mode once. Frames use volatile 0x12.
public enum LiveLightingProfile {
  public static func prepare(_ baseline: Snapshot) throws -> Snapshot {
    try baseline.validateStructure()
    guard baseline.isKeyboard, baseline.customColors != nil else { throw S136Error.message("Se requiere el K628 con su paleta leída.") }
    var value = baseline
    value.configuration[1] = 29
    if value.configuration[2] == 0 { value.configuration[2] = 4 }
    return value
  }
  public static func restore(baseline: Snapshot, installed: Snapshot, current: Snapshot) throws -> Snapshot {
    _ = try baseline.preparedForRestore(on: current)
    _ = try installed.preparedForRestore(on: current)
    let fields = [1, 2]
    guard fields.allSatisfy({ current.configuration[$0] == installed.configuration[$0] }) else {
      throw S136Error.message("El modo de iluminación cambió fuera de la app. Se conserva el respaldo para recuperarlo.")
    }
    var value = current
    for field in fields { value.configuration[field] = baseline.configuration[field] }
    return value
  }
}

/// FIFO keeps repeated 'next' presses relative to the queued target, not stale hardware.
public actor SkinRequestQueue {
  private struct Request { let target: KeyboardSkin; let continuation: CheckedContinuation<MicroControlResponse, Never> }
  private var requests: [Request] = []
  private var draining = false
  private let transition: @Sendable (KeyboardSkin) async -> MicroControlResponse
  public init(transition: @escaping @Sendable (KeyboardSkin) async -> MicroControlResponse) { self.transition = transition }
  public func submit(_ target: KeyboardSkin?, current: KeyboardSkin, toggleCodex: Bool = false, includeMusic: Bool = true) async -> MicroControlResponse {
    let previous = requests.last?.target ?? current
    var resolved = toggleCodex ? (previous == .codex ? KeyboardSkin.normal : .codex) : (target ?? previous.next)
    if target == nil && !toggleCodex && !includeMusic && resolved == .music { resolved = .normal }
    return await withCheckedContinuation { continuation in
      requests.append(.init(target: resolved, continuation: continuation))
      if !draining { draining = true; Task { await drain() } }
    }
  }
  public var pendingTargets: [KeyboardSkin] { requests.map(\.target) }
  private func drain() async {
    while let request = requests.first {
      let result = await transition(request.target)
      requests.removeFirst(); request.continuation.resume(returning: result)
    }
    draining = false
  }
}

/// Static skins write palette 1 once, using the ordinary custom-lighting mode.
public enum StaticLightingProfile {
  public static func prepare(_ baseline: Snapshot, skin: KeyboardSkin, launchers: Bool) throws -> Snapshot {
    try baseline.validateStructure()
    guard baseline.isKeyboard, let colors = baseline.customColors, skin == .boca else { throw S136Error.message("Elegí una skin estática compatible con el K628.") }
    var value = baseline
    value.customColors = SkinPalette.colors(for: skin, baseline: colors, launchers: launchers)
    value.configuration[1] = 19; value.configuration[22] = 0
    if value.configuration[2] == 0 { value.configuration[2] = 4 }
    return value
  }
  public static func restore(baseline: Snapshot, installed: Snapshot, current: Snapshot) throws -> Snapshot {
    _ = try baseline.preparedForRestore(on: current)
    _ = try installed.preparedForRestore(on: current)
    guard let previous = baseline.customColors, let sent = installed.customColors, var colors = current.customColors else { throw S136Error.message("Falta la paleta de recuperación.") }
    let fields = [1,2,22]
    guard fields.allSatisfy({ current.configuration[$0] == installed.configuration[$0] }),
      KeyboardLayout.keys.allSatisfy({ Array(colors[$0.slot*3..<$0.slot*3+3]) == Array(sent[$0.slot*3..<$0.slot*3+3]) }) else {
      throw S136Error.message("La skin cambió fuera de la app. Se conserva su respaldo.")
    }
    var result = current
    for field in fields { result.configuration[field] = baseline.configuration[field] }
    for key in KeyboardLayout.keys { colors.replaceSubrange(key.slot*3..<key.slot*3+3, with: previous[key.slot*3..<key.slot*3+3]) }
    result.customColors = colors
    return result
  }
}
