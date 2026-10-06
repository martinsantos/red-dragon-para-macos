// SPDX-License-Identifier: MIT
import Combine
import Foundation
import RedragonCore

@MainActor
final class MicroStore: ObservableObject {
  @Published var skinEnabled: Bool { didSet { defaults.set(skinEnabled, forKey: "micro.skin") } }
  @Published var bindings: [MicroBinding] { didSet { persistBindings() } }
  @Published var selectedNumber = 1
  @Published var message = "Num 1–6 pueden ser chats o prefunciones."
  @Published var error: String?
  @Published var syncLights = false { didSet { if !preview { defaults.set(syncLights, forKey: "micro.syncLights") } } }
  @Published var bridgeAddress = "ws://127.0.0.1:4500"
  let bridge = MicroBridge()
  let router: LocalCodexRouter
  private let defaults: UserDefaults
  private let preview: Bool
  private let actions = CodexActions()
  private let hotkeys = MicroHotkeys()
  private var installedBindings: [MicroBinding] = []

  init(defaults: UserDefaults = .standard, preview: Bool = false) {
    self.defaults = defaults
    self.preview = preview
    syncLights = !preview && defaults.bool(forKey: "micro.syncLights")
    router = LocalCodexRouter(defaults: defaults, preview: preview)
    skinEnabled = preview || CommandLine.arguments.contains("--micro") || defaults.bool(forKey: "micro.skin")
    if let data = defaults.data(forKey: "micro.bindings"),
       let saved = try? JSONDecoder().decode([MicroBinding].self, from: data),
       (try? MicroBinding.validate(saved)) != nil {
      bindings = saved
    } else { bindings = MicroBinding.defaults }
    hotkeys.perform = { [weak self] number in
      guard let self, let binding = self.installedBindings.first(where: { $0.number == number }) else { return }
      self.perform(binding)
    }
    if let index = CommandLine.arguments.firstIndex(of: "--follow-codex"), index + 1 < CommandLine.arguments.count {
      router.attach(URL(fileURLWithPath: CommandLine.arguments[index + 1]), to: 1)
      bindings[0].title = "Este chat"
      bindings[0].action = .localChat
    }
    if !preview {
      defaults.set(skinEnabled, forKey: "micro.skin")
      persistBindings()
    }
  }

  private func persistBindings() {
    guard !preview, (try? MicroBinding.validate(bindings)) != nil,
          let data = try? JSONEncoder().encode(bindings) else { return }
    defaults.set(data, forKey: "micro.bindings")
  }
  func registerHardware(_ bindings: [MicroBinding]?) {
    installedBindings = bindings ?? []
    do { try hotkeys.register(numbers: installedBindings.filter { $0.action == .prompt || $0.action == .localChat }.map(\.number)) }
    catch { self.error = error.localizedDescription }
  }
  func perform(_ binding: MicroBinding) {
    do {
      switch binding.action {
      case .prompt: message = try actions.copyPrompt(binding.prompt)
      case .localChat: message = try actions.openChat(router.threadIDs[binding.number])
      case .recentChat: message = try actions.recentChat(binding.number)
      case .indicator: message = "Solo indicador: no se envió ninguna acción."
      }
    } catch { self.error = error.localizedDescription }
  }
  func command(key: UInt16, flags: UInt64, name: String) {
    do { message = try actions.shortcut(key: key, flags: .init(rawValue: flags), description: "Atajo \(name) enviado a Codex.") }
    catch { self.error = error.localizedDescription }
  }
  func openAccessibility() { actions.openAccessibility() }
  var selected: MicroBinding { bindings[selectedNumber - 1] }
  func state(for binding: MicroBinding) -> MicroState {
    if router.routes.contains(where: { $0.number == binding.number }) { return router.states[binding.number] ?? .disconnected }
    guard bridge.connected, !binding.threadID.isEmpty else { return .disconnected }
    return bridge.threads.first(where: { $0.id == binding.threadID })?.state ?? .disconnected
  }
  var hardwareStates: [MicroState] { bindings.map { state(for: $0) } }
}
