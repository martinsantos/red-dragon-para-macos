// SPDX-License-Identifier: MIT
import Foundation

/// One baseline for the whole skin session. Switching skins never installs Normal first.
public struct KeyboardSkinSession: Codable, Sendable {
  public var baseline: Snapshot
  public var installed: Snapshot
  public var skin: KeyboardSkin
  public var launcherColors: Bool
  public var bindings: [MicroBinding]
  public var launcherKeys: Bool? = nil
  public var controlPad: Bool? = nil
  public var chatPad: Bool? = nil
  public init(baseline: Snapshot, installed: Snapshot, skin: KeyboardSkin,
              launcherColors: Bool = false, bindings: [MicroBinding] = MicroBinding.defaults) {
    self.baseline = baseline; self.installed = installed; self.skin = skin
    self.launcherColors = launcherColors; self.bindings = bindings
  }
  public func validate() throws {
    _ = try baseline.preparedForRestore(on: installed)
    try MicroBinding.validate(bindings)
    guard baseline.isKeyboard, skin != .normal else { throw S136Error.message("Sesión de skin inválida.") }
  }
  public func restored(on current: Snapshot) throws -> Snapshot {
    try validate()
    let before = try baseline.preparedForRestore(on: current)
    let sent = try installed.preparedForRestore(on: current)
    // A failed first activation may already have rolled back to the baseline.
    if current.sameContents(as: before) { return current }
    var restored: Snapshot
    switch skin {
    case .codex:
      if controlPad == true {
        let unmapped = try ApplicationControlProfile.restorePad(baseline: before, installed: sent, current: current)
        restored = try StaticLightingProfile.restore(baseline: before, installed: sent, current: current)
        restored.keymap = unmapped.keymap
      } else { restored = try CodexMicroProfile.restore(baseline: before, installed: sent, current: current, launcherColors: launcherColors) }
    case .apps, .claude, .boca:
      restored = try StaticLightingProfile.restore(baseline: before, installed: sent, current: current)
      if controlPad == true {
        let unmapped = try ApplicationControlProfile.restorePad(baseline: before, installed: sent, current: current)
        restored.keymap = unmapped.keymap
      }
    case .music:
      restored = try LiveLightingProfile.restore(baseline: before, installed: sent, current: current)
    case .normal: throw S136Error.message("Normal no necesita una sesión de skin.")
    }
    if launcherKeys == true {
      let unmapped = try ApplicationControlProfile.restoreLaunchers(baseline: before, installed: sent, current: current)
      for slot in ApplicationControlProfile.launcherSlots { try restored.assign(unmapped.assignment(at: slot), to: slot) }
    }
    return restored
  }
  public static func plan(_ target: KeyboardSkin, from previous: Self?, current: Snapshot,
                          bindings: [MicroBinding], states: [MicroState]?, launchers: Bool,
                          controlPad: Bool = false, launcherKeys: Bool = false,
                          chatPad: Bool = false) throws -> (snapshot: Snapshot, session: Self?) {
    let baseline = try previous?.restored(on: current) ?? current
    if target == .normal { return (baseline, nil) }
    var planned: Snapshot
    switch target {
    case .codex:
      if controlPad {
        planned = try StaticLightingProfile.prepare(baseline, skin: target, launchers: launchers)
        if chatPad {
          planned = try CodexMicroProfile.prepare(planned, bindings: bindings, launcherColors: launchers)
          if let states { planned = try CodexMicroProfile.withStates(states, on: planned) }
        }
        planned = try ApplicationControlProfile.preparePad(on: planned, preserveColors: chatPad)
      } else {
        planned = try CodexMicroProfile.prepare(baseline, bindings: bindings, launcherColors: launchers)
        if let states { planned = try CodexMicroProfile.withStates(states, on: planned) }
      }
    case .apps, .claude, .boca:
      planned = try StaticLightingProfile.prepare(baseline, skin: target, launchers: launchers)
      if target == .claude { planned = try ApplicationControlProfile.preparePad(on: planned) }
    case .music: planned = try LiveLightingProfile.prepare(baseline)
    case .normal: planned = baseline
    }
    if launcherKeys && launchers { planned = try ApplicationControlProfile.prepareLaunchers(on: planned) }
    var session = Self(baseline: baseline, installed: planned, skin: target, launcherColors: launchers, bindings: bindings)
    session.controlPad = target == .claude || (target == .codex && controlPad)
    session.launcherKeys = launcherKeys && launchers
    session.chatPad = target == .codex && chatPad
    return (planned, session)
  }
}

/// Saved before a write. A restart can distinguish the old skin from a committed new one.
public struct SkinTransitionJournal: Codable, Sendable {
  public let previous: KeyboardSkinSession?
  public let proposed: KeyboardSkinSession?
  public let before: Snapshot
  public let after: Snapshot
  public init(previous: KeyboardSkinSession?, proposed: KeyboardSkinSession?, before: Snapshot, after: Snapshot) {
    self.previous = previous; self.proposed = proposed; self.before = before; self.after = after
  }
  public func resolved(on current: Snapshot) throws -> KeyboardSkinSession? {
    _ = try before.preparedForRestore(on: current)
    _ = try after.preparedForRestore(on: current)
    if current.sameContents(as: after) { return proposed }
    if current.sameContents(as: before) { return previous }
    throw S136Error.message("La transición se interrumpió y el teclado no coincide con ninguna copia verificada. Se conserva el respaldo; reconectá el teclado antes de recuperar sus ajustes.")
  }
}
