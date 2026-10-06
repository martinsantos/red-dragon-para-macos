// SPDX-License-Identifier: MIT
import SwiftUI

struct ContentView: View {
  @ObservedObject var store: DeviceStore
  @State private var section = AppSection.mapping

  var body: some View {
    NavigationSplitView {
      DeviceSidebar(
        endpoints: store.endpoints, selectedID: store.selectedID,
        section: $section, canSelect: store.canRead, select: store.select)
    } detail: {
      VStack(alignment: .leading, spacing: 0) {
        DeviceDetailView(section: section, store: store)
        Divider()
        DeviceStatusBar(
          status: store.status, canDiscard: store.canDiscard,
          canApply: store.canApply, discard: store.discard, apply: store.apply)
      }
    }
    .toolbar {
      DeviceToolbar(
        canRead: store.canRead, hasSelection: store.selectedEndpoint != nil,
        detect: store.detect, read: store.read)
    }
    .task { store.detect() }
    .alert(
      store.needsInputPermission ? "Habilitá el acceso al kit" : "No se pudo completar",
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    ) {
      if store.needsInputPermission {
        Button("Abrir Monitoreo de entrada") {
          store.openInputSettings()
          store.error = nil
        }
      }
      Button("Aceptar", role: .cancel) { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
  }
}
