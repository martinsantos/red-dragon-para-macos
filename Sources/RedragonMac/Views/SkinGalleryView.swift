// SPDX-License-Identifier: MIT
import RedragonCore
import SwiftUI

struct SkinGalleryView: View {
  @ObservedObject var skins: KeyboardSkinController
  @ObservedObject var audio: SystemAudio
  @ObservedObject var launchers: AppLaunchers
  @State private var selectedSlot = 1
  init(skins: KeyboardSkinController) { self.skins = skins; audio = skins.audio; launchers = skins.launchers }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          VStack(alignment: .leading, spacing: 6) {
            Text("Skins del teclado").font(.largeTitle.bold())
            Text("Luces y accesos rápidos, en una sola ventana.").foregroundStyle(.secondary)
          }
          Spacer()
          if skins.busy { ProgressView().controlSize(.small); Text("Cambiando a \((skins.requested ?? skins.active).title)…") }
          else { Label(skins.confirmed ? "Activa: \(skins.active.title)" : "\(skins.active.title) · sin confirmar", systemImage: skins.confirmed ? "checkmark.circle" : "circle.dashed").foregroundStyle(skins.confirmed ? Color.green : .secondary) }
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
          ForEach(KeyboardSkin.allCases) { skin in skinCard(skin) }
        }
        if let error = skins.transitionError {
          Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
          Text("La skin activa sigue siendo \(skins.active.title). Podés elegir otra o volver a Normal.").font(.caption).foregroundStyle(.secondary)
        }
        HStack {
          Text(skins.shortcutMessage).font(.callout)
          Spacer()
          Button("Reintentar atajo") { skins.configureHotkeys() }
          Button("Siguiente skin") { skins.select(nil) }.disabled(!skins.canSwitch)
        }
        Toggle("Auto · perfil según la aplicación activa", isOn: $skins.autoProfiles)
          .help("Codex y Claude seleccionan sus funciones. Chrome y WhatsApp seleccionan Apps. Elegir una skin manualmente desactiva Auto.")
        Text("Normal recupera tus luces y números. En las otras skins, 1–4 quedan dedicadas a abrir apps sin Fn. Si elegís varias durante una escritura, se aplica la última elección.")
          .font(.callout).foregroundStyle(.secondary)
        if skins.active.hasActionPad { ApplicationProfileView(skins: skins) }
        if let preview = preview {
          KeyboardDiagram(snapshot: preview, mode: .lighting, instruction: "Los colores muestran la skin activa. Elegí otra skin arriba para cambiar el teclado.", selectedSlot: $selectedSlot)
          Text("Vista de los colores enviados · la confirmación USB no mide el brillo físico de cada LED.").font(.caption).foregroundStyle(.secondary)
        }
        if skins.audioPanelVisible || skins.active == .music {
          GroupBox("Música · audio del sistema") {
            VStack(alignment: .leading, spacing: 12) {
              HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<audio.bands.count, id: \.self) { index in
                  RoundedRectangle(cornerRadius: 3).fill(Color.purple.gradient)
                    .frame(maxWidth: .infinity).frame(height: max(3, CGFloat(audio.bands[index])*60))
                }
              }.frame(height: 65, alignment: .bottom)
              HStack {
                Text(audio.message).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                if audio.starting { ProgressView().controlSize(.small) }
                Button(audio.connected ? "Desconectar audio" : "Conectar audio del sistema") {
                  Task { if audio.connected { await audio.stop() } else { await audio.start() } }
                }.disabled(audio.starting || skins.busy)
              }
              Text(skins.musicMessage).font(.callout).foregroundStyle(.orange)
              Text("macOS pide Grabación de pantalla y audio del sistema. Esta función procesa niveles de audio en memoria: no guarda audio, no usa el micrófono y no recibe cuadros de video. En silencio se apagan las ondas; 1–4 conservan sus colores.")
                .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
          }
        }
        GroupBox {
          VStack(alignment: .leading, spacing: 14) {
            Toggle("Accesos globales 1–4", isOn: $launchers.enabled).font(.headline)
            Text(skins.launcherKeysActive ? "Activos en el K628: pulsá 1, 2, 3 o 4, sin Fn ni Enter, desde cualquier app. Normal recupera los números." : "Elegí Apps, Codex, Claude, Boca o Música para dedicar las teclas 1–4. En Normal podés escribir sus números.")
              .font(.callout).foregroundStyle(.secondary)
            ForEach(launchers.bindings) { binding in
              HStack(spacing: 12) {
                let rgb = SkinPalette.launcherColors[binding.number-1]
                Circle().fill(Color(red: Double(rgb[0])/255, green: Double(rgb[1])/255, blue: Double(rgb[2])/255)).frame(width: 12, height: 12)
                Text("\(binding.number)").font(.system(.headline, design: .monospaced)).frame(width: 32)
                Text(binding.title).frame(maxWidth: .infinity, alignment: .leading)
                Button("Abrir") { skins.launch(binding.number) }.disabled(!launchers.enabled)
                Button("Cambiar app…") { launchers.choose(binding.number) }
              }
            }
            Text(launchers.message).font(.caption).foregroundStyle(.secondary)
            Text("Codex y Claude vuelven a su ventana existente, con el chat que dejaste abierto. Si cerraste la app, la recuperación del chat depende de ella. El primer 3 trae la última ventana de Chrome; las pulsaciones siguientes recorren sus ventanas existentes.").font(.caption).foregroundStyle(.secondary)
            HStack {
              if !launchers.accessibilityAllowed {
                Button("Habilitar Accesibilidad para recorrer Chrome") { launchers.openAccessibilitySettings() }
              }
              Spacer()
              Button("Restablecer apps") { launchers.reset() }
            }
          }.padding(8)
        }
      }.padding(28)
    }
  }
  private func skinCard(_ skin: KeyboardSkin) -> some View {
    Button {
      if skin == .music && !skins.musicAvailable { skins.audioPanelVisible = true }
      else { skins.select(skin) }
    } label: {
      VStack(alignment: .leading, spacing: 12) {
        Image(systemName: symbol(skin)).font(.title2)
        Text(skin.title).font(.headline)
        Text(description(skin)).font(.caption).foregroundStyle(.secondary).frame(height: 34, alignment: .topLeading)
        Text(skins.requested == skin ? "Pendiente…" : skins.active == skin && skins.confirmed ? "Activa" : skin == .music && !skins.musicAvailable ? "Requiere cable USB" : "Activar").font(.caption.bold())
      }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(skins.active == skin ? 0.13 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(skins.active == skin ? Color.accentColor : Color.primary.opacity(0.15)))
    }.buttonStyle(.plain).disabled(!skins.canSwitch)
      .accessibilityLabel(skin == .music && !skins.musicAvailable ? "Música requiere cable USB · mostrar instrucciones" : "Activar skin \(skin.title)")
  }
  private var preview: Snapshot? {
    guard var value = skins.store.original, value.isKeyboard, let colors = value.customColors else { return nil }
    if skins.active != .normal && !(skins.active == .codex && skins.codexChatPad) {
      value.customColors = SkinPalette.colors(for: skins.active, baseline: colors, bands: audio.connected ? audio.bands : [], launchers: launchers.enabled)
      value.configuration[1] = 19
    }
    return value
  }
  private func symbol(_ skin: KeyboardSkin) -> String {
    switch skin { case .normal: "keyboard"; case .apps: "square.grid.2x2"; case .codex: "circle.hexagongrid"; case .claude: "sparkle"; case .boca: "flag"; case .music: "waveform" }
  }
  private func description(_ skin: KeyboardSkin) -> String {
    switch skin { case .normal: "Tus luces y números"; case .apps: "1–4 · abrir aplicaciones"; case .codex: "Uso, preguntas y herramientas"; case .claude: "Chats, modelo y herramientas"; case .boca: "Azul · amarillo · azul"; case .music: "Ondas con el audio de la Mac" }
  }
}
