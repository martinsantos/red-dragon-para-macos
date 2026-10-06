// SPDX-License-Identifier: MIT
import RedragonCore
import SwiftUI

struct DPIView: View {
  @ObservedObject var store: DeviceStore
  let snapshot: Snapshot
  var body: some View {
    if snapshot.isKeyboard {
      ContentUnavailableView(
        "Seleccioná el mouse", systemImage: "computermouse",
        description: Text("Los ajustes de DPI y frecuencia de respuesta pertenecen al M693."))
    } else {
      Form {
        Section("Cinco niveles de DPI") {
          ForEach(0..<5, id: \.self) { index in
            Picker(
              "Nivel \(index+1)",
              selection: Binding(
                get: { snapshot.dpi(at: index) },
                set: { value in store.edit { try $0.setDPI(value, at: index) } })
            ) {
              let current = snapshot.dpi(at: index)
              if Snapshot.dpiPresets[current] == nil {
                Text("\(current) DPI · actual").tag(current)
              }
              ForEach(Snapshot.dpiPresets.keys.sorted(), id: \.self) { Text("\($0) DPI").tag($0) }
            }
          }
        }
        Section("Frecuencia de respuesta por USB") {
          Picker(
            "Polling rate",
            selection: Binding(
              get: { Int(snapshot.configuration[11]) },
              set: { value in store.edit { $0.configuration[11] = UInt8(value) } })
          ) {
            Text("125 Hz").tag(0)
            Text("250 Hz").tag(1)
            Text("500 Hz").tag(2)
            Text("1000 Hz").tag(3)
          }
        }
        Section {
          Text(
            "Se ofrecen los cinco valores cuyo código coincide con el software original. Los valores arbitrarios y el ajuste independiente X/Y todavía no están validados."
          ).foregroundStyle(.secondary)
        }
      }.formStyle(.grouped)
    }
  }
}
