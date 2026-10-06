// SPDX-License-Identifier: MIT
import AppKit
import RedragonCore
import SwiftUI

struct LightingView: View {
  @ObservedObject var store: DeviceStore
  let snapshot: Snapshot
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      if !snapshot.isKeyboard {
        MouseDiagram(snapshot: snapshot, lighting: true, selectedSlot: .constant(-1))
      }
      SolidColorView(snapshot: snapshot, store: store).id(store.selectedID)
      DisclosureGroup("Más efectos, brillo y velocidad") {
        Form {
          Section("Iluminación del \(snapshot.isKeyboard ? "teclado" : "mouse")") {
            Picker("Efecto", selection: byteBinding(1)) {
              let modes = snapshot.isKeyboard ? KeyCatalog.keyboardModes : KeyCatalog.mouseModes
              if !modes.contains(where: { $0.code == Int(snapshot.configuration[1]) }) {
                Text("Efecto actual \(snapshot.configuration[1])").tag(
                  Int(snapshot.configuration[1]))
              }
              ForEach(modes) { Text($0.name).tag($0.code) }
            }
            Picker("Brillo", selection: byteBinding(2)) {
              Text("Apagado").tag(0)
              ForEach(1...4, id: \.self) { Text("\($0*25)%").tag($0) }
            }
            Picker("Velocidad del efecto", selection: byteBinding(3)) {
              ForEach(0...4, id: \.self) { Text("Nivel \($0)").tag($0) }
            }
            Toggle(
              "Multicolor",
              isOn: Binding(
                get: { snapshot.lightingIsMulticolor },
                set: { value in
                  store.edit {
                    $0.configuration[5] = value ? (snapshot.isKeyboard ? 255 : 1) : 0
                    $0.configuration.replaceSubrange(6..<9, with: snapshot.lightingRGB)
                    $0.synchronizeLightingColor()
                  }
                }))
            ColorPicker(
              "Color",
              selection: Binding(
                get: {
                  Color(
                    red: Double(snapshot.lightingRGB[0]) / 255,
                    green: Double(snapshot.lightingRGB[1]) / 255,
                    blue: Double(snapshot.lightingRGB[2]) / 255)
                },
                set: { color in
                  guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                  let bytes = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
                    UInt8(max(0, min(255, ($0 * 255).rounded())))
                  }
                  store.edit { s in
                    s.configuration.replaceSubrange(6..<9, with: bytes)
                    s.configuration[5] = 0
                    s.synchronizeLightingColor()
                  }
                }), supportsOpacity: false)
          }
          Section {
            Text(
              "Los cambios se guardan en el hardware. La app lee nuevamente los ajustes después de aplicar."
            ).foregroundStyle(.secondary)

          }
        }.formStyle(.grouped)
      }
      if snapshot.isKeyboard, snapshot.customColors != nil {
        DisclosureGroup("Color distinto por tecla") {
          KeyColorView(store: store, snapshot: snapshot).id(store.selectedID)
        }
      }
    }
  }
  private func byteBinding(_ index: Int) -> Binding<Int> {
    Binding(
      get: { Int(snapshot.configuration[index]) },
      set: { value in
        store.edit {
          $0.configuration[index] = UInt8(value)
        }
      })
  }
}
