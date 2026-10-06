// SPDX-License-Identifier: MIT
import Carbon
import Foundation

/// Reserve only the keypad keys assigned to app actions while Micro is active.
/// No keystroke log or event tap. Applies to keypads on all connected keyboards.
@MainActor
final class MicroHotkeys {
  private var refs: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?
  var perform: ((Int) -> Void)?
  private static let keyCodes: [UInt32] = [83, 84, 85, 86, 87, 88] // macOS Num 1…6

  init() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
      guard let event, let context else { return OSStatus(eventNotHandledErr) }
      var id = EventHotKeyID()
      let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &id)
      guard result == noErr else { return result }
      guard id.signature == 0x52444d43 else { return OSStatus(eventNotHandledErr) }
      let owner = Unmanaged<MicroHotkeys>.fromOpaque(context).takeUnretainedValue()
      let number = Int(id.id)
      Task { @MainActor in owner.perform?(number) }
      return noErr
    }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }

  func register(numbers: [Int]) throws {
    unregister()
    for number in numbers {
      guard (1...6).contains(number) else { continue }
      var ref: EventHotKeyRef?
      let result = RegisterEventHotKey(Self.keyCodes[number - 1], 0,
                                      EventHotKeyID(signature: 0x52444d43, id: UInt32(number)),
                                      GetApplicationEventTarget(), 0, &ref)
      guard result == noErr, let ref else {
        unregister()
        throw NSError(domain: "MicroHotkeys", code: Int(result), userInfo: [NSLocalizedDescriptionKey:
          "Otra app está usando Num \(number). Cerrala o usá el botón de la skin."])
      }
      refs.append(ref)
    }
  }
  func unregister() {
    refs.forEach { UnregisterEventHotKey($0) }
    refs = []
  }
  deinit {
    refs.forEach { UnregisterEventHotKey($0) }
    if let handler { RemoveEventHandler(handler) }
  }
}
