// SPDX-License-Identifier: MIT
import SwiftUI

struct ContentView: View {
  @ObservedObject var store: DeviceStore
  @StateObject private var micro = MicroStore(preview: CommandLine.arguments.contains("--micro-preview"))
  @State private var section = AppSection.mapping
  @State private var turnOffAfterRestore = false

  var body: some View {
    NavigationSplitView {
      DeviceSidebar(
        endpoints: store.endpoints, selectedID: store.selectedID,
        section: $section, canSelect: store.canRead, select: store.select)
    } detail: {
      VStack(alignment: .leading, spacing: 0) {
        if store.inputAccessDenied {
          HStack(spacing: 12) {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            Text("Para configurar teclas y luces, habilitá esta app en Monitoreo de entrada.")
              .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            Button("Abrir ajuste") { store.openInputSettings() }
          }.padding(14).background(Color.orange.opacity(0.08))
          Divider()
        }
        if micro.skinEnabled {
          CodexMicroView(store: store, micro: micro)
        } else {
          DeviceDetailView(section: section, store: store)
        }
        Divider()
        DeviceStatusBar(
          status: store.status, canDiscard: store.canDiscard,
          canApply: store.canApply, discard: store.discard, apply: store.apply)
      }
    }
    .toolbar {
      ToolbarItem {
        Picker("Modo", selection: Binding(get: { micro.skinEnabled }, set: toggleSkin)) {
          Text("Normal").tag(false)
          Text("Codex Micro").tag(true)
        }.pickerStyle(.segmented).frame(width: 225).help("Cambiar de modo dentro de esta ventana")
      }
      DeviceToolbar(
        canRead: store.canRead, hasSelection: store.selectedEndpoint != nil,
        detect: store.detect, read: store.read)
    }
    .preferredColorScheme(micro.skinEnabled ? .dark : nil)
    .task {
      if micro.skinEnabled || store.microRecovery != nil { micro.skinEnabled = true; section = .micro }
      micro.registerHardware(store.microBindingsForHotkeys)
      store.detect()
    }
    .onChange(of: store.microRecovery?.bindings) { _, bindings in
      if bindings == nil && turnOffAfterRestore {
        micro.skinEnabled = false
        section = .mapping
        turnOffAfterRestore = false
      }
    }
    .onChange(of: store.microBindingsForHotkeys) { _, bindings in micro.registerHardware(bindings) }
    .onChange(of: section) { _, section in
      if section == .micro { micro.skinEnabled = true }
      else if store.microRecovery == nil { micro.skinEnabled = false }
      else { self.section = .micro }
    }
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

  private func toggleSkin(_ enabled: Bool) {
    if !enabled, store.microRecovery != nil {
      guard store.canRestoreMicro else {
        store.error = "Seleccioná el K628 y volvé a leerlo para restaurar las teclas antes de apagar Micro."
        return
      }
      micro.syncLights = false
      turnOffAfterRestore = true
      store.restoreMicro()
      // Keep the recovery controls visible until restoration is confirmed.
      return
    }
    micro.skinEnabled = enabled
    section = enabled ? .micro : .mapping
  }
}
