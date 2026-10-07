// SPDX-License-Identifier: MIT
import SwiftUI
import RedragonCore

struct ContentView: View {
  @ObservedObject var skins: KeyboardSkinController
  @ObservedObject var mode: MicroModeController
  @ObservedObject var store: DeviceStore
  @ObservedObject var micro: MicroStore
  @State private var section = AppSection.lighting
  @State private var normalSection = AppSection.lighting

  init(skins: KeyboardSkinController) {
    self.skins = skins
    mode = skins.mode
    store = skins.store
    micro = skins.mode.micro
  }

  var body: some View {
    NavigationSplitView {
      DeviceSidebar(
        endpoints: store.endpoints, selectedID: store.selectedID,
        section: $section, canSelect: store.canRead && !skins.busy, select: store.select)
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
        if !skins.galleryVisible, !micro.skinEnabled, skins.active != .normal {
          HStack {
            Label("Skin \(skins.active.title) · volvé a Normal para editar las luces", systemImage: "paintpalette")
            Spacer(); Button("Normal · restaurar") { skins.select(.normal) }.disabled(!skins.canSwitch)
          }.padding(14).background(Color.orange.opacity(0.08))
        }
        if skins.galleryVisible {
          SkinGalleryView(skins: skins)
        } else if micro.skinEnabled {
          CodexMicroView(store: store, micro: micro, mode: mode, showLighting: {
            normalSection = .lighting
            skins.galleryVisible = false
            skins.select(.normal)
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
        Button("Skins") { skins.galleryVisible = true }
      }
      ToolbarItem {
        Picker("Skin activa", selection: Binding(get: { skins.requested ?? skins.active }, set: { skins.select($0) })) {
          ForEach(KeyboardSkin.allCases.filter { $0 != .music || skins.musicAvailable || skins.active == .music }) { skin in Text(skin.title).tag(skin) }
        }.frame(width: 165).disabled(!skins.canSwitch)
      }
      ToolbarItem {
        Button("Normal · restaurar") { skins.select(.normal) }.disabled(!skins.canSwitch)
      }
      DeviceToolbar(
        canRead: store.canRead && !skins.busy, hasSelection: store.selectedEndpoint != nil,
        detect: store.detect, read: store.read)
    }
    .overlay(alignment: .top) {
      if let notice = skins.notice {
        Text(notice).font(.headline).padding(.horizontal, 22).padding(.vertical, 12)
          .background(.regularMaterial, in: Capsule()).shadow(radius: 8).padding(.top, 8)
          .allowsHitTesting(false).accessibilityLabel(notice)
      }
    }
    .preferredColorScheme(.dark)
    .task {
      section = .skins
      skins.start()
    }
    .onChange(of: micro.skinEnabled) { _, enabled in
      if !skins.galleryVisible { section = enabled ? .micro : normalSection }
    }
    .onChange(of: section) { _, section in
      if section == .skins { skins.galleryVisible = true }
      else if section == .micro { skins.galleryVisible = false; micro.skinEnabled = true }
      else { skins.galleryVisible = false; micro.skinEnabled = false }
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

}
