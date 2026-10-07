// SPDX-License-Identifier: MIT
import Foundation

public enum KeyboardSkin: String, Codable, CaseIterable, Sendable, Identifiable {
  case normal, apps, codex, claude, boca, music
  public var id: String { rawValue }
  public var title: String {
    switch self { case .normal: "Normal"; case .apps: "Apps"; case .codex: "Codex"; case .claude: "Claude"; case .boca: "Boca"; case .music: "Música" }
  }
  public var hasActionPad: Bool { self == .codex || self == .claude }
  public var next: Self {
    let all = Self.allCases
    return all[(all.firstIndex(of: self)! + 1) % all.count]
  }
}

/// Independent, temporary palettes. Never changes mappings, macros or persistent RGB.
public enum SkinPalette {
  public static let launcherColors: [[UInt8]] = [[30,110,255], [255,140,70], [155,90,255], [40,220,80]]
  public static func colors(for skin: KeyboardSkin, baseline: [UInt8], bands: [Float] = [], launchers: Bool) -> [UInt8] {
    var result = baseline.count == 384 ? baseline : [UInt8](repeating: 0, count: 384)
    if [.apps, .codex, .claude, .boca, .music].contains(skin) {
      for key in KeyboardLayout.keys {
        let rgb: [UInt8]
        if skin == .boca { rgb = key.row == 2 ? [255,190,0] : [0,45,220] }
        else if skin == .apps { rgb = [12,12,18] }
        else if skin == .codex { rgb = [4,15,38] }
        else if skin == .claude { rgb = [35,15,5] }
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
    if skin.hasActionPad {
      for index in 0..<6 {
        let slot = CodexMicroProfile.slots[index]
        result.replaceSubrange(slot*3..<slot*3+3, with: ApplicationControlProfile.padColors[index])
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
  public static let refreshOffset = (0..<128).first { slot in !KeyboardLayout.keys.contains { $0.slot == slot } }! * 3
  public static func prepare(_ baseline: Snapshot) throws -> Snapshot {
    try baseline.validateStructure()
    guard baseline.isKeyboard, baseline.customColors != nil else { throw S136Error.message("Se requiere el K628 con su paleta leída.") }
    var value = baseline
    // Vendor UI effects 29/30 serialize as firmware mode FE (0x4964a3…0x4964bb).
    value.configuration[1] = 0xfe
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

/// Finish the in-flight write, then apply the latest intent. Obsolete selections share
/// the result of the final selection; no hardware transactions run concurrently.
public actor SkinRequestQueue {
  private var waiting: [CheckedContinuation<MicroControlResponse, Never>] = []
  private var queued: KeyboardSkin?
  private var inFlight: KeyboardSkin?
  private var draining = false
  private let transition: @Sendable (KeyboardSkin) async -> MicroControlResponse
  private let changed: @Sendable (KeyboardSkin?) async -> Void
  public init(transition: @escaping @Sendable (KeyboardSkin) async -> MicroControlResponse,
              changed: @escaping @Sendable (KeyboardSkin?) async -> Void = { _ in }) {
    self.transition = transition; self.changed = changed
  }
  public func submit(_ target: KeyboardSkin?, current: KeyboardSkin, toggleCodex: Bool = false, includeMusic: Bool = true) async -> MicroControlResponse {
    let previous = queued ?? inFlight ?? current
    var resolved = toggleCodex ? (previous == .codex ? KeyboardSkin.normal : .codex) : (target ?? previous.next)
    if target == nil && !toggleCodex && !includeMusic && resolved == .music { resolved = .normal }
    return await withCheckedContinuation { continuation in
      queued = resolved; waiting.append(continuation)
      if !draining { draining = true; Task { await drain() } }
      else { Task { await changed(resolved) } }
    }
  }
  public var pendingTargets: [KeyboardSkin] { [inFlight, queued].compactMap { $0 } }
  private func drain() async {
    while let target = queued {
      let continuations = waiting; waiting = []; queued = nil; inFlight = target
      await changed(target)
      let result = await transition(target)
      inFlight = nil
      var status = result.status
      status.busy = queued != nil; status.requestedSkin = queued?.rawValue
      for continuation in continuations { continuation.resume(returning: .init(ok: result.ok, status: status, error: result.error)) }
    }
    draining = false
    await changed(nil)
  }
}

/// Static skins write palette 1 once, using the ordinary custom-lighting mode.
public enum StaticLightingProfile {
  public static func prepare(_ baseline: Snapshot, skin: KeyboardSkin, launchers: Bool) throws -> Snapshot {
    try baseline.validateStructure()
    guard baseline.isKeyboard, let colors = baseline.customColors, [.apps, .codex, .claude, .boca].contains(skin) else { throw S136Error.message("Elegí una skin estática compatible con el K628.") }
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
