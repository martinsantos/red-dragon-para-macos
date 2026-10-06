// SPDX-License-Identifier: MIT
import SwiftUI

struct ContentView: View {
  @ObservedObject var mode: MicroModeController
  @ObservedObject var store: DeviceStore
  @ObservedObject var micro: MicroStore
  @State private var section = AppSection.lighting
  @State private var normalSection = AppSection.lighting

  init(mode: MicroModeController) {
    self.mode = mode
    store = mode.store
    micro = mode.micro
  }

  var body: some View {
    NavigationSplitView {
      DeviceSidebar(
        endpoints: store.endpoints, selectedID: store.selectedID,
        section: $section, canSelect: store.canRead, select: store.select)
    } detail: {
      VStack(alignment: .leading, spacing: 0) {
        if !mode.attentionNumbers.isEmpty {
          HStack {
            Label("Codex necesita tu respuesta · Num \(mode.attentionNumbers.map(String.init).joined(separator: ", "))", systemImage: "bell.badge")
            Spacer()
            Button(store.microRecovery == nil ? "Activar Codex Micro" : "Mostrar Codex") {
              mode.perform(store.microRecovery == nil ? .on : .show)
            }.disabled(!mode.canSwitch)
            Button("Cerrar aviso") { mode.dismissAttention() }
          }.padding(14).background(Color.orange.opacity(0.08))
          Divider()
        }
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
          CodexMicroView(store: store, micro: micro, mode: mode, showLighting: {
            normalSection = .lighting
            toggleSkin(false)
          })
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
        Button(store.microRecovery == nil ? "Activar Codex Micro" : "Desactivar Codex Micro") {
          mode.perform(.toggle)
        }.disabled(!mode.canSwitch).help("⌃⌥⌘C · activa o restaura el teclado")
      }
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
      mode.start()
    }
    .onChange(of: micro.skinEnabled) { _, enabled in section = enabled ? .micro : normalSection }
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
      mode.perform(.off)
      return
    }
    micro.skinEnabled = enabled
    section = enabled ? .micro : normalSection
  }
}
