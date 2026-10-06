// SPDX-License-Identifier: MIT
import SwiftUI

struct AppCommands: Commands {
  @ObservedObject var store: DeviceStore

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Detectar dispositivos", action: store.detect)
        .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!store.canRead)
      Button("Aplicar cambios", action: store.apply)
        .keyboardShortcut("s").disabled(!store.canApply)
    }
  }
}
