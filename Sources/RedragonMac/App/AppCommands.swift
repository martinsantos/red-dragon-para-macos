// SPDX-License-Identifier: MIT
import SwiftUI
import RedragonCore

struct AppCommands: Commands {
  @ObservedObject var store: DeviceStore
  @ObservedObject var mode: MicroModeController

  @ObservedObject var skins: KeyboardSkinController

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Detectar dispositivos", action: store.detect)
        .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!store.canRead || skins.busy)
      Button("Aplicar cambios", action: store.apply)
        .keyboardShortcut("s").disabled(!store.canApply)
    }
    CommandMenu("Skins") {
      Button("Siguiente skin · ⌘⌥F4") { skins.select(nil) }.disabled(!skins.canSwitch)
      ForEach(KeyboardSkin.allCases) { skin in
        Button("Activar \(skin.title)") { skins.select(skin) }.disabled(!skins.canSwitch)
      }
      Divider()
      Button("Mostrar Skins") { skins.galleryVisible = true; skins.showWindow() }
    }
    CommandMenu("Codex") {
      Button("Activar Codex Micro") { mode.perform(.on) }.disabled(!mode.canSwitch)
      Button("Desactivar Codex Micro") { mode.perform(.off) }.disabled(!mode.canSwitch)
      Button("Alternar modo · ⌃⌥⌘C") { mode.perform(.toggle) }.disabled(!mode.canSwitch)
      Divider()
      Button("Mostrar panel Codex") { mode.perform(.show) }
      Toggle("Avisarme cuando Codex necesite respuesta", isOn: $mode.noticesEnabled)
    }
  }
}
