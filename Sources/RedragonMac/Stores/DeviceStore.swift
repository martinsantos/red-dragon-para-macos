// SPDX-License-Identifier: MIT
import Combine
import Foundation
import RedragonCore

@MainActor
final class DeviceStore: ObservableObject {
  private let controller: HardwareController
  private let backups: BackupRepository
  private let system = MacSystemIntegration()
  private let microRepository = MicroRecoveryRepository()
  @Published private(set) var microRecovery: MicroRecovery?
  @Published private(set) var microHardwareConfirmed = false
  var microBindingsForHotkeys: [MicroBinding]? { microHardwareConfirmed ? microRecovery?.bindings : nil }

  @Published private(set) var endpoints: [Endpoint] = []
  @Published private(set) var selectedID: String?
  @Published private(set) var original: Snapshot?
  @Published private(set) var edited: Snapshot?
  @Published private(set) var busy = false
  @Published private(set) var inputAccessDenied = false
  @Published private(set) var status = "Detectá el kit para leer su configuración."
  @Published var error: String?
  @Published private(set) var backupURL: URL?
  var liveMicroPalette = false
  var microLauncherColors = false
  var microUpdateHandler: (() -> Void)?
  var fullMicroRestoreHandler: (() -> Void)?
  @Published var liveSkinOwnsKeyboard = false
  var skinOwnsSelected: Bool { liveSkinOwnsKeyboard && original?.isKeyboard == true }
  let previewMode: Bool

  var changed: Bool {
    guard let original, let edited else { return false }
    return !original.sameContents(as: edited)
  }
  var selectedEndpoint: Endpoint? { endpoints.first { $0.id == selectedID } }
  var needsInputPermission: Bool { error?.contains("e00002e2") == true }
  var canRead: Bool { !busy && !previewMode && !changed }
  var canApply: Bool { !busy && !previewMode && changed && !microOwnsSelected && !skinOwnsSelected }
  var canDiscard: Bool { !busy && changed }
  var microOwnsSelected: Bool {
    guard let recovery = microRecovery, let original else { return false }
    return original.endpoint.productID == recovery.baseline.endpoint.productID
      && original.endpoint.target == recovery.baseline.endpoint.target
      && original.profile == recovery.baseline.profile
  }
  var canActivateMicro: Bool { !busy && !previewMode && !changed && edited?.isKeyboard == true && microRecovery == nil }
  var canRestoreMicro: Bool { !busy && !previewMode && !changed && microOwnsSelected }

  init(
    controller: HardwareController = HardwareController(),
    backups: BackupRepository = BackupRepository(), arguments: [String] = CommandLine.arguments
  ) {
    self.controller = controller
    self.backups = backups
    previewMode = arguments.contains("--preview")
    if !previewMode {
      do { microRecovery = try microRepository.load() }
      catch { self.error = "No se pudo cargar la recuperación Micro: \(error.localizedDescription)" }
    }
    guard let index = arguments.firstIndex(of: "--preview") else { return }
    guard index + 1 < arguments.count else {
      error = "Indicá el archivo de respaldo para la vista previa."
      return
    }
    do {
      let snapshot = try SnapshotFile.load(URL(fileURLWithPath: arguments[index + 1]))
      endpoints = [snapshot.endpoint]
      selectedID = snapshot.endpoint.id
      original = snapshot
      edited = snapshot
      status = "Vista previa del respaldo · sin escrituras al dispositivo."
    } catch {
      self.error = error.localizedDescription
    }
  }

  func detect() {
    guard canRead else { return }
    busy = true
    Task {
      endpoints = await controller.endpoints()
      if !endpoints.contains(where: { $0.id == selectedID }) {
        selectedID = endpoints.first(where: { $0.supportsLiveLighting })?.id ?? endpoints.first(where: { $0.isKeyboard })?.id ?? endpoints.first?.id
        original = nil
        edited = nil
      }
      busy = false
      if endpoints.isEmpty { inputAccessDenied = false }
      status =
        endpoints.isEmpty
        ? "Conectá el receptor del S136 o el mouse por USB."
        : "\(endpoints.count) interfaces detectadas."
      if selectedEndpoint != nil { read() }
    }
  }

  func select(_ id: String) {
    guard canRead else { return }
    selectedID = id
    original = nil
    edited = nil
    read()
  }

  func read() {
    guard canRead, let endpoint = selectedEndpoint else { return }
    busy = true
    error = nil
    status = "Leyendo el dispositivo…"
    Task {
      defer { busy = false }
      do {
        let snapshot = try await controller.read(endpoint)
        original = snapshot
        edited = snapshot
        inputAccessDenied = false
        if microOwnsSelected, let recovery = microRecovery {
          microHardwareConfirmed = snapshot.sameContents(as: recovery.installed)
        }
        status =
          "Leído · perfil \(snapshot.profile + 1) · \(snapshot.isKeyboard ? "teclado" : "mouse")"
      } catch {
        inputAccessDenied = error.localizedDescription.contains("e00002e2")
        self.error = inputAccessDenied ? nil : error.localizedDescription
        status = inputAccessDenied ? "Habilitá Monitoreo de entrada para configurar el kit." : "No se pudo leer el dispositivo."
      }
    }
  }

  func edit(_ action: (inout Snapshot) throws -> Void) {
    guard !busy, !microOwnsSelected && !skinOwnsSelected, var snapshot = edited else { return }
    do {
      try action(&snapshot)
      edited = snapshot
    } catch {
      self.error = error.localizedDescription
    }
  }

  func apply() {
    guard canApply, let original, let edited else { return }
    busy = true
    error = nil
    status = "Creando respaldo y verificando cambios…"
    Task {
      defer { busy = false }
      do {
        backupURL = try backups.save(original)
        let verified = try await controller.apply(original: original, edited: edited)
        self.original = verified
        self.edited = verified
        status = "Guardado en el dispositivo y verificado por USB."
      } catch {
        self.error = error.localizedDescription
        status = "La operación no quedó confirmada. Descartá los cambios pendientes y volvé a leer."
      }
    }
  }

  func restoreBackup() {
    guard !busy, !changed, !microOwnsSelected && !skinOwnsSelected, let original,
      let url = system.chooseBackup(in: backups.directory)
    else { return }
    do {
      edited = try backups.load(url, for: original)
      status = "Respaldo preparado. Pulsá Aplicar para restaurarlo."
    } catch {
      self.error = error.localizedDescription
    }
  }
  /// Apply only the lighting fields; preserve unrelated pending key/macro edits.
  func applySolidColor(_ rgb: [UInt8]) {
    guard !busy, !microOwnsSelected && !skinOwnsSelected, let original, let edited else { return }
    if previewMode {
      edit { try $0.setSolidColor(rgb) }
      status = "Vista previa del color · sin escrituras al dispositivo."
      return
    }
    var solid = original
    do { try solid.setSolidColor(rgb) } catch {
      self.error = error.localizedDescription
      return
    }
    busy = true
    error = nil
    status = "Aplicando color fijo…"
    Task {
      defer { busy = false }
      do {
        backupURL = try backups.save(original)
        let verified = try await controller.apply(original: original, edited: solid)
        var pending = edited
        var lightingFields = [1, 2, 5, 6, 7, 8]
        if let start = solid.keyboardModeColorOffset {
          lightingFields += Array(start + 1..<start + 5)
        }
        for index in lightingFields { pending.configuration[index] = verified.configuration[index] }
        self.original = verified
        self.edited = pending
        status =
          changed
          ? "Color aplicado · quedan otros cambios pendientes."
          : "Color fijo guardado y verificado."
      } catch {
        self.error = error.localizedDescription
        status = "No se confirmó el cambio de color. Volvé a leer el dispositivo."
      }
    }
  }

  func discard() { edited = original }

  func applyKeyColor(_ rgb: [UInt8], at slot: Int) {
    guard !busy, !microOwnsSelected && !skinOwnsSelected, let original, let edited else { return }
    if previewMode {
      edit { try $0.setVisibleKeyColor(rgb, at: slot) }
      status = "Vista previa del color de la tecla · sin escrituras al dispositivo."
      return
    }
    var planned = original
    do { try planned.setVisibleKeyColor(rgb, at: slot) } catch {
      self.error = error.localizedDescription
      return
    }
    busy = true
    error = nil
    status = "Aplicando color a \(KeyCatalog.physicalName(slot: slot, keyboard: true))…"
    Task {
      defer { busy = false }
      do {
        backupURL = try backups.save(original)
        let verified = try await controller.apply(original: original, edited: planned)
        var pending = edited
        for index in [1, 2, 22] { pending.configuration[index] = verified.configuration[index] }
        if var colors = pending.customColors, let before = original.customColors,
           let after = verified.customColors {
          for index in after.indices where before[index] != after[index] { colors[index] = after[index] }
          pending.customColors = colors
        }
        self.original = verified
        self.edited = pending
        status = changed ? "Color de tecla aplicado · quedan otros cambios pendientes." : "Color de tecla guardado y verificado por USB."
      } catch {
        self.error = error.localizedDescription
        status = "No se confirmó el color de la tecla. Volvé a leer el dispositivo."
      }
    }
  }

  func activateMicro(_ bindings: [MicroBinding]) {
    Task {
      do { try await activateMicroNow(bindings) }
      catch { self.error = error.localizedDescription }
    }
  }

  /// Select and read the keyboard for shortcuts and commands, even from the mouse screen.
  func readKeyboardForMicro() async throws {
    guard canRead else { throw S136Error.message("Aplicá o descartá los cambios pendientes y esperá a que termine la operación actual.") }
    busy = true
    error = nil
    status = "Leyendo el K628 para cambiar de modo…"
    defer { busy = false }
    endpoints = await controller.endpoints()
    guard let keyboard = endpoints.first(where: { $0.supportsLiveLighting }) ?? endpoints.first(where: { $0.isKeyboard }) else {
      throw S136Error.message("Conectá el K628 por cable (selector OFF) o encendelo en 2,4 GHz con su receptor.")
    }
    selectedID = keyboard.id
    original = nil
    edited = nil
    do {
      let snapshot = try await controller.read(keyboard)
      original = snapshot
      edited = snapshot
      inputAccessDenied = false
      if microOwnsSelected, let recovery = microRecovery {
        microHardwareConfirmed = snapshot.sameContents(as: recovery.installed)
      } else { microHardwareConfirmed = false }
      status = "Leído · perfil \(snapshot.profile + 1) · teclado"
    } catch {
      inputAccessDenied = error.localizedDescription.contains("e00002e2")
      microHardwareConfirmed = false
      status = "No se pudo leer el teclado para cambiar de modo."
      throw error
    }
  }

  func activateMicroNow(_ bindings: [MicroBinding]) async throws {
    guard canActivateMicro, let original else { throw S136Error.message("El teclado no está listo para activar Micro.") }
    busy = true
    error = nil
    status = "Respaldando y activando las seis teclas Micro…"
    defer { busy = false }
    do {
        let planned = try CodexMicroProfile.prepare(original, bindings: bindings, liveLighting: liveMicroPalette, launcherColors: microLauncherColors)
        let backup = try backups.save(original)
        backupURL = backup
        let recovery = MicroRecovery(baseline: original, installed: planned, bindings: bindings, backupURL: backup, launcherColors: microLauncherColors)
        // Persist recovery BEFORE the first hardware write, including across app crashes.
        try microRepository.save(recovery)
        microRecovery = recovery
        let verified = try await controller.apply(original: original, edited: planned)
        self.original = verified
        self.edited = verified
        microHardwareConfirmed = true
        status = "Micro activo · Num 1–6 · respaldo guardado."
    } catch {
      self.error = error.localizedDescription
      status = "Activación sin confirmar. Volvé a leer y usá Volver al teclado normal."
      throw error
    }
  }

  func updateMicro(_ bindings: [MicroBinding], states: [MicroState]? = nil) {
    if let microUpdateHandler { microUpdateHandler(); return }
    guard canRestoreMicro, let original, let previous = microRecovery else { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        var planned = try CodexMicroProfile.prepare(original, bindings: bindings, liveLighting: liveMicroPalette, launcherColors: microLauncherColors)
        if let states { planned = try CodexMicroProfile.withStates(states, on: planned) }
        var recovery = previous
        if previous.launcherColors == true && !microLauncherColors, var colors = planned.customColors, let baselineColors = previous.baseline.customColors {
          for slot in 1...4 { colors.replaceSubrange(slot*3..<slot*3+3, with: baselineColors[slot*3..<slot*3+3]) }
          planned.customColors = colors
        }
        if planned.sameContents(as: original) && bindings == previous.bindings && previous.launcherColors == microLauncherColors { return }
        recovery.launcherColors = microLauncherColors
        recovery.installed = planned
        recovery.bindings = bindings
        try microRepository.save(recovery)
        let verified = try await controller.apply(original: original, edited: planned)
        microRecovery = recovery
        self.original = verified
        self.edited = verified
        microHardwareConfirmed = true
        status = "Perfil Micro actualizado y verificado."
      } catch {
        try? microRepository.save(previous)
        self.error = error.localizedDescription
        status = "No se pudo actualizar Micro. Volvé a leer el dispositivo."
      }
    }
  }

  func restoreMicro() {
    Task {
      do { try await restoreMicroNow() }
      catch { self.error = error.localizedDescription }
    }
  }

  func restoreMicroNow() async throws {
    guard canRestoreMicro, let current = original, let recovery = microRecovery else {
      throw S136Error.message("El teclado no está listo para restaurar sus ajustes anteriores.")
    }
    busy = true
    error = nil
    status = "Restaurando el teclado…"
    defer { busy = false }
    do {
        var baseline = try recovery.baseline.preparedForRestore(on: current)
        var installed = try recovery.installed.preparedForRestore(on: current)
        baseline.endpoint = current.endpoint
        installed.endpoint = current.endpoint
        let restored: Snapshot
        if baseline.sameContents(as: current) {
          restored = current // A failed activation was already rolled back.
        } else {
          let planned = try CodexMicroProfile.restore(baseline: baseline, installed: installed, current: current, launcherColors: recovery.launcherColors == true)
          restored = try await controller.apply(original: current, edited: planned)
        }
        self.original = restored
        self.edited = restored
        try microRepository.clear()
        microRecovery = nil
        microHardwareConfirmed = false
        status = "Teclas y luces anteriores restauradas."
    } catch {
      self.error = error.localizedDescription
      status = "El respaldo se conserva. No se confirmó la restauración."
      throw error
    }
  }

  func restoreFullMicroBackup() {
    if let fullMicroRestoreHandler { fullMicroRestoreHandler(); return }
    guard canRestoreMicro, let current = original, let recovery = microRecovery else { return }
    busy = true
    error = nil
    Task {
      defer { busy = false }
      do {
        let planned = try recovery.baseline.preparedForRestore(on: current)
        backupURL = try backups.save(current)
        let verified = try await controller.apply(original: current, edited: planned)
        self.original = verified
        self.edited = verified
        try microRepository.clear()
        microRecovery = nil
        microHardwareConfirmed = false
        status = "Respaldo anterior a Micro restaurado y verificado."
      } catch { self.error = error.localizedDescription }
    }
  }
  func installStaticSkin(_ baseline: Snapshot, planned: Snapshot) async throws -> Snapshot {
    guard !busy, !changed, !previewMode else { throw S136Error.message("Esperá antes de cambiar la skin.") }
    busy = true; defer { busy = false }
    backupURL = try backups.save(baseline)
    let verified = try await controller.apply(original: baseline, edited: planned)
    original = verified; edited = verified
    status = "Paleta de la skin guardada y releída."
    return verified
  }
  /// Recovery is owned by KeyboardSkinController; this mirror only registers Micro inputs.
  func adoptSkinSession(_ session: KeyboardSkinSession?, confirmed: Bool) {
    liveSkinOwnsKeyboard = session != nil
    if let session, session.skin == .codex {
      microRecovery = MicroRecovery(baseline: session.baseline, installed: session.installed,
        bindings: session.bindings, backupURL: backupURL ?? backups.directory,
        launcherColors: session.launcherColors)
      microHardwareConfirmed = confirmed
    } else { microRecovery = nil; microHardwareConfirmed = false }
    if confirmed {
      switch session?.skin ?? .normal {
      case .normal: status = "Teclas y luces anteriores restauradas y verificadas."
      case .apps: status = "Apps activa · 1–4 abren aplicaciones sin Fn."
      case .codex: status = "Codex activo · 1–4 aplicaciones · Num 1–6 funciones."
      case .claude: status = "Claude activo · 1–4 aplicaciones · Num 1–6 funciones."
      case .boca: status = "Boca activa · paleta guardada y verificada."
      case .music: status = "Música activa · audio del sistema · RGB temporal por USB."
      }
    }
  }
  func clearLegacySkinRecovery() throws { try microRepository.clear() }
  func installLiveMode(_ baseline: Snapshot) async throws -> Snapshot {
    guard !busy, !changed, !previewMode else { throw S136Error.message("Esperá antes de activar el modo de luces de computadora.") }
    busy = true; defer { busy = false }
    backupURL = try backups.save(baseline)
    let planned = try LiveLightingProfile.prepare(baseline)
    let verified = try await controller.apply(original: baseline, edited: planned)
    original = verified; edited = verified
    return verified
  }
  func restoreLiveMode(_ recovery: LiveSkinRecovery) async throws {
    try await readKeyboardForMicro()
    guard !busy, let current = original else { throw S136Error.message("No se pudo leer el teclado para restaurar la skin.") }
    busy = true; defer { busy = false }
    let planned: Snapshot
    if current.sameContents(as: recovery.baseline) { planned = current }
    else if recovery.skin == .boca { planned = try StaticLightingProfile.restore(baseline: recovery.baseline, installed: recovery.installed, current: current) }
    else { planned = try LiveLightingProfile.restore(baseline: recovery.baseline, installed: recovery.installed, current: current) }
    let verified = try await controller.apply(original: current, edited: planned)
    original = verified; edited = verified
    status = "Modo de luces anterior restaurado y verificado."
  }
  func sendLiveColors(_ colors: [UInt8], known: Snapshot, refreshOnly: Bool = false) async throws {
    guard !busy, !changed, !previewMode else { throw S136Error.message("Esperá la operación actual antes de enviar luces temporales.") }
    busy = true; defer { busy = false }
    if refreshOnly { try await controller.refreshLiveColors(on: known, colors: colors) }
    else { try await controller.sendLiveColors(on: known, colors: colors) }
  }
  func stopLiveColors(known: Snapshot) async throws {
    guard !busy, !changed, !previewMode else { throw S136Error.message("Esperá la operación actual antes de restaurar las luces.") }
    busy = true; defer { busy = false }
    // Registry IDs can change when reconnecting. Match the saved hardware and profile.
    let devices = await controller.endpoints()
    guard let endpoint = devices.first(where: { $0.isKeyboard && $0.productID == known.endpoint.productID }) else {
      throw S136Error.message("Reconectá el K628 para detener la skin y recuperar sus luces.")
    }
    var connected = known; connected.endpoint = endpoint
    try await controller.stopLiveColors(on: connected)
    let verified = try await controller.read(endpoint)
    guard verified.profile == known.profile, verified.capabilities == known.capabilities else {
      throw S136Error.message("El RGB temporal terminó, pero el perfil o hardware cambió. Se conserva el respaldo.")
    }
    endpoints = devices; selectedID = endpoint.id; original = verified; edited = verified
    status = "RGB temporal detenido · configuración leída."
  }

  func openInputSettings() { system.openInputSettings() }
  func showApplication() { system.showApplication() }
  func showBackups() {
    do {
      try backups.createDirectory()
      system.openDirectory(backups.directory)
    } catch {
      self.error = error.localizedDescription
    }
  }
}
