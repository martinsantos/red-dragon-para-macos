// SPDX-License-Identifier: MIT
import AppKit
import Combine
import RedragonCore

/// All skins share one transition queue and one physical keyboard owner.
@MainActor
final class KeyboardSkinController: ObservableObject {
  let mode = MicroModeController()
  let audio = SystemAudio()
  let launchers = AppLaunchers()
  @Published private(set) var active: KeyboardSkin = .normal
  @Published private(set) var confirmed = false
  @Published private(set) var pending = 0
  @Published var galleryVisible = true
  @Published var audioPanelVisible = false
  @Published private(set) var musicMessage = "La animación del teclado por USB requiere validación. Por el receptor no cambió las luces."
  @Published private(set) var notice: String?
  @Published private(set) var shortcutMessage = "⌘⌥F4 · siguiente skin (Win + Alt + Fn + 4 en K628)"
  private var recovery: LiveSkinRecovery?
  private var liveKnown: Snapshot?
  private let repository = LiveSkinRepository()
  private let hotkeys = SkinHotkeys()
  private var subscriptions: Set<AnyCancellable> = []
  private var worker: Task<Void, Never>?
  private var started = false
  private var quitting = false
  private var noticeRevision = 0
  private lazy var requests = SkinRequestQueue { [weak self] target in
    guard let self else { return .init(ok: false, status: .init(hardwareActive: false, recoveryPending: false, skinVisible: false, busy: false, message: "App cerrada."), error: "App cerrada.") }
    return await self.transition(to: target)
  }
  var store: DeviceStore { mode.store }
  var busy: Bool { pending > 0 }
  var canSwitch: Bool { !quitting && mode.canSwitch }
  var status: MicroControlStatus {
    var value = mode.status
    value.hardwareActive = confirmed && active != .normal
    value.recoveryPending = recovery != nil || store.microRecovery != nil
    value.busy = busy || store.busy
    value.skin = active.rawValue
    value.audioConnected = audio.connected; value.audioLevel = audio.bands.max() ?? 0; value.audioMessage = audio.message
    return value
  }
  init() {
    do {
      recovery = try repository.load()
      if let recovery { active = recovery.skin; liveKnown = recovery.baseline; store.liveSkinOwnsKeyboard = true }
      else if store.microRecovery != nil { active = .codex }
    } catch { store.error = "No se pudo cargar la recuperación de skin: \(error.localizedDescription)" }
    store.liveMicroPalette = false
    store.microLauncherColors = launchers.enabled
    mode.externalTransitioning = true
    mode.controlHandler = { [weak self] command in
      guard let self else { return .init(ok: false, status: .init(hardwareActive: false, recoveryPending: false, skinVisible: false, busy: false, message: "App cerrada."), error: "App cerrada.") }
      return await self.execute(command)
    }
    for publisher in [mode.objectWillChange.eraseToAnyPublisher(), audio.objectWillChange.eraseToAnyPublisher(), launchers.objectWillChange.eraseToAnyPublisher()] {
      publisher.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
    store.$microHardwareConfirmed.sink { [weak self] value in
      Task { @MainActor in guard let self, self.active == .codex else { return }; self.confirmed = value }
    }.store(in: &subscriptions)
    hotkeys.next = { [weak self] in self?.select(nil) }
    hotkeys.launch = { [weak self] number in self?.launch(number) }
    launchers.changed = { [weak self] in
      guard let self else { return }; self.store.microLauncherColors = self.launchers.enabled
      self.configureHotkeys()
      if self.confirmed && [.codex, .boca].contains(self.active) { self.select(self.active) }
    }
  }
  func start() {
    guard !started else { return }; started = true
    mode.externalTransitioning = true
    mode.start(); configureHotkeys()
  }
  private func configureHotkeys() {
    guard !store.previewMode else { return }
    do { try hotkeys.register(launchers: launchers.enabled); shortcutMessage = "⌘⌥F4 · siguiente skin (Win + Alt + Fn + 4 en K628)" }
    catch { shortcutMessage = error.localizedDescription }
  }
  func select(_ skin: KeyboardSkin?) {
    Task {
      let response = await request(skin)
      if !response.ok { store.error = response.error; showWindow() }
    }
  }
  private func request(_ skin: KeyboardSkin?, toggleCodex: Bool = false) async -> MicroControlResponse {
    guard canSwitch else { return .init(ok: false, status: status, error: "Aplicá o descartá los cambios pendientes antes de cambiar de skin.") }
    if skin == .music { audioPanelVisible = true }
    pending += 1; mode.externalTransitioning = true
    defer {
      pending -= 1
      if pending == 0 { mode.externalTransitioning = active != .codex; if confirmed && active != .normal { startWorker() } }
    }
    return await requests.submit(skin, current: active, toggleCodex: toggleCodex, includeMusic: false)
  }
  func prepareToQuit() async -> Bool {
    if store.previewMode { return true }
    guard recovery != nil || store.microRecovery != nil || active != .normal || busy else {
      await audio.stop(); return true
    }
    quitting = true
    pending += 1; mode.externalTransitioning = true
    let response = await requests.submit(.normal, current: active)
    pending -= 1; quitting = false
    if !response.ok { store.error = response.error; showWindow() }
    return response.ok
  }
  func execute(_ command: MicroCommand) async -> MicroControlResponse {
    switch command {
    case .status: return .init(ok: true, status: status)
    case .show: galleryVisible = false; mode.micro.skinEnabled = true; showWindow(); return .init(ok: true, status: status)
    case .skinsShow: galleryVisible = true; showWindow(); return .init(ok: true, status: status)
    case .on, .skinCodex: return await request(.codex)
    case .off, .skinNormal: return await request(.normal)
    case .toggle: return await request(nil, toggleCodex: true)
    case .skinNext: return await request(nil)
    case .skinBoca: return await request(.boca)
    case .skinMusic: return await request(.music)
    case .audioOn:
      audioPanelVisible = true; galleryVisible = true
      await audio.start()
      return .init(ok: audio.connected, status: status, error: audio.connected ? nil : audio.message)
    case .audioOff:
      await audio.stop(); return .init(ok: true, status: status)
    case .launchF1, .launchF2, .launchF3, .launchF4:
      let number = [MicroCommand.launchF1, .launchF2, .launchF3, .launchF4].firstIndex(of: command)! + 1
      do { try await launchers.launch(number); return .init(ok: true, status: status) }
      catch { return .init(ok: false, status: status, error: error.localizedDescription) }
    }
  }
  private func waitForIdle() async throws {
    let deadline = Date().addingTimeInterval(60)
    while store.busy || mode.transitioning {
      guard Date() < deadline else { throw S136Error.message("La operación sigue en curso. Esperá y consultá el estado de la skin.") }
      try await Task.sleep(for: .milliseconds(100))
    }
    guard !store.changed else { throw S136Error.message("Aplicá o descartá los cambios pendientes antes de cambiar de skin.") }
  }
  private func stopWorker() async {
    let previous = worker; worker = nil
    previous?.cancel(); await previous?.value
  }
  private func transition(to target: KeyboardSkin) async -> MicroControlResponse {
    do {
      await stopWorker()
      try await waitForIdle()
      if target != .music { await audio.stop(); audioPanelVisible = false }
      if let known = liveKnown ?? (store.microRecovery != nil ? store.microRecovery?.installed : nil) {
        if known.configuration[1] == 29 { try await store.stopLiveColors(known: known) }
        if let record = recovery { try await store.restoreLiveMode(record) }
        try repository.clear(); recovery = nil; liveKnown = nil; store.liveSkinOwnsKeyboard = false
        if active != .codex { active = .normal; confirmed = true }
      }
      if target != .codex, store.microRecovery != nil {
        let response = await mode.execute(.off)
        guard response.ok else { throw S136Error.message(response.error ?? "No se pudo restaurar Codex.") }
        active = .normal; confirmed = true
      }
      switch target {
      case .normal:
        mode.micro.skinEnabled = false
      case .codex:
        let response = await mode.execute(.on)
        guard response.ok else { throw S136Error.message(response.error ?? "No se pudo activar Codex.") }
        if store.microRecovery?.launcherColors != launchers.enabled {
          store.updateMicro(mode.micro.bindings)
          try await waitForIdle()
          if let error = store.error { throw S136Error.message(error) }
        }
        liveKnown = store.original
      case .boca, .music:
        try await store.readKeyboardForMicro()
        guard let known = store.original, let colors = known.customColors else { throw S136Error.message("No se pudo leer la paleta del K628.") }
        if target == .music && known.endpoint.target != 0 {
          audioPanelVisible = true; galleryVisible = true
          throw S136Error.message("Por el receptor, las pruebas RGB temporales no cambiaron las luces. Para verificar Música, conectá el K628 por cable con el selector en OFF. Podés probar el audio en pantalla mientras tanto.")
        }
        let planned = target == .boca
          ? try StaticLightingProfile.prepare(known, skin: .boca, launchers: launchers.enabled)
          : try LiveLightingProfile.prepare(known)
        let record = LiveSkinRecovery(baseline: known, installed: planned, skin: target)
        try repository.save(record); recovery = record; liveKnown = known; store.liveSkinOwnsKeyboard = true
        let installed = target == .boca
          ? try await store.installStaticSkin(known, planned: planned)
          : try await store.installLiveMode(known)
        liveKnown = installed
        if target == .music {
          try await store.sendLiveColors(SkinPalette.colors(for: target, baseline: colors, bands: audio.bands, launchers: launchers.enabled), known: installed)
        }
        mode.micro.skinEnabled = false
      }
      active = target; confirmed = true
      announce("Skin: \(target.title)")
      mode.notifications.skinChanged(target.title)
      var result = status; result.busy = store.busy || pending > 1
      return .init(ok: true, status: result)
    } catch {
      confirmed = false
      var result = status; result.busy = store.busy || pending > 1
      return .init(ok: false, status: result, error: error.localizedDescription)
    }
  }
  private var currentKeyboard: Snapshot? {
    if let current = store.original, current.isKeyboard, current.profile == liveKnown?.profile { return current }
    return liveKnown
  }
  private func startWorker() {
    guard worker == nil, confirmed, active == .music else { return }
    worker = Task { [weak self] in
      var previous: [UInt8]?
      while !Task.isCancelled {
        guard let self else { return }
        if self.pending == 0, !self.store.busy, !self.mode.transitioning, !self.store.changed,
           let known = self.currentKeyboard, let palette = known.customColors {
          self.liveKnown = known
          var base = palette
          if self.active == .codex && self.mode.micro.syncLights {
            for (index, state) in self.mode.micro.hardwareStates.enumerated() {
              let slot = CodexMicroProfile.slots[index]
              base.replaceSubrange(slot*3..<slot*3+3, with: state.rgb)
            }
          }
          let colors = SkinPalette.colors(for: self.active, baseline: base, bands: self.audio.connected ? self.audio.bands : [], launchers: self.launchers.enabled)
          if previous != colors {
            do { try await self.store.sendLiveColors(colors, known: known); previous = colors }
            catch { self.announce("No se pudieron actualizar las luces: \(error.localizedDescription)"); self.confirmed = false; return }
          }
        }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      }
    }
  }
  func launch(_ number: Int) {
    Task { do { try await launchers.launch(number); announce(launchers.message) }
      catch { store.error = error.localizedDescription; showWindow() } }
  }
  private func announce(_ text: String) {
    noticeRevision += 1; let revision = noticeRevision; notice = text
    Task { try? await Task.sleep(for: .seconds(4)); if noticeRevision == revision { notice = nil } }
  }
  func showWindow() {
    if let window = NSApp.windows.first(where: { $0.title == "RED DRAGON PARA MACOS" }) {
      if window.isMiniaturized { window.deminiaturize(nil) }; window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
}
