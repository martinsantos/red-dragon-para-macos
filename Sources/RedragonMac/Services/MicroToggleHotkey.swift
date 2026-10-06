// SPDX-License-Identifier: MIT
import Carbon
import Foundation
import RedragonCore

@MainActor
final class MicroToggleHotkey {
  private var reference: EventHotKeyRef?
  private var handler: EventHandlerRef?
  var perform: (() -> Void)?

  func register() throws {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
      guard let event, let context else { return OSStatus(eventNotHandledErr) }
      var id = EventHotKeyID()
      let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &id)
      guard result == noErr, id.signature == 0x52444d54, id.id == 1 else {
        return OSStatus(eventNotHandledErr)
      }
      let owner = Unmanaged<MicroToggleHotkey>.fromOpaque(context).takeUnretainedValue()
      Task { @MainActor in owner.perform?() }
      return noErr
    }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    guard installed == noErr else { throw S136Error.message("No se pudo preparar el atajo de modo Codex.") }
    let result = RegisterEventHotKey(8, UInt32(controlKey | optionKey | cmdKey),
                                    EventHotKeyID(signature: 0x52444d54, id: 1),
                                    GetApplicationEventTarget(), 0, &reference)
    guard result == noErr else {
      throw S136Error.message("Otra app usa ⌃⌥⌘C. Podés activar Micro desde el menú Codex o con comandos.")
    }
  }
  deinit {
    if let reference { UnregisterEventHotKey(reference) }
    if let handler { RemoveEventHandler(handler) }
  }
}
