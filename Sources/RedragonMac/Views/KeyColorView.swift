// SPDX-License-Identifier: MIT
import AppKit
import RedragonCore
import SwiftUI

struct KeyColorView: View {
  @ObservedObject var store: DeviceStore
  let snapshot: Snapshot
  @State private var slot = 0
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Color por tecla · paleta 1").font(.title2)
      Text(
        "Elegí una posición y su color. Al editar, se activa el efecto Personalizado con la primera paleta."
      ).foregroundStyle(.secondary)
      KeyboardDiagram(snapshot: snapshot, mode: .colors, selectedSlot: $slot)
      ColorPicker(
        "Color de \(KeyCatalog.physicalName(slot:slot,keyboard:true))",
        selection: Binding(
          get: { color(slot) },
          set: { value in
            guard let c = NSColor(value).usingColorSpace(.sRGB) else { return }
            let rgb = [c.redComponent, c.greenComponent, c.blueComponent].map {
              UInt8(max(0, min(255, ($0 * 255).rounded())))
            }
            store.edit { try $0.setKeyColor(rgb, at: slot) }
          }), supportsOpacity: false)
      Button("Usar este color en todas las teclas") {
        guard let colors = snapshot.customColors else { return }
        let rgb = Array(colors[slot * 3..<slot * 3 + 3])
        store.edit { s in for i in KeyCatalog.visibleSlots(s) { try s.setKeyColor(rgb, at: i) } }
      }
    }
  }
  private func color(_ index: Int) -> Color {
    guard let rgb = snapshot.customColors, index * 3 + 2 < rgb.count else { return .black }
    return Color(
      red: Double(rgb[index * 3]) / 255, green: Double(rgb[index * 3 + 1]) / 255,
      blue: Double(rgb[index * 3 + 2]) / 255)
  }
}
