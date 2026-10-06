// SPDX-License-Identifier: MIT
import RedragonCore
import SwiftUI

struct MacroView: View {
  @ObservedObject var store: DeviceStore
  @State private var events: [MacroEvent] = []
  @State private var trigger = 1
  @State private var choice = 0x200004
  @State private var action = 0
  @State private var delay = 10
  @State private var repetitions = 1
  @State private var macroIndex = -1
  @State private var testText = ""
  private var table: MacroTable? { store.edited?.macroData.flatMap { try? MacroTable(bytes: $0) } }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(
        "Macros experimentales: la carga en memoria y la asignación están verificadas. Todavía falta comprobar su ejecución física. Creá pulsaciones completas o combinaciones con eventos de presionar y soltar."
      ).foregroundStyle(.secondary)
      TextField("Área para probar una macro de escritura", text: $testText).textFieldStyle(
        .roundedBorder)
      if let snapshot = store.edited, let table {
        HStack {
          Picker("Secuencia", selection: $macroIndex) {
            Text("Nueva macro").tag(-1)
            ForEach(table.definitions.indices, id: \.self) {
              Text("Macro \($0+1) · \(table.definitions[$0].events.count) eventos").tag($0)
            }
          }.onChange(of: macroIndex) { _, i in
            events = i >= 0 && i < table.definitions.count ? table.definitions[i].events : []
          }
          Button("Nueva") {
            macroIndex = -1
            events = []
          }
        }
        GroupBox("Agregar un evento") {
          VStack(alignment: .leading, spacing: 12) {
            Picker("Tecla o botón", selection: $choice) {
              ForEach(
                KeyCatalog.keys.filter { $0.code != 0x200000 }
                  + KeyCatalog.mouse.filter { $0.code >> 16 == 0x10 }
              ) { Text($0.name).tag($0.code) }
            }
            HStack {
              Picker("Acción", selection: $action) {
                Text("Pulsar y soltar").tag(0)
                Text("Presionar").tag(1)
                Text("Soltar").tag(2)
              }
              Stepper("Pausa: \(delay) ms", value: $delay, in: 0...60000, step: 10)
              Button("Agregar") { addEvent() }
            }
          }.padding(8)
        }
        GroupBox("Secuencia · \(events.count) eventos") {
          VStack(alignment: .leading, spacing: 6) {
            if events.isEmpty {
              Text("Agregá las teclas y pausas de tu macro.").foregroundStyle(.secondary)
            }
            ForEach(Array(events.enumerated()), id: \.offset) { i, event in
              HStack {
                Text("\(i+1). \(event.down ? "Presionar" : "Soltar") \(name(event))").frame(
                  maxWidth: .infinity, alignment: .leading)
                Text("\(event.delay) ms").foregroundStyle(.secondary)
                Button {
                  events.remove(at: i)
                } label: {
                  Image(systemName: "minus.circle")
                }.buttonStyle(.borderless)
              }
            }
          }.padding(8)
        }
        HStack {
          Picker("Asignar a", selection: $trigger) {
            ForEach(
              KeyCatalog.visibleSlots(snapshot).filter { !snapshot.isKeyboard || $0 != 74 },
              id: \.self
            ) { Text(KeyCatalog.physicalName(slot: $0, keyboard: snapshot.isKeyboard)).tag($0) }
          }
          Stepper("Repetir: \(repetitions)", value: $repetitions, in: 1...255)
          Button("Preparar macro") {
            store.edit {
              try $0.appendMacro(
                events: events, to: trigger, repetitions: repetitions,
                replacing: macroIndex >= 0 ? macroIndex : nil)
            }
          }.disabled(events.isEmpty)
        }
        Text(
          "Revisá el mapa y pulsá Aplicar al dispositivo. La app exige que cada tecla y botón de la secuencia termine soltado."
        ).font(.caption).foregroundStyle(.secondary)
      } else {
        ContentUnavailableView(
          "Leé la memoria del dispositivo", systemImage: "repeat",
          description: Text(
            "Las secuencias existentes se conservan. Un formato desconocido requiere revisión antes de editarlo."
          ))
      }
    }
  }
  private func addEvent() {
    let type: UInt8 = choice >> 16 == 0x10 ? 1 : 0
    let mask = (choice >> 8) & 255
    let button: UInt8 =
      type == 1
      ? UInt8(mask) : (mask == 0 ? UInt8(choice & 255) : UInt8(0xe0 + mask.trailingZeroBitCount))
    if action != 2 {
      events.append(MacroEvent(delay: UInt16(delay), type: type, button: button, down: true))
    }
    if action != 1 {
      events.append(MacroEvent(delay: UInt16(delay), type: type, button: button, down: false))
    }
  }
  private func name(_ event: MacroEvent) -> String {
    if event.type == 1 { return KeyCatalog.name(0x100000 | Int(event.button) << 8) }
    if event.type == 0 {
      return KeyCatalog.name(
        event.button >= 0xe0 && event.button <= 0xe7
          ? 0x200000 | 1 << Int(event.button - 0xe0 + 8) : 0x200000 | Int(event.button))
    }
    return "Evento \(event.type), valor \(event.button)"
  }
}
