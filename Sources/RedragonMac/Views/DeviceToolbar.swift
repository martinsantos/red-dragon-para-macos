// SPDX-License-Identifier: MIT
import SwiftUI

struct DeviceToolbar: ToolbarContent {
  let canRead: Bool
  let hasSelection: Bool
  let detect: () -> Void
  let read: () -> Void

  var body: some ToolbarContent {
    ToolbarItemGroup {
      Button("Detectar", systemImage: "arrow.triangle.2.circlepath", action: detect).disabled(
        !canRead)
      Button("Leer del dispositivo", systemImage: "arrow.down.circle", action: read).disabled(
        !canRead || !hasSelection)
    }
  }
}
