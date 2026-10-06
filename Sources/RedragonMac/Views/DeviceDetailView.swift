// SPDX-License-Identifier: MIT
import SwiftUI

struct DeviceDetailView: View {
  let section: AppSection
  @ObservedObject var store: DeviceStore

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(section.rawValue).font(.largeTitle.weight(.semibold))
          Text(
            store.edited.map { ($0.isKeyboard ? "K628" : "M693") + " · Perfil \($0.profile + 1)" }
              ?? "Redragon S136"
          )
          .foregroundStyle(.secondary)
        }
        Spacer()
        if store.busy { ProgressView().controlSize(.small) }
        if store.changed { Text("Cambios pendientes").font(.caption).foregroundStyle(.orange) }
      }
      .padding(28)
      Divider()
      ScrollView {
        DeviceFeatureView(section: section, store: store)
          .padding(28)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .disabled(store.busy || store.microOwnsSelected)
    }
  }
}

private struct DeviceFeatureView: View {
  let section: AppSection
  @ObservedObject var store: DeviceStore

  var body: some View {
    if section == .backup {
      BackupView(store: store)
    } else if section == .macros {
      MacroView(store: store).id(store.selectedID)
    } else if let snapshot = store.edited {
      switch section {
      case .lighting: LightingView(store: store, snapshot: snapshot)
      case .dpi: DPIView(store: store, snapshot: snapshot)
      default: MappingView(store: store, snapshot: snapshot).id(store.selectedID)
      }
    } else if store.inputAccessDenied {
      ContentUnavailableView("macOS bloqueó el acceso al teclado", systemImage: "lock.shield",
        description: Text("Quitá la entrada anterior de esta app en Monitoreo de entrada y agregá esta versión. Después cerrala, reabrila y pulsá Detectar. Los controles de luces aparecerán al leer el dispositivo."))
    } else {
      ContentUnavailableView(
        "Leé el dispositivo", systemImage: "cable.connector",
        description: Text(
          "Conectá el receptor o el mouse por USB y pulsá Detectar. Seleccioná el modo 2,4 GHz en el teclado."
        ))
    }
  }
}
