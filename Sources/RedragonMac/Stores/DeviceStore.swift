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
  let previewMode: Bool

  var changed: Bool {
    guard let original, let edited else { return false }
    return !original.sameContents(as: edited)
  }
  var selectedEndpoint: Endpoint? { endpoints.first { $0.id == selectedID } }
  var needsInputPermission: Bool { error?.contains("e00002e2") == true }
  var canRead: Bool { !busy && !previewMode && !changed }
  var canApply: Bool { !busy && !previewMode && changed && !microOwnsSelected }
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
        selectedID = endpoints.first(where: { $0.target == 1 })?.id ?? endpoints.first?.id
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
    guard !busy, !microOwnsSelected, var snapshot = edited else { return }
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
    guard !busy, !changed, !microOwnsSelected, let original,
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
    guard !busy, !microOwnsSelected, let original, let edited else { return }
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
    guard !busy, !microOwnsSelected, let original, let edited else { return }
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
    guard canActivateMicro, let original else { return }
    busy = true
    error = nil
    status = "Respaldando y activando las seis teclas Micro…"
    Task {
      defer { busy = false }
      do {
        let planned = try CodexMicroProfile.prepare(original, bindings: bindings)
        let backup = try backups.save(original)
        backupURL = backup
        let recovery = MicroRecovery(baseline: original, installed: planned, bindings: bindings, backupURL: backup)
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
      }
    }
  }

  func updateMicro(_ bindings: [MicroBinding], states: [MicroState]? = nil) {
    guard canRestoreMicro, let original, let previous = microRecovery else { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        var planned = try CodexMicroProfile.prepare(original, bindings: bindings)
        if let states { planned = try CodexMicroProfile.withStates(states, on: planned) }
        if planned.sameContents(as: original) && bindings == previous.bindings { return }
        var recovery = previous
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
    guard canRestoreMicro, let current = original, let recovery = microRecovery else { return }
    busy = true
    error = nil
    Task {
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
          let planned = try CodexMicroProfile.restore(baseline: baseline, installed: installed, current: current)
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
      }
    }
  }

  func restoreFullMicroBackup() {
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
