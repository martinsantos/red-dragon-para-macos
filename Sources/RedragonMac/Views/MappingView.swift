// SPDX-License-Identifier: MIT
import RedragonCore
import SwiftUI

struct MappingView: View {
  @ObservedObject var store: DeviceStore
  let snapshot: Snapshot
  @State private var selectedSlot: Int = 0
  @State private var search = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(
        snapshot.isKeyboard
          ? "Elegí una tecla y su nueva función. Las posiciones se identifican por el mapa original de tu kit."
          : "Elegí uno de los siete botones y asignale una tecla o un clic."
      )
      .foregroundStyle(.secondary)
      if snapshot.isKeyboard {
        Button("Adaptar Command y Option a Mac") {
          store.edit { s in
            try s.assign(0x200400, to: 65)
            try s.assign(0x200800, to: 66)
            try s.assign(0x208000, to: 73)
          }
        }
        Text(
          "Fn y sus combinaciones pertenecen al firmware. Los nombres de símbolos dependen de la distribución elegida en macOS."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if snapshot.isKeyboard {
        KeyboardDiagram(snapshot: snapshot, selectedSlot: $selectedSlot)
      } else {
        MouseDiagram(snapshot: snapshot, selectedSlot: $selectedSlot)
      }
      GroupBox(
        "Asignar a \(KeyCatalog.physicalName(slot:selectedSlot,keyboard:snapshot.isKeyboard))"
      ) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Función actual").foregroundStyle(.secondary)
            Spacer()
            Text(KeyCatalog.name(snapshot.assignment(at: selectedSlot))).fontWeight(.semibold)
          }
          if snapshot.isKeyboard && selectedSlot == 74 {
            Label("Fn pertenece al firmware y conserva su función.", systemImage: "lock")
              .font(.caption).foregroundStyle(.secondary)
          }
          TextField("Buscar una función…", text: $search).textFieldStyle(.roundedBorder)
          Picker(
            "Nueva función",
            selection: Binding(
              get: { snapshot.assignment(at: selectedSlot) },
              set: { code in store.edit { try $0.assign(code, to: selectedSlot) } })
          ) {
            let choices =
              (snapshot.isKeyboard ? KeyCatalog.keys : KeyCatalog.mouse + KeyCatalog.keys)
            let current = snapshot.assignment(at: selectedSlot)
            if !choices.contains(where: { $0.code == current }) {
              Text(KeyCatalog.name(current)).tag(current)
            }
            ForEach(
              choices.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            ) { choice in Text(choice.name).tag(choice.code) }
          }.disabled(snapshot.isKeyboard && selectedSlot == 74)
        }.padding(8)
      }
    }
  }
}
