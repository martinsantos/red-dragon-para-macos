// SPDX-License-Identifier: MIT
import SwiftUI

struct BackupView: View {
  @ObservedObject var store: DeviceStore
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Acceso al kit en macOS", systemImage: "keyboard.badge.ellipsis").font(.title2)
      Text(
        "Para abrir el canal USB, macOS puede exigir Monitoreo de entrada. Habilitá RED DRAGON PARA MACOS en Privacidad y seguridad; si no figura, agregá la app con +. Cerrá y abrí la aplicación después de habilitarla."
      ).foregroundStyle(.secondary)
      HStack {
        Button("Abrir Monitoreo de entrada") { store.openInputSettings() }
        Button("Mostrar esta app en Finder") { store.showApplication() }
      }
      Divider()
      Label("Una copia antes de cada cambio", systemImage: "checkmark.shield").font(.title2)
      Text(
        "La copia contiene el perfil, la iluminación, los DPI, el mapa de teclas, los colores personalizados y la memoria de macros. Podés preparar un respaldo y revisarlo antes de restaurarlo."
      ).foregroundStyle(.secondary)
      HStack {
        Button("Abrir respaldos") { store.showBackups() }
        Button("Preparar restauración…") { store.restoreBackup() }.disabled(
          store.original == nil || store.changed)
      }
      if let url = store.backupURL {
        Text("Último respaldo: \(url.lastPathComponent)").font(.caption).textSelection(.enabled)
      }
      Divider()
      Text("Compatibilidad comprobada").font(.headline)
      Text(
        "Receptor USB 320F:50B8 y mouse por cable 320F:2225. Para configurar el teclado, usá el receptor y el modo 2,4 GHz. Bluetooth y otras revisiones de hardware requieren validación."
      )
      .foregroundStyle(.secondary)
      Text("Aplicación independiente. No es software oficial de Redragon.").font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
