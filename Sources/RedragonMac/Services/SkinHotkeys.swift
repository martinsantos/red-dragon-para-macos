// SPDX-License-Identifier: MIT
import Carbon
import RedragonCore

@MainActor
final class SkinHotkeys {
  private var references: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?
  var next: (() -> Void)?
  var launch: ((Int) -> Void)?
  private let codes: [UInt32] = [UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4)]
  func register(launchers: Bool) throws {
    for reference in references { UnregisterEventHotKey(reference) }; references = []
    if handler == nil {
      var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == 0x5244534b else { return OSStatus(eventNotHandledErr) }
        let owner = Unmanaged<SkinHotkeys>.fromOpaque(context).takeUnretainedValue()
        let number = Int(id.id)
        Task { @MainActor in if number == 10 { owner.next?() } else { owner.launch?(number) } }
        return noErr
      }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
      guard result == noErr else { throw S136Error.message("No se pudieron preparar los atajos globales.") }
    }
    try add(code: UInt32(kVK_F4), modifiers: UInt32(cmdKey | optionKey), id: 10)
    if launchers {
      do { for i in 0..<4 { try add(code: codes[i], modifiers: 0, id: UInt32(i+1)) } }
      catch {
        // Never reserve only a subset while the UI says all four are available.
        for reference in references { UnregisterEventHotKey(reference) }; references = []
        try add(code: UInt32(kVK_F4), modifiers: UInt32(cmdKey | optionKey), id: 10)
        throw error
      }
    }
  }
  private func add(code: UInt32, modifiers: UInt32, id: UInt32) throws {
    var reference: EventHotKeyRef?
    let result = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x5244534b, id: id), GetApplicationEventTarget(), 0, &reference)
    guard result == noErr, let reference else { throw S136Error.message("El atajo \(id == 10 ? "⌘⌥F4" : "F\(id)") está ocupado por otra app. Desactivá ese atajo para usarlo aquí.") }
    references.append(reference)
  }
  deinit {
    for reference in references { UnregisterEventHotKey(reference) }
    if let handler { RemoveEventHandler(handler) }
  }
}
