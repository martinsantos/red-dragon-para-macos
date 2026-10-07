// SPDX-License-Identifier: MIT
import AppKit
import Combine
import RedragonCore

/// Buttons, shortcuts, CLI and Codex updates share one transaction owner.
@MainActor
final class KeyboardSkinController: ObservableObject {
  let mode = MicroModeController()
  let audio = SystemAudio()
  let launchers = AppLaunchers()
  @Published private(set) var active: KeyboardSkin = .normal
  @Published private(set) var confirmed = false
  @Published private(set) var pending = 0
  @Published private(set) var requested: KeyboardSkin?
  @Published private(set) var transitionError: String?
  @Published var galleryVisible = true
  @Published var audioPanelVisible = false
  @Published private(set) var notice: String?
  @Published private(set) var shortcutMessage = "⌘Espacio · siguiente skin (Win + Espacio en el Redragon conectado a Mac)"
  @Published var autoProfiles = UserDefaults.standard.bool(forKey: "skins.autoProfiles") {
    didSet { UserDefaults.standard.set(autoProfiles, forKey: "skins.autoProfiles"); if started && autoProfiles { followApplication() } }
  }
  @Published var codexChatPad = UserDefaults.standard.bool(forKey: "skins.codexChatPad") {
    didSet { UserDefaults.standard.set(codexChatPad, forKey: "skins.codexChatPad"); if started && active == .codex { select(.codex) } }
  }
  @Published private(set) var lastPadAction: Int?
  private var state = SkinSessionState()
  private let repository = SkinSessionRepository()
  private let hotkeys = SkinHotkeys()
  private var subscriptions: Set<AnyCancellable> = []
  private var worker: Task<Void, Never>?
  private var started = false
  private var quitting = false
  private var refreshing = false
  private var recoveryLoadFailed = false
  private var noticeRevision = 0
  private let padActions = ApplicationPadActions()
  private var appObserver: NSObjectProtocol?
  private var shortcutPresses = 0
  private var lastPhysicalLauncher: Int?
  private var lastPhysicalPad: Int?
  var usesFunctionPad: Bool { state.session?.controlPad == true }
  var launcherKeysActive: Bool { confirmed && state.session?.launcherKeys == true && hotkeys.launcherRegistered }
  private lazy var requests = SkinRequestQueue(transition: { [weak self] target in
    guard let self else { return .init(ok: false, status: .init(hardwareActive: false, recoveryPending: false, skinVisible: false, busy: false, message: "App cerrada."), error: "App cerrada.") }
    return await self.transition(to: target)
  }, changed: { [weak self] target in await self?.setRequested(target) })
  var store: DeviceStore { mode.store }
  var busy: Bool { pending > 0 }
  var canSwitch: Bool { !quitting && !recoveryLoadFailed && mode.canSwitch }
  var musicAvailable: Bool { store.endpoints.contains(where: { $0.supportsLiveLighting }) }
  var musicMessage: String {
    musicAvailable ? "USB directo detectado. La skin conecta el audio y envía ondas al teclado."
      : "Las ondas físicas requieren USB directo: conectá un cable de datos y poné el selector del K628 en OFF. Podés comprobar el audio aquí sin cambiar tu skin."
  }
  var status: MicroControlStatus {
    var value = mode.status
    value.hardwareActive = confirmed && active != .normal
    value.recoveryPending = state.session != nil || state.pending != nil
    value.busy = busy || store.busy
    value.skin = active.rawValue; value.requestedSkin = requested?.rawValue
    value.message = busy ? "Cambiando a \((requested ?? active).title)…" : store.status
    value.audioConnected = audio.connected; value.audioLevel = audio.bands.max() ?? 0; value.audioMessage = audio.message
    value.lastLauncher = launchers.lastLaunched; value.lastPadAction = lastPadAction
    value.launcherKeysActive = launcherKeysActive; value.autoProfiles = autoProfiles
    value.shortcutActive = hotkeys.shortcutRegistered; value.shortcutPresses = shortcutPresses
    value.lastPhysicalLauncher = lastPhysicalLauncher; value.lastPhysicalPad = lastPhysicalPad
    return value
  }
  init() {
    do {
      if let saved = try repository.load() { state = saved }
      else {
        let live = try LiveSkinRepository().load()
        let micro = store.microRecovery
        guard live == nil || micro == nil else { throw S136Error.message("Hay dos respaldos antiguos pendientes. Se conservan para recuperar el teclado antes de cambiar de skin.") }
        if let live { state.session = .init(baseline: live.baseline, installed: live.installed, skin: live.skin) }
        else if let micro { state.session = .init(baseline: micro.baseline, installed: micro.installed, skin: .codex, launcherColors: micro.launcherColors == true, bindings: micro.bindings) }
        try repository.save(state)
        try LiveSkinRepository().clear(); try store.clearLegacySkinRecovery()
      }
      active = state.session?.skin ?? .normal
      store.adoptSkinSession(state.session, confirmed: false)
    } catch { recoveryLoadFailed = true; transitionError = "No se pudo cargar la recuperación: \(error.localizedDescription)" }
    mode.externalTransitioning = true
    mode.externalHotkeys = true
    mode.controlHandler = { [weak self] command in
      guard let self else { return .init(ok: false, status: .init(hardwareActive: false, recoveryPending: false, skinVisible: false, busy: false, message: "App cerrada."), error: "App cerrada.") }
      return await self.execute(command)
    }
    mode.synchronizeHandler = { [weak self] in self?.refreshCodex() }
    store.microUpdateHandler = { [weak self] in self?.select(.codex) }
    store.fullMicroRestoreHandler = { [weak self] in self?.select(.normal) }
    for publisher in [mode.objectWillChange.eraseToAnyPublisher(), audio.objectWillChange.eraseToAnyPublisher(), launchers.objectWillChange.eraseToAnyPublisher()] {
      publisher.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
    hotkeys.next = { [weak self] in guard let self else { return }; self.shortcutPresses += 1; self.select(nil) }
    hotkeys.launch = { [weak self] number in guard let self else { return }; self.lastPhysicalLauncher = number; self.launch(number) }
    hotkeys.pad = { [weak self] number in guard let self else { return }; self.lastPhysicalPad = number; self.performPad(number) }
    launchers.changed = { [weak self] in
      guard let self else { return }; self.configureHotkeys()
      if self.confirmed && self.active != .normal { self.select(self.active) }
    }
    appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
      object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.followApplication() } }
  }
  private func setRequested(_ target: KeyboardSkin?) { requested = target }
  func start() {
    guard !started else { return }; started = true
    mode.start(); configureHotkeys()
    guard !recoveryLoadFailed, !store.previewMode else { return }
    Task {
      do {
        try await waitForIdle(); try await store.readKeyboardForMicro()
        if let current = store.original {
          try reconcile(current); confirmed = true; store.adoptSkinSession(state.session, confirmed: true)
          if active != .normal { _ = await request(active) }
          configureHotkeys()
        }
      } catch { transitionError = error.localizedDescription }
    }
  }
  func configureHotkeys() {
    guard !store.previewMode else { return }
    do { try hotkeys.register(launchers: confirmed && state.session?.launcherKeys == true, actionPad: confirmed && usesFunctionPad); shortcutMessage = "⌘Espacio · siguiente skin (Win + Espacio en el Redragon conectado a Mac)" }
    catch { shortcutMessage = error.localizedDescription }
  }
  func select(_ skin: KeyboardSkin?) {
    autoProfiles = false
    Task { let response = await request(skin); if !response.ok { transitionError = response.error } }
  }
  private func followApplication() {
    guard autoProfiles, started, !quitting,
      let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
      let target = ApplicationProfileRouting.skin(for: bundleID), target != (requested ?? active) else { return }
    Task { let response = await request(target); if !response.ok { transitionError = response.error } }
  }
  private func request(_ skin: KeyboardSkin?, toggleCodex: Bool = false) async -> MicroControlResponse {
    guard canSwitch else { return .init(ok: false, status: status, error: "Aplicá o descartá los cambios pendientes antes de cambiar de skin.") }
    if skin == .music { audioPanelVisible = true }
    pending += 1; transitionError = nil
    defer { pending -= 1; if pending == 0 { requested = nil; startWorker() } }
    return await requests.submit(skin, current: active, toggleCodex: toggleCodex, includeMusic: musicAvailable)
  }
  func prepareToQuit() async -> Bool {
    if store.previewMode { return true }
    guard state.session != nil || state.pending != nil || busy else { await audio.stop(); return true }
    quitting = true; pending += 1
    let response = await requests.submit(.normal, current: active)
    pending -= 1; quitting = false
    if !response.ok { store.error = response.error; showWindow() }
    return response.ok
  }
  func execute(_ command: MicroCommand) async -> MicroControlResponse {
    if [.on, .off, .toggle, .skinNext, .skinApps, .skinCodex, .skinClaude, .skinNormal, .skinBoca, .skinMusic].contains(command) {
      autoProfiles = false
    }
    switch command {
    case .status: return .init(ok: true, status: status)
    case .show: galleryVisible = false; mode.micro.skinEnabled = true; showWindow(); return .init(ok: true, status: status)
    case .skinsShow: galleryVisible = true; showWindow(); return .init(ok: true, status: status)
    case .on, .skinCodex: return await request(.codex)
    case .off, .skinNormal: return await request(.normal)
    case .toggle: return await request(nil, toggleCodex: true)
    case .skinNext: return await request(nil)
    case .skinApps: return await request(.apps)
    case .skinClaude: return await request(.claude)
    case .skinBoca: return await request(.boca)
    case .skinMusic: return await request(.music)
    case .hotkeysRetry: configureHotkeys(); return .init(ok: !shortcutMessage.contains("ocupado"), status: status)
    case .pad1, .pad2, .pad3, .pad4, .pad5, .pad6:
      let number = [MicroCommand.pad1, .pad2, .pad3, .pad4, .pad5, .pad6].firstIndex(of: command)! + 1
      do { try await performPadNow(number); return .init(ok: true, status: status) }
      catch { return .init(ok: false, status: status, error: error.localizedDescription) }
    case .audioOn:
      audioPanelVisible = true; galleryVisible = true; await audio.start()
      return .init(ok: audio.connected, status: status, error: audio.connected ? nil : audio.message)
    case .audioOff: await audio.stop(); return .init(ok: true, status: status)
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
  private func stopWorker() async { let previous = worker; worker = nil; previous?.cancel(); await previous?.value }
  private func reconcile(_ current: Snapshot) throws {
    if let journal = state.pending {
      state.session = try journal.resolved(on: current); state.pending = nil
      try repository.save(state)
    } else if let session = state.session { _ = try session.restored(on: current) }
    active = state.session?.skin ?? .normal
  }
  private func transition(to target: KeyboardSkin) async -> MicroControlResponse {
    var wasConfirmed = confirmed
    let changedSkin = active != target || !confirmed
    do {
      try await waitForIdle()
      // Preflight must leave the current skin intact when the next one is unavailable.
      if target == .music && !musicAvailable {
        audioPanelVisible = true
        throw S136Error.message(musicMessage)
      }
      if target == .music {
        await audio.start()
        guard audio.connected else { throw S136Error.message(audio.message) }
      }
      await stopWorker()
      if active == .music, let session = state.session { try await store.stopLiveColors(known: session.installed) }
      try await store.readKeyboardForMicro()
      guard let current = store.original else { throw S136Error.message("No se pudo leer el K628.") }
      try reconcile(current); confirmed = true; wasConfirmed = true
      guard target != .music || current.endpoint.supportsLiveLighting else { throw S136Error.message(musicMessage) }
      let syncCodex = codexChatPad && (mode.micro.syncLights || (active != .codex && !mode.micro.router.routes.isEmpty))
      let states = target == .codex && syncCodex ? mode.micro.hardwareStates : nil
      let plan = try KeyboardSkinSession.plan(target, from: state.session, current: current,
        bindings: mode.micro.bindings, states: states, launchers: launchers.enabled,
        controlPad: true, launcherKeys: true, chatPad: codexChatPad)
      // Reserve all required keys before changing firmware. A collision keeps the old skin.
      do { try hotkeys.register(launchers: plan.session?.launcherKeys == true, actionPad: plan.session?.controlPad == true) }
      catch {
        guard (plan.session?.launcherKeys != true || hotkeys.launcherRegistered),
              (plan.session?.controlPad != true || hotkeys.padRegistered) else { throw error }
        shortcutMessage = error.localizedDescription
      }
      let journal = SkinTransitionJournal(previous: state.session, proposed: plan.session, before: current, after: plan.snapshot)
      state.pending = journal; try repository.save(state)
      if !current.sameContents(as: plan.snapshot) { _ = try await store.installStaticSkin(current, planned: plan.snapshot) }
      if target == .music {
        try await store.sendLiveColors(SkinPalette.colors(for: .music, baseline: plan.snapshot.customColors ?? [], bands: audio.bands, launchers: launchers.enabled), known: plan.snapshot)
      }
      let committed = SkinSessionState(session: plan.session, pending: nil)
      try repository.save(committed); state = committed
      active = target; confirmed = true; transitionError = nil
      store.adoptSkinSession(state.session, confirmed: true)
      configureHotkeys()
      mode.micro.skinEnabled = target == .codex && !galleryVisible
      if target == .codex { mode.micro.syncLights = syncCodex }
      if target != .music { await audio.stop(); audioPanelVisible = false }
      if changedSkin { announce("Skin: \(target.title)"); mode.notifications.skinChanged(target.title) }
      var result = status; result.busy = store.busy || pending > 1
      result.message = store.status
      return .init(ok: true, status: result)
    } catch {
      if let journal = state.pending {
        do {
          try await store.readKeyboardForMicro()
          guard let current = store.original else { throw error }
          // A frame can fail after configuration committed. Restore the previous skin too.
          if current.sameContents(as: journal.after), !current.sameContents(as: journal.before) {
            if journal.proposed?.skin == .music { try await store.stopLiveColors(known: current) }
            _ = try await store.installStaticSkin(current, planned: journal.before.preparedForRestore(on: current))
          }
          guard let restored = store.original else { throw error }
          try reconcile(restored); confirmed = true; store.adoptSkinSession(state.session, confirmed: true)
        } catch { confirmed = false }
      } else { confirmed = wasConfirmed }
      configureHotkeys()
      if active != .music { await audio.stop() }
      transitionError = error.localizedDescription
      var result = status; result.busy = store.busy || pending > 1
      return .init(ok: false, status: result, error: error.localizedDescription)
    }
  }
  private func refreshCodex() {
    guard codexChatPad, !refreshing, !busy, active == .codex, confirmed, mode.micro.syncLights,
      !store.busy, !store.changed, let session = state.session,
      let plan = try? KeyboardSkinSession.plan(.codex, from: session, current: session.installed,
        bindings: mode.micro.bindings, states: mode.micro.hardwareStates, launchers: launchers.enabled,
        controlPad: true, launcherKeys: true, chatPad: true),
      !plan.snapshot.sameContents(as: session.installed) else { return }
    refreshing = true
    Task { _ = await request(.codex); refreshing = false }
  }
  private func startWorker() {
    guard worker == nil, confirmed, active == .music, let session = state.session else { return }
    worker = Task { [weak self] in
      var previous: [UInt8]?
      while !Task.isCancelled {
        guard let self else { return }
        if !self.busy, !self.store.busy, !self.store.changed {
          let colors = SkinPalette.colors(for: .music, baseline: session.installed.customColors ?? [],
            bands: self.audio.connected ? self.audio.bands : [], launchers: self.launchers.enabled)
          do { try await self.store.sendLiveColors(colors, known: session.installed, refreshOnly: previous == colors); previous = colors }
          catch { self.transitionError = "Se detuvo la animación: \(error.localizedDescription)"; return }
        }
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      }
    }
  }
  func launch(_ number: Int) {
    Task { do { try await launchers.launch(number); announce(launchers.message) }
      catch { store.error = error.localizedDescription; showWindow() } }
  }
  func performPad(_ number: Int) {
    Task { do { try await performPadNow(number) }
      catch { transitionError = error.localizedDescription; showWindow() } }
  }
  private func performPadNow(_ number: Int) async throws {
    guard (1...6).contains(number), confirmed, usesFunctionPad, !busy else {
      throw S136Error.message("Activá Codex o Claude y esperá la confirmación para usar Num 1–6.")
    }
    let message: String
    if active == .codex && state.session?.chatPad == true {
      mode.micro.perform(mode.micro.bindings[number-1])
      if let error = mode.micro.error { throw S136Error.message(error) }
      message = mode.micro.message
    } else { message = try await padActions.perform(ApplicationPadAction.actions(for: active)[number-1], skin: active) }
    lastPadAction = number; announce(message)
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
  deinit { if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) } }
}
