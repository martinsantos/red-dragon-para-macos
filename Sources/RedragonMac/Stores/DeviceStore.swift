// SPDX-License-Identifier: MIT
import Combine
import Foundation
import RedragonCore

@MainActor
final class DeviceStore: ObservableObject {
  private let controller: HardwareController
  private let backups: BackupRepository
  private let system = MacSystemIntegration()

  @Published private(set) var endpoints: [Endpoint] = []
  @Published private(set) var selectedID: String?
  @Published private(set) var original: Snapshot?
  @Published private(set) var edited: Snapshot?
  @Published private(set) var busy = false
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
  var canApply: Bool { !busy && !previewMode && changed }
  var canDiscard: Bool { !busy && changed }

  init(
    controller: HardwareController = HardwareController(),
    backups: BackupRepository = BackupRepository(), arguments: [String] = CommandLine.arguments
  ) {
    self.controller = controller
    self.backups = backups
    previewMode = arguments.contains("--preview")
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
        status =
          "Leído · perfil \(snapshot.profile + 1) · \(snapshot.isKeyboard ? "teclado" : "mouse")"
      } catch {
        self.error = error.localizedDescription
        status = "No se pudo leer el dispositivo."
      }
    }
  }

  func edit(_ action: (inout Snapshot) throws -> Void) {
    guard !busy, var snapshot = edited else { return }
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
    guard !busy, !changed, let original,
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
    guard !busy, let original, let edited else { return }
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
