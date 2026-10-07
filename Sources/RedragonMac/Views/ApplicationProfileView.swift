// SPDX-License-Identifier: MIT
import SwiftUI
import RedragonCore

struct ApplicationProfileView: View {
  @ObservedObject var skins: KeyboardSkinController
  var body: some View {
    GroupBox("\(skins.active.title) · funciones del pad numérico") {
      VStack(alignment: .leading, spacing: 14) {
        if skins.active == .codex {
          Picker("Num 1–6", selection: $skins.codexChatPad) {
            Text("Funciones de Codex").tag(false)
            Text("Chats y prefunciones").tag(true)
          }.pickerStyle(.segmented)
        }
        if skins.active == .claude || !skins.codexChatPad {
          let actions = ApplicationPadAction.actions(for: skins.active)
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(CodexMicroProfile.displayOrder, id: \.self) { number in
              Button { skins.performPad(number) } label: {
                VStack(alignment: .leading, spacing: 8) {
                  Text("NUM \(number)").font(.caption.monospaced())
                  Text(skins.active == .claude && actions[number-1] == .dictation ? "Configurar dictado" : actions[number-1].title).font(.headline)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
              }.buttonStyle(.bordered).disabled(!skins.confirmed || skins.busy || !skins.usesFunctionPad)
                .accessibilityLabel("Num \(number) · \(skins.active == .claude && actions[number-1] == .dictation ? "Configurar dictado" : actions[number-1].title)")
            }
          }
          Text("Una pulsación física ejecuta la función desde cualquier app. Ver uso abre el panel oficial en el navegador. Pregunta pendiente trae el chat de Codex que necesita atención; elegís vos qué responder.")
            .font(.callout).foregroundStyle(.secondary)
          if skins.active == .claude {
            Text("Num 3 abre la configuración de dictado; la grabación usa el control nativo de Claude. Modelo abre el selector de su chat actual; si no está disponible, la app lo informa.")
              .font(.caption).foregroundStyle(.secondary)
          }
        } else {
          Text("Num 1–6 usan tus chats y prefunciones guardados. Abrí el panel Codex de la barra lateral para editarlos.")
            .font(.callout).foregroundStyle(.secondary)
        }
      }.padding(8)
    }
  }
}
