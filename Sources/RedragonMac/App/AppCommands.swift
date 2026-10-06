// SPDX-License-Identifier: MIT
import SwiftUI

struct AppCommands: Commands {
  @ObservedObject var store: DeviceStore
  @ObservedObject var mode: MicroModeController

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Detectar dispositivos", action: store.detect)
        .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!store.canRead)
      Button("Aplicar cambios", action: store.apply)
        .keyboardShortcut("s").disabled(!store.canApply)
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
