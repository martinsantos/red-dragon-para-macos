// SPDX-License-Identifier: MIT
import AppKit
import Combine
import RedragonCore

/// One activation/restoration path for buttons, global shortcut, notifications and CLI.
@MainActor
final class MicroModeController: ObservableObject {
  let store: DeviceStore
  let micro: MicroStore
  let notifications: MicroNotifications
  @Published private(set) var transitioning = false
  @Published private(set) var shortcutMessage = "Atajo global: ⌃⌥⌘C"
  @Published private(set) var commandMessage = "Comandos: micro on / off / status"
  @Published private(set) var attentionNumbers: [Int] = []
  @Published var noticesEnabled: Bool {
    didSet {
      guard !store.previewMode else { return }
      defaults.set(noticesEnabled, forKey: "micro.notices")
      if noticesEnabled { Task { await notifications.enable() } }
      else { notifications.clear(Array(1...6)); attentionNumbers = [] }
    }
  }
  private let defaults: UserDefaults
  private let shortcut = MicroToggleHotkey()
  private var server: MicroControlServer?
  private var tracker = MicroAttentionTracker()
  private var subscriptions: Set<AnyCancellable> = []
  private var started = false

  init(defaults: UserDefaults = .standard, arguments: [String] = CommandLine.arguments) {
    self.defaults = defaults
    store = DeviceStore(arguments: arguments)
    micro = MicroStore(defaults: defaults, preview: arguments.contains("--preview") || arguments.contains("--micro-preview"))
    notifications = MicroNotifications()
    noticesEnabled = !store.previewMode && defaults.bool(forKey: "micro.notices")
  }
  func start() {
    guard !started else { return }
    started = true
    if store.microRecovery != nil { micro.skinEnabled = true }
    shortcut.perform = { [weak self] in self?.perform(.toggle) }
    notifications.activate = { [weak self] in self?.perform(.on) }
    notifications.show = { [weak self] in self?.perform(.show) }
    if !store.previewMode {
      do { try shortcut.register() }
      catch { shortcutMessage = error.localizedDescription }
    }
    let channel = MicroControlServer { [weak self] command in
      guard let self else {
        return MicroControlResponse(ok: false, status: .init(hardwareActive: false,
          recoveryPending: false, skinVisible: false, busy: false, message: "App cerrada."), error: "App cerrada.")
      }
      return await self.execute(command)
    }
    do { try channel.start(); server = channel }
    catch { commandMessage = error.localizedDescription }
    store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    micro.router.$states.combineLatest(micro.router.$pendingQuestions).sink { [weak self] _ in
      Task { @MainActor in self?.observeRouter(); self?.synchronizeLights() }
    }.store(in: &subscriptions)
    store.$busy.sink { [weak self] busy in
      if !busy { Task { @MainActor in self?.registerActions(); self?.synchronizeLights() } }
    }.store(in: &subscriptions)
    micro.objectWillChange.sink { [weak self] in
      Task { @MainActor in self?.synchronizeLights() }
    }.store(in: &subscriptions)
    micro.bridge.objectWillChange.sink { [weak self] in
      Task { @MainActor in self?.synchronizeLights() }
    }.store(in: &subscriptions)
    registerActions()
    store.detect()
  }
  var status: MicroControlStatus {
    .init(hardwareActive: store.microHardwareConfirmed, recoveryPending: store.microRecovery != nil,
          skinVisible: micro.skinEnabled, busy: transitioning || store.busy, message: store.status)
  }
  var canSwitch: Bool { !transitioning && !store.busy && !store.changed && !store.previewMode }
  func perform(_ command: MicroCommand) {
    Task {
      let response = await execute(command)
      if !response.ok { store.error = response.error; showWindow() }
    }
  }
  func execute(_ command: MicroCommand) async -> MicroControlResponse {
    if command == .status { return .init(ok: true, status: status) }
    if command == .show {
      micro.skinEnabled = true
      showWindow()
      return .init(ok: true, status: status)
    }
    guard canSwitch else {
      return .init(ok: false, status: status, error: store.previewMode
        ? "Vista previa: no se modifica el teclado." : "Hay una operación o cambios pendientes. Esperá, aplicá o descartá antes de cambiar de modo.")
    }
    transitioning = true
    defer { transitioning = false; registerActions(); synchronizeLights() }
    let turnOn = command == .on || (command == .toggle && store.microRecovery == nil)
    do {
      if turnOn {
        micro.skinEnabled = true
        try await store.readKeyboardForMicro()
        if store.microRecovery != nil {
          guard store.microHardwareConfirmed else {
            throw S136Error.message("Hay un respaldo Micro pendiente. Volvé al teclado normal antes de activarlo otra vez.")
          }
        } else {
          if !micro.router.routes.isEmpty { micro.syncLights = true }
          try await store.activateMicroNow(micro.bindings)
        }
      } else {
        if store.microRecovery != nil {
          micro.syncLights = false
          try await store.readKeyboardForMicro()
          try await store.restoreMicroNow()
        }
        micro.skinEnabled = false
      }
      // The operation has finished; report completion, not a transitional success.
      var confirmed = status
      confirmed.busy = false
      return .init(ok: true, status: confirmed)
    } catch {
      store.error = error.localizedDescription
      var finished = status
      finished.busy = false
      return .init(ok: false, status: finished, error: error.localizedDescription)
    }
  }
  private func registerActions() { micro.registerHardware(store.microBindingsForHotkeys) }
  private func observeRouter() {
    let states = micro.router.states
    let alerts = tracker.update(states, questions: micro.router.pendingQuestions)
    let cleared = attentionNumbers.filter { states[$0] != .attention }
    notifications.clear(cleared)
    attentionNumbers.removeAll { states[$0] != .attention }
    guard noticesEnabled else { return }
    for number in alerts {
      if !attentionNumbers.contains(number) { attentionNumbers.append(number) }
      notifications.attention(number: number)
    }
  }
  func dismissAttention() { notifications.clear(attentionNumbers); attentionNumbers = [] }
  private func synchronizeLights() {
    guard !transitioning, micro.syncLights, store.canRestoreMicro, store.error == nil,
      store.microRecovery?.bindings == micro.bindings, let current = store.original,
      let planned = try? CodexMicroProfile.withStates(micro.hardwareStates, on: current),
      !current.sameContents(as: planned) else { return }
    store.updateMicro(micro.bindings, states: micro.hardwareStates)
  }
  private func showWindow() {
    if let window = NSApp.windows.first(where: { $0.title == "RED DRAGON PARA MACOS" }) {
      if window.isMiniaturized { window.deminiaturize(nil) }
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
}
