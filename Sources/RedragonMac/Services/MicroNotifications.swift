// SPDX-License-Identifier: MIT
import Combine
import Foundation
import UserNotifications

@MainActor
final class MicroNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  @Published private(set) var permissionMessage = "Activá los avisos para permitir notificaciones de macOS."
  var activate: (() -> Void)?
  var show: (() -> Void)?
  private var allowed = false
  private let center: UNUserNotificationCenter?

  override init() {
    center = Bundle.main.bundleIdentifier == nil ? nil : .current()
    super.init()
    center?.delegate = self
    let action = UNNotificationAction(identifier: "MICRO_ON", title: "Activar Codex Micro", options: [.foreground])
    center?.setNotificationCategories([UNNotificationCategory(identifier: "CODEX_ATTENTION", actions: [action], intentIdentifiers: [])])
    Task { await refreshPermission() }
  }
  func enable() async {
    guard let center else { return }
    do {
      _ = try await center.requestAuthorization(options: [.alert, .sound])
      await refreshPermission()
    } catch { permissionMessage = "No se pudieron habilitar los avisos: \(error.localizedDescription)" }
  }
  private func refreshPermission() async {
    guard let settings = await center?.notificationSettings() else { return }
    allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    permissionMessage = allowed ? "Avisos permitidos por macOS." : "Permití los avisos de esta app en Ajustes del Sistema → Notificaciones."
  }
  func attention(number: Int) {
    guard allowed, let center else { return }
    let content = UNMutableNotificationContent()
    content.title = "Codex necesita tu respuesta"
    content.body = "El chat conectado a Num \(number) registró una pregunta. Podés activar Codex Micro desde este aviso o con ⌃⌥⌘C."
    content.categoryIdentifier = "CODEX_ATTENTION"
    content.sound = .default
    Task {
      try? await center.add(UNNotificationRequest(identifier: "micro-attention-\(number)", content: content, trigger: nil))
    }
  }
  func skinChanged(_ name: String) {
    guard allowed, let center else { return }
    let content = UNMutableNotificationContent(); content.title = "Skin: \(name)"
    content.body = "⌘⌥F4 para cambiar de skin."
    Task { try? await center.add(UNNotificationRequest(identifier: "skin-changed", content: content, trigger: nil)) }
  }
  func clear(_ numbers: [Int]) {
    center?.removeDeliveredNotifications(withIdentifiers: numbers.map { "micro-attention-\($0)" })
  }
  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }

  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse) async {
    await MainActor.run {
      if response.actionIdentifier == "MICRO_ON" { activate?() }
      else if response.actionIdentifier == UNNotificationDefaultActionIdentifier { show?() }
    }
  }
}
