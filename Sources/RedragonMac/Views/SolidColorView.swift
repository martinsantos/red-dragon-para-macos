import AppKit
// SPDX-License-Identifier: MIT
import RedragonCore
import SwiftUI

struct SolidColorView: View {
  let snapshot: Snapshot
  @ObservedObject var store: DeviceStore
  @State private var color: Color

  private let presets: [(String, [UInt8])] = [
    ("Rojo", [255, 0, 0]), ("Naranja", [255, 110, 0]), ("Amarillo", [255, 220, 0]),
    ("Verde", [0, 255, 0]), ("Azul", [0, 0, 255]), ("Violeta", [170, 0, 255]),
    ("Rosa", [255, 0, 100]), ("Blanco", [255, 255, 255]),
  ]

  init(snapshot: Snapshot, store: DeviceStore) {
    self.snapshot = snapshot
    self.store = store
    _color = State(
      initialValue: Color(
        red: Double(snapshot.lightingRGB[0]) / 255, green: Double(snapshot.lightingRGB[1]) / 255,
        blue: Double(snapshot.lightingRGB[2]) / 255))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Cambiar el color en un clic").font(.title2.weight(.semibold))
      Text(
        "Elegí un color: la app activa Color fijo, apaga Multicolor y lo guarda en el \(snapshot.isKeyboard ? "teclado" : "mouse")."
      ).foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
        ForEach(presets, id: \.0) { name, rgb in
          Button {
            color = Color(
              red: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255, blue: Double(rgb[2]) / 255)
            store.applySolidColor(rgb)
          } label: {
            VStack(spacing: 8) {
              RoundedRectangle(cornerRadius: 8).fill(
                Color(
                  red: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255, blue: Double(rgb[2]) / 255
                )
              ).frame(height: 34)
              Text(name).font(.callout.weight(.medium))
            }.padding(8)
          }.buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1)))
        }
      }
      HStack {
        ColorPicker("Otro color", selection: $color, supportsOpacity: false)
        Spacer()
        Button("Usar este color") {
          guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
          store.applySolidColor(
            [c.redComponent, c.greenComponent, c.blueComponent].map {
              UInt8(max(0, min(255, ($0 * 255).rounded())))
            })
        }.buttonStyle(.borderedProminent)
      }
      if store.previewMode {
        Text("Vista previa: los colores se muestran sin escribir al hardware.").font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
