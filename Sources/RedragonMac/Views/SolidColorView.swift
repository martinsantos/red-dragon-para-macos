import AppKit
// SPDX-License-Identifier: MIT
import RedragonCore
import SwiftUI

struct SolidColorView: View {
  let snapshot: Snapshot
  @ObservedObject var store: DeviceStore
  let selectedKey: Int?
  @State private var color: Color

  private let presets: [(String, [UInt8])] = [
    ("Rojo", [255, 0, 0]), ("Naranja", [255, 110, 0]), ("Amarillo", [255, 220, 0]),
    ("Verde", [0, 255, 0]), ("Azul", [0, 0, 255]), ("Violeta", [170, 0, 255]),
    ("Rosa", [255, 0, 100]), ("Blanco", [255, 255, 255]),
  ]

  init(snapshot: Snapshot, store: DeviceStore, selectedKey: Int? = nil) {
    self.snapshot = snapshot
    self.store = store
    self.selectedKey = selectedKey
    let rgb = (snapshot.configuration[1] == 19 ? selectedKey : nil).flatMap { slot in
      snapshot.customColors.map { Array($0[slot * 3..<slot * 3 + 3]) }
    } ?? snapshot.lightingRGB
    _color = State(
      initialValue: Color(
        red: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255,
        blue: Double(rgb[2]) / 255))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(selectedKey.map { "Color de \(KeyCatalog.physicalName(slot: $0, keyboard: true))" } ?? "Cambiar el color en un clic").font(.title2.weight(.semibold))
      Text(
        selectedKey == nil ? "Elegí un color: la app activa Color fijo, apaga Multicolor y lo guarda en el \(snapshot.isKeyboard ? "teclado" : "mouse")." : "Elegí un color y se aplica a esta tecla. Al pasar a Personalizado, el resto conserva el color configurado del efecto anterior."
      ).foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
        ForEach(presets, id: \.0) { name, rgb in
          Button {
            color = Color(
              red: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255, blue: Double(rgb[2]) / 255)
            apply(rgb)
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
          apply(
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
  private func apply(_ rgb: [UInt8]) {
    if let selectedKey { store.applyKeyColor(rgb, at: selectedKey) }
    else { store.applySolidColor(rgb) }
  }
}
