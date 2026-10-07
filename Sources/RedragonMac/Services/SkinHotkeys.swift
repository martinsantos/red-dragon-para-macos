// SPDX-License-Identifier: MIT
import Carbon
import RedragonCore

@MainActor
final class SkinHotkeys {
  private var references: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?
  var next: (() -> Void)?
  var launch: ((Int) -> Void)?
  var pad: ((Int) -> Void)?
  private(set) var launcherRegistered = false
  private(set) var padRegistered = false
  private(set) var shortcutRegistered = false
  private let codes: [UInt32] = [UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4)]
  func register(launchers: Bool, actionPad: Bool = false) throws {
    for reference in references { UnregisterEventHotKey(reference) }; references = []
    launcherRegistered = false; padRegistered = false; shortcutRegistered = false
    if handler == nil {
      var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == 0x5244534b else { return OSStatus(eventNotHandledErr) }
        let owner = Unmanaged<SkinHotkeys>.fromOpaque(context).takeUnretainedValue()
        let number = Int(id.id)
        Task { @MainActor in
          if number == 10 { owner.next?() }
          else if (20..<26).contains(number) { owner.pad?(number - 19) }
          else { owner.launch?(number) }
        }
        return noErr
      }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
      guard result == noErr else { throw S136Error.message("No se pudieron preparar los atajos globales.") }
    }
    // Register app actions independently, so a Spotlight conflict cannot disable 1–4.
    var shortcutError: Error?
    do { try add(code: UInt32(kVK_Space), modifiers: UInt32(cmdKey), id: 10); shortcutRegistered = true }
    catch { shortcutError = error }
    do {
      if launchers { for i in 0..<4 { try add(code: codes[i], modifiers: 0, id: UInt32(i+1)) } }
      if actionPad {
        let padCodes: [UInt32] = [UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8), UInt32(kVK_F9), UInt32(kVK_F10)]
        for i in 0..<6 { try add(code: padCodes[i], modifiers: 0, id: UInt32(i+20)) }
      }
      launcherRegistered = launchers; padRegistered = actionPad
    } catch {
      for reference in references { UnregisterEventHotKey(reference) }; references = []
      launcherRegistered = false; padRegistered = false; shortcutRegistered = false
      if (try? add(code: UInt32(kVK_Space), modifiers: UInt32(cmdKey), id: 10)) != nil { shortcutRegistered = true }
      throw error
    }
    if let shortcutError { throw shortcutError }
  }
  private func add(code: UInt32, modifiers: UInt32, id: UInt32) throws {
    var reference: EventHotKeyRef?
    let result = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x5244534b, id: id), GetApplicationEventTarget(), 0, &reference)
    guard result == noErr, let reference else { throw S136Error.message(id == 10
      ? "⌘Espacio está ocupado. Desactivá Mostrar búsqueda Spotlight en los atajos de macOS y pulsá Reintentar atajo."
      : "Otra app reservó un acceso del teclado (F\(id >= 20 ? id-15 : id)). No se activaron parcialmente los accesos.") }
    references.append(reference)
  }
  deinit {
    for reference in references { UnregisterEventHotKey(reference) }
    if let handler { RemoveEventHandler(handler) }
  }
}
