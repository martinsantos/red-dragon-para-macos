// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import Combine
import RedragonCore

struct AppLauncher: Codable, Identifiable {
  var number: Int
  var title: String
  var bundleID: String
  var id: Int { number }
  static let defaults: [Self] = [
    .init(number: 1, title: "Codex", bundleID: "com.openai.codex"),
    .init(number: 2, title: "Claude", bundleID: "com.anthropic.claudefordesktop"),
    .init(number: 3, title: "Chrome · siguiente ventana", bundleID: "com.google.Chrome"),
    .init(number: 4, title: "WhatsApp", bundleID: "net.whatsapp.WhatsApp")]
}

/// Focuses existing apps without opening a new chat. Window references stay in RAM.
@MainActor
final class AppLaunchers: ObservableObject {
  @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "skins.launchers.enabled"); changed?() } }
  @Published private(set) var bindings: [AppLauncher]
  @Published private(set) var message = "F1 Codex · F2 Claude · F3 Chrome · F4 WhatsApp"
  var changed: (() -> Void)?
  private let defaults: UserDefaults
  private var lastWindows: [String: AXUIElement] = [:]
  private var observer: NSObjectProtocol?
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    enabled = defaults.object(forKey: "skins.launchers.enabled") as? Bool ?? true
    if let data = defaults.data(forKey: "skins.launchers.bindings"),
       let values = try? JSONDecoder().decode([AppLauncher].self, from: data),
       values.map(\.number) == Array(1...4), values.allSatisfy({ !$0.bundleID.isEmpty && $0.bundleID.count < 256 }) {
      bindings = values
    } else { bindings = AppLauncher.defaults }
    observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification,
      object: nil, queue: .main) { [weak self] notification in
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        Task { @MainActor in self?.remember(app) }
      }
  }
  var accessibilityAllowed: Bool { AXIsProcessTrusted() }
  func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }
  func choose(_ number: Int) {
    let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
    panel.message = "Elegí la app para F\(number)."; panel.prompt = "Asignar"
    guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
      let identifier = bundle.bundleIdentifier, let index = bindings.firstIndex(where: { $0.number == number }) else { return }
    bindings[index] = .init(number: number, title: url.deletingPathExtension().lastPathComponent, bundleID: identifier)
    save()
  }
  func reset() { bindings = AppLauncher.defaults; save() }
  private func save() { if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: "skins.launchers.bindings") }; changed?() }
  private func remember(_ app: NSRunningApplication) {
    guard accessibilityAllowed, let id = app.bundleIdentifier, bindings.contains(where: { $0.bundleID == id }),
      let window = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) else { return }
    lastWindows[id] = (window as! AXUIElement)
  }
  func launch(_ number: Int) async throws {
    guard enabled, let binding = bindings.first(where: { $0.number == number }) else {
      throw S136Error.message("Activá los accesos F1–F4 en Skins.")
    }
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: binding.bundleID).first {
      if number == 3 && binding.bundleID == "com.google.Chrome" {
        guard accessibilityAllowed else {
          app.activate(options: [])
          message = "Chrome abierto. Para recorrer sus ventanas, habilitá Accesibilidad."
          return
        }
        try cycleChrome(app)
      } else {
        app.activate(options: [])
        if accessibilityAllowed, let window = lastWindows[binding.bundleID] {
          AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
          AXUIElementPerformAction(window, kAXRaiseAction as CFString)
          AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString, window)
        }
      }
      message = "F\(number) · \(binding.title) · ventana anterior"
      return
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID) else {
      throw S136Error.message("Instalá \(binding.title) o asigná otra app a F\(number).")
    }
    let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
    _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    message = "F\(number) · \(binding.title) abierto. La app decide qué ventana recupera al iniciarse."
  }
  private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
  }
  private func cycleChrome(_ app: NSRunningApplication) throws {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    guard let all = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else {
      throw S136Error.message("Chrome no permite leer sus ventanas. Revisá Accesibilidad.")
    }
    let windows = all.filter { (attribute($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole }
    guard !windows.isEmpty else { app.activate(options: []); return }
    let current = lastWindows[app.bundleIdentifier ?? ""] ?? (attribute(element, kAXFocusedWindowAttribute).map { $0 as! AXUIElement })
    let index = current.flatMap { selected in windows.firstIndex { CFEqual(selected, $0) } }
    let next = windows[index.map { ($0+1) % windows.count } ?? 0]
    app.activate(options: [])
    AXUIElementSetAttributeValue(next, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    guard AXUIElementPerformAction(next, kAXRaiseAction as CFString) == .success else { throw S136Error.message("No se pudo mostrar esa ventana de Chrome.") }
    AXUIElementSetAttributeValue(element, kAXFocusedWindowAttribute as CFString, next)
    lastWindows[app.bundleIdentifier ?? ""] = next
  }
  deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
}
