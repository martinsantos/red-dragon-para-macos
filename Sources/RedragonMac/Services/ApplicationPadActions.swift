// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import RedragonCore

/// Actions target the chosen application, never a random text field or approval.
@MainActor
struct ApplicationPadActions {
  func perform(_ action: ApplicationPadAction, skin: KeyboardSkin) async throws -> String {
    let claude = skin == .claude
    let bundleID = claude ? "com.anthropic.claudefordesktop" : "com.openai.codex"
    let name = claude ? "Claude" : "Codex"
    if action == .usage {
      let address = claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/settings/usage"
      guard NSWorkspace.shared.open(URL(string: address)!) else { throw S136Error.message("No se pudo abrir Uso de \(name).") }
      return "Uso de \(name) abierto en su panel oficial."
    }
    let app = try await ApplicationFocus.focus(bundleID, title: name)
    guard AXIsProcessTrusted() else { throw S136Error.message("Habilitá Accesibilidad para usar las funciones de \(name).") }
    if !claude && action == .dictation {
      let pressed = pressControl(app, matches: { label in
        let value = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["dictate", "dictar", "start dictation", "iniciar dictado", "voice input", "entrada de voz"].contains(value)
          || value.hasPrefix("dictate (") || value.hasPrefix("dictar (")
      })
      if pressed { return "Se activó el control Dictar de Codex." }
      guard focusEditor(app) else { throw S136Error.message("Codex no mostró Dictar ni un editor de mensaje identificable. No se envió el atajo a otro campo.") }
      try await Task.sleep(for: .milliseconds(75))
      // The native dictation shortcut requires the composer, not just the app, focused.
    }
    if claude && action == .model {
      guard pressControl(app, matches: { label in
        let value = label.lowercased()
        return value == "choose model" || value == "select model" || value == "seleccionar modelo"
          || value == "elegir modelo" || value.hasPrefix("model:") || value.hasPrefix("modelo:")
          || value.contains("claude sonnet") || value.contains("claude opus") || value.contains("claude fable")
      }) else { throw S136Error.message("No se encontró el selector de modelo de Claude. Abrí un chat; se conserva tu selección.") }
      return "Selector de modelo de Claude abierto."
    }
    if claude && action == .dictation {
      // Claude Code exposes a hold-to-record control, which cannot be truthfully
      // represented as a toggle. Open its native setup instead of pulsing Caps Lock.
      guard pressControl(app, matches: { label in
        ["dictation settings", "configuración de dictado", "voice settings"].contains(label.lowercased())
      }) else { throw S136Error.message("Claude no expone la configuración de dictado en esta ventana. Revisá Settings → General → Desktop app.") }
      return "Configuración de dictado de Claude abierta; usá su control nativo para grabar."
    }
    let key: CGKeyCode
    let flags: CGEventFlags
    switch action {
    case .attention: key = 0; flags = [.maskCommand, .maskAlternate] // ⌘⌥A
    case .dictation: key = 2; flags = [.maskControl, .maskShift] // ⌃⇧D
    case .model: key = 46; flags = [.maskControl, .maskShift] // ⌃⇧M
    case .review: key = 5; flags = [.maskControl, .maskShift] // ⌃⇧G
    case .newChat: key = 45; flags = [.maskCommand] // ⌘N
    case .search: key = 40; flags = [.maskCommand] // ⌘K
    case .settings: key = 43; flags = [.maskCommand] // ⌘,
    case .usage: return ""
    }
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
      throw S136Error.message("No se pudo preparar el acceso de \(name).")
    }
    down.flags = flags; up.flags = flags
    down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
    return "\(name) · \(action.title)."
  }
  private func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
  }
  private func pressControl(_ app: NSRunningApplication, matches: (String) -> Bool) -> Bool {
    let application = AXUIElementCreateApplication(app.processIdentifier)
    guard let window = attribute(application, kAXFocusedWindowAttribute) else { return false }
    var stack = [window as! AXUIElement]
    var count = 0
    while let node = stack.popLast(), count < 2000 {
      count += 1
      let role = attribute(node, kAXRoleAttribute) as? String ?? ""
      if [kAXButtonRole, kAXPopUpButtonRole, kAXMenuButtonRole].contains(role),
         (attribute(node, kAXEnabledAttribute) as? Bool) != false {
        let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { attribute(node, $0) as? String }
        if labels.contains(where: matches), AXUIElementPerformAction(node, kAXPressAction as CFString) == .success { return true }
      }
      // Read structure and control labels only; never retrieve chat text or input values.
      if [kAXStaticTextRole, kAXTextAreaRole, kAXTextFieldRole].contains(role) { continue }
      // Visit bottom controls before potentially long message lists.
      if let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] { stack += children.suffix(max(0, 2000-stack.count)) }
    }
    return false
  }
  private func focusEditor(_ app: NSRunningApplication) -> Bool {
    let application = AXUIElementCreateApplication(app.processIdentifier)
    guard let window = attribute(application, kAXFocusedWindowAttribute) else { return false }
    var stack = [window as! AXUIElement], editors: [AXUIElement] = []
    var visited = 0
    while let node = stack.popLast(), visited < 2000 {
      visited += 1
      let role = attribute(node, kAXRoleAttribute) as? String ?? ""
      if role == kAXTextAreaRole {
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(node, kAXFocusedAttribute as CFString, &settable) == .success, settable.boolValue {
          editors.append(node)
        }
        continue
      }
      if [kAXStaticTextRole, kAXTextFieldRole].contains(role) { continue }
      if let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] { stack += children.suffix(max(0, 2000-stack.count)) }
    }
    // Refuse ambiguous editors, such as a browser beside the chat composer.
    guard editors.count == 1, let editor = editors.first,
      AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
      let focused = attribute(application, kAXFocusedUIElementAttribute), CFEqual(focused, editor) else { return false }
    return true
  }
}
