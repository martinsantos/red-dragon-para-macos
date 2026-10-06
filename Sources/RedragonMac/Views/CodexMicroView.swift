// SPDX-License-Identifier: MIT
import SwiftUI
import RedragonCore
import CoreGraphics

struct CodexMicroView: View {
  @ObservedObject var store: DeviceStore
  @ObservedObject var micro: MicroStore
  @ObservedObject var bridge: MicroBridge
  @ObservedObject var router: LocalCodexRouter
  @ObservedObject var mode: MicroModeController
  @ObservedObject var notifications: MicroNotifications
  let showLighting: () -> Void
  @State private var showConnection = false

  init(store: DeviceStore, micro: MicroStore, mode: MicroModeController, showLighting: @escaping () -> Void) {
    self.store = store
    self.micro = micro
    bridge = micro.bridge
    router = micro.router
    self.mode = mode
    notifications = mode.notifications
    self.showLighting = showLighting
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        header
        hardwareBar
        VStack(alignment: .leading, spacing: 8) {
          Text(mode.shortcutMessage).font(.callout.weight(.medium))
          Text(mode.commandMessage).font(.caption.monospaced()).foregroundStyle(.secondary)
          Toggle("Avisarme cuando Codex necesite respuesta", isOn: $mode.noticesEnabled)
            .disabled(store.previewMode)
          if mode.noticesEnabled { Text(notifications.permissionMessage).font(.caption).foregroundStyle(.secondary) }
        }
        Text("Estos botones seleccionan la tecla que querés configurar. Para cambiar el RGB del teclado, usá Cambiar luces.")
          .font(.caption).foregroundStyle(.secondary)
        HStack(alignment: .top, spacing: 22) {
          VStack(alignment: .leading, spacing: 14) {
            HStack {
              Text("AGENTES / PREFUNCIONES").font(.caption.monospaced()).foregroundStyle(.secondary)
              Spacer()
              Text("PAD NUMÉRICO").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
              ForEach(CodexMicroProfile.displayOrder, id: \.self) { number in
                agentKey(micro.bindings[number - 1])
              }
            }
            commandBar
            HStack(spacing: 14) {
              ForEach([MicroState.idle, .thinking, .attention, .complete, .failed], id: \.self) { state in
                HStack(spacing: 5) {
                  Circle().fill(color(state)).frame(width: 6, height: 6)
                  Text(state.title).font(.caption2)
                }
              }
            }.foregroundStyle(.secondary)
            Text(micro.message).font(.callout).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity)
          inspector.frame(width: 290)
        }
        Toggle("Luces del teclado según los estados conectados", isOn: $micro.syncLights)
          .disabled(!store.microOwnsSelected || store.previewMode)
          .help("Activa la paleta por tecla de los chats conectados al enrutador.")
        if store.microRecovery != nil {
          DisclosureGroup("Recuperación del teclado") {
            VStack(alignment: .leading, spacing: 8) {
              Text("Si cambiaste ajustes con otra app, podés recuperar todo el respaldo anterior a Micro. Esto reemplaza las modificaciones posteriores; se guarda primero una copia del estado actual.")
                .font(.caption).foregroundStyle(.secondary)
              Button("Restaurar respaldo completo anterior a Micro") {
                micro.syncLights = false
                store.restoreFullMicroBackup()
              }.disabled(!store.canRestoreMicro)
            }.padding(.top, 8)
          }.font(.callout)
        }
        DisclosureGroup("Estados en vivo · conexión opcional", isExpanded: $showConnection) {
          connection.padding(.top, 12)
        }.font(.callout)
        Text("Skin inspirada en Codex Micro. Redragon no tiene la integración nativa del dispositivo de Work Louder. La skin puede usarse sin activar el teclado.")
          .font(.caption).foregroundStyle(.secondary)
      }.padding(28)
    }
    .background(Color(red: 0.045, green: 0.05, blue: 0.07))
    .alert("Modo Codex Micro", isPresented: Binding(get: { micro.error != nil }, set: { if !$0 { micro.error = nil } })) {
      if micro.error?.contains("Accesibilidad") == true {
        Button("Abrir Accesibilidad") { micro.openAccessibility() }
      }
      Button("Aceptar", role: .cancel) { micro.error = nil }
    } message: { Text(micro.error ?? "") }
  }

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 8) {
        Text("RED DRAGON / macOS").font(.caption.monospaced()).tracking(2).foregroundStyle(.secondary)
        Text("CODEX MICRO").font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-1)
        Text("Tus chats y prefunciones, a un toque.").foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 7) {
        Label(store.microHardwareConfirmed ? "Teclado Micro activo" : store.inputAccessDenied ? "Sin acceso al teclado" : "Micro en pantalla", systemImage: "circle.hexagongrid.fill")
          .font(.caption.weight(.medium)).foregroundStyle(store.microHardwareConfirmed ? Color.mint : .orange)
        Label(router.routes.isEmpty ? bridge.status : "Enrutador local · \(router.threadIDs.count) chat(s)", systemImage: router.routes.isEmpty && !bridge.connected ? "link.badge.plus" : "link")
          .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: 260, alignment: .trailing)
      }
    }
  }

  private func agentKey(_ binding: MicroBinding) -> some View {
    let state = micro.state(for: binding)
    let selected = micro.selectedNumber == binding.number
    return Button { micro.selectedNumber = binding.number } label: {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text(String(format: "%02d", binding.number)).font(.system(size: 28, weight: .semibold, design: .monospaced))
          Spacer()
          Circle().fill(state == .disconnected ? Color.gray.opacity(0.35) : color(state)).frame(width: 10, height: 10)
        }
        Text(binding.title.isEmpty ? "Botón \(binding.number)" : binding.title)
          .font(.headline).lineLimit(1)
        HStack(spacing: 5) {
          Image(systemName: binding.action == .prompt ? "doc.on.clipboard" : "bubble.left")
          Text(binding.action == .prompt ? "Prefunción" : binding.action == .localChat ? "Chat conectado" : binding.action == .indicator ? "Solo indicador" : "Chat reciente \(binding.number)").lineLimit(1)
        }.font(.caption).foregroundStyle(.secondary)
        Text(state.title).font(.caption2).foregroundStyle(state == .disconnected ? Color.secondary : color(state))
      }
      .padding(16).frame(maxWidth: .infinity, minHeight: 143, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(selected ? 0.095 : 0.045)))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.mint : Color.white.opacity(0.13), lineWidth: selected ? 2 : 1))
    }.buttonStyle(.plain)
      .accessibilityLabel("Num \(binding.number), \(binding.title), \(state.title)")
      .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var inspector: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("NUM \(micro.selectedNumber)").font(.caption.monospaced()).foregroundStyle(.mint)
      TextField("Nombre", text: $micro.bindings[micro.selectedNumber - 1].title).textFieldStyle(.roundedBorder)
      Picker("Al pulsar", selection: $micro.bindings[micro.selectedNumber - 1].action) {
        ForEach(MicroBinding.Action.allCases, id: \.self) { Text($0.title).tag($0) }
      }.pickerStyle(.menu)
      if micro.selected.action == .prompt {
        Text("Prefunción cargada").font(.caption).foregroundStyle(.secondary)
        TextEditor(text: $micro.bindings[micro.selectedNumber - 1].prompt)
          .font(.system(size: 12)).frame(height: 155)
          .padding(5).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        Text("Se copia al portapapeles y abre Codex. Pegá con ⌘V; vos elegís cuándo enviarla.")
          .font(.caption).foregroundStyle(.secondary)
      } else if micro.selected.action == .recentChat {
        Text("Num \(micro.selectedNumber) enviará ⌘⌥\(micro.selectedNumber). Codex abre el chat reciente de esa posición cuando está al frente.")
          .font(.callout).foregroundStyle(.secondary)
      } else if micro.selected.action == .localChat {
        Text("Abre el chat exacto conectado a esta tecla. Conectá su registro local abajo.")
          .font(.callout).foregroundStyle(.secondary)
      } else {
        Text("La luz sigue al chat conectado. Pulsar esta tecla no envía ninguna acción.")
          .font(.callout).foregroundStyle(.secondary)
      }
      Button(micro.selected.action == .prompt ? "Copiar prefunción" : "Abrir chat") {
        micro.perform(micro.selected)
      }.buttonStyle(.borderedProminent).tint(.mint).disabled(micro.selected.action == .indicator)
      Divider()
      Text("Enrutador local de estados").font(.caption.weight(.medium))
      if let route = router.routes.first(where: { $0.number == micro.selectedNumber }) {
        Text("Chat \(router.threadIDs[micro.selectedNumber]?.prefix(8) ?? "local")")
          .font(.caption2.monospaced()).foregroundStyle(.secondary).help(route.file.path)
        if let issue = router.issues[micro.selectedNumber] {
          Text(issue).font(.caption).foregroundStyle(.orange)
        } else if let date = router.eventDates[micro.selectedNumber] {
          Text("Último evento: \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
        }
        Button("Desconectar este chat") { router.detach(micro.selectedNumber) }
      }
      Button("Conectar chat local…") { router.chooseFile(for: micro.selectedNumber) }
      Text("Lee inicio, fin y preguntas pendientes del registro de este chat. Es el último estado observado; no confirma errores ni aprobaciones que el registro no exponga.")
        .font(.caption).foregroundStyle(.secondary)
      if bridge.connected {
        Divider()
        Picker("Estado a seguir", selection: $micro.bindings[micro.selectedNumber - 1].threadID) {
          Text("Sin asignar").tag("")
          if !micro.selected.threadID.isEmpty && !bridge.threads.contains(where: { $0.id == micro.selected.threadID }) {
            Text("Chat no disponible").tag(micro.selected.threadID)
          }
          ForEach(bridge.threads) { thread in Text(thread.title).tag(thread.id) }
        }
        Text("Elegí el chat del servidor que corresponde a esta tecla. La lista puede diferir de los recientes de la app.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.padding(18).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
  }

  private var commandBar: some View {
    HStack(spacing: 8) {
      command("Nuevo chat", "plus.bubble", key: 45, flags: [.maskCommand])
      command("Requiere atención", "bell", key: 0, flags: [.maskCommand, .maskAlternate])
      command("Dictar", "mic", key: 2, flags: [.maskControl, .maskShift])
      command("Modelo", "dial.medium", key: 46, flags: [.maskControl, .maskShift])
    }.controlSize(.large)
  }
  private func command(_ name: String, _ symbol: String, key: UInt16, flags: CGEventFlags) -> some View {
    Button { micro.command(key: key, flags: flags.rawValue, name: name) } label: {
      Label(name, systemImage: symbol).font(.caption)
    }.buttonStyle(.bordered).help("Envía el atajo configurado por defecto en Codex. Requiere Accesibilidad.")
  }

  private var hardwareBar: some View {
    HStack(spacing: 16) {
      Image(systemName: "keyboard").font(.title2).foregroundStyle(.mint)
      VStack(alignment: .leading, spacing: 5) {
        Text(store.inputAccessDenied ? "El teclado está bloqueado por macOS" : store.microRecovery == nil ? "Control del teclado K628" : "Teclado en modo Micro").font(.headline)
        Text(store.microRecovery == nil
          ? (store.inputAccessDenied ? "Renová el permiso de esta versión para cambiar sus luces y teclas." : "Cambiar luces abre los colores del teclado. Activar Micro asigna las seis teclas y su paleta.")
          : "Las funciones quedan en el hardware. Dejá la app abierta para los chats conectados y las prefunciones.")
          .font(.caption).foregroundStyle(.secondary)
        if store.changed { Text("Aplicá o descartá los cambios pendientes antes de activar Micro.").font(.caption).foregroundStyle(.orange) }
        if store.previewMode { Text("Vista previa · no se puede activar el hardware.").font(.caption).foregroundStyle(.orange) }
      }
      Spacer()
      Button("Cambiar luces", action: showLighting).disabled(store.busy)
      if store.microRecovery == nil {
        if store.inputAccessDenied {
          Button("Habilitar acceso") { store.openInputSettings() }.buttonStyle(.borderedProminent)
        } else {
          Button("Activar Micro en teclado") {
            mode.perform(.on)
          }
            .buttonStyle(.borderedProminent).tint(.mint).disabled(!mode.canSwitch)
        }
      } else {
        VStack(alignment: .trailing, spacing: 8) {
          Button("Volver al teclado normal") { mode.perform(.off) }
            .buttonStyle(.borderedProminent).tint(.mint).disabled(!mode.canSwitch)
          if store.microRecovery?.bindings != micro.bindings {
            Button("Actualizar funciones") { store.updateMicro(micro.bindings) }.disabled(!store.canRestoreMicro)
          }
        }
      }
    }.padding(18).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
  }

  private var connection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Sigue únicamente chats cargados en el App Server al que te conectes. Un servidor nuevo no ve la actividad de esta ventana de Codex.")
        .font(.callout).foregroundStyle(.secondary)
      HStack {
        TextField("Servidor local", text: $micro.bridgeAddress).textFieldStyle(.roundedBorder).disabled(bridge.connected || bridge.connecting)
        if bridge.connected || bridge.connecting {
          Button("Desconectar") { bridge.disconnect() }
        } else { Button("Conectar") { bridge.connect(micro.bridgeAddress) } }
      }
      Text("La paleta por tecla necesita una prueba visual en tu unidad. Los cambios se agrupan y se verifican por USB. Al desconectar, las seis luces se apagan si esta opción sigue activa.")
        .font(.caption).foregroundStyle(.secondary)
      Link("Cómo conectar un App Server", destination: URL(string: "https://learn.chatgpt.com/docs/app-server")!)
    }
  }

  private func color(_ state: MicroState) -> Color {
    let rgb = state.rgb.map { Double($0) / 255 }
    return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
  }
}
