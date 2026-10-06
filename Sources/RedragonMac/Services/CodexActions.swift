// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices

@MainActor
struct CodexActions {
  // Resolve the installed app through Launch Services; no hard-coded application path.
  private func application() -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first {
      let name = ($0.localizedName ?? "").lowercased()
      return $0.bundleIdentifier == "com.openai.codex" || name == "codex" || name == "chatgpt"
    }
  }

  func openChat(_ id: String?) throws -> String {
    guard let id, let uuid = UUID(uuidString: id),
          let url = URL(string: "codex://threads/\(uuid.uuidString.lowercased())"),
          NSWorkspace.shared.open(url) else {
      throw NSError(domain: "MicroAction", code: 4, userInfo: [NSLocalizedDescriptionKey:
        "Conectá un registro local de Codex a esta tecla antes de abrir el chat."])
    }
    return "Se pidió abrir el chat conectado en Codex."
  }

  func copyPrompt(_ prompt: String) throws -> String {
    guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw NSError(domain: "MicroAction", code: 1, userInfo: [NSLocalizedDescriptionKey: "Escribí la prefunción primero."])
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(prompt, forType: .string)
    application()?.activate(options: [])
    return "Prefunción copiada. Pegala con ⌘V en el chat que elijas."
  }

  func recentChat(_ number: Int) throws -> String {
    let keys: [CGKeyCode] = [18, 19, 20, 21, 23, 22]
    guard (1...6).contains(number) else { return "" }
    return try shortcut(key: keys[number - 1], flags: [.maskCommand, .maskAlternate],
                        description: "Atajo al chat reciente \(number) enviado a Codex.")
  }

  func shortcut(key: CGKeyCode, flags: CGEventFlags, description: String) throws -> String {
    guard let app = application() else {
      throw NSError(domain: "MicroAction", code: 2, userInfo: [NSLocalizedDescriptionKey: "Abrí Codex o ChatGPT antes de usar este botón."])
    }
    guard AXIsProcessTrusted() else {
      throw NSError(domain: "MicroAction", code: 3, userInfo: [NSLocalizedDescriptionKey:
        "Los botones en pantalla necesitan Accesibilidad para enviar atajos a Codex. Las teclas físicas de chat funcionan sin ese permiso."])
    }
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else { return "No se pudo crear el atajo." }
    down.flags = flags
    up.flags = flags
    app.activate(options: [])
    // Deliver only to the chosen app, never to whichever app happens to gain focus.
    down.postToPid(app.processIdentifier)
    up.postToPid(app.processIdentifier)
    return description
  }

  func openAccessibility() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }
}
