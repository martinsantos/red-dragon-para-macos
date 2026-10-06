// SPDX-License-Identifier: MIT
import Foundation
import RedragonCore

@main
struct CLI {
  static func main() async {
    do {
      if ["skin", "launch", "audio"].contains(CommandLine.arguments.dropFirst().first ?? "") {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let commands: [String: MicroCommand] = ["next": .skinNext, "normal": .skinNormal, "codex": .skinCodex, "boca": .skinBoca, "music": .skinMusic, "status": .status, "show": .skinsShow]
        let audio: [String: MicroCommand] = ["on": .audioOn, "off": .audioOff, "status": .status]
        let launches: [String: MicroCommand] = ["f1": .launchF1, "f2": .launchF2, "f3": .launchF3, "f4": .launchF4]
        guard arguments.count >= 2, arguments.dropFirst(2).allSatisfy({ $0 == "--json" }),
          let command = (arguments[0] == "skin" ? commands : arguments[0] == "audio" ? audio : launches)[arguments[1]] else {
          throw S136Error.message("Uso: s136ctl skin next|normal|codex|boca|music|status|show [--json] | launch f1|f2|f3|f4 [--json] | audio on|off|status [--json]")
        }
        let response = try MicroControlSocket.send(command)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if arguments.contains("--json") { print(String(decoding: try encoder.encode(response), as: UTF8.self)) }
        else { print("Skin: \(response.status.skin ?? "unknown") · \(response.status.message)") }
        if !response.ok { throw S136Error.message(response.error ?? "No se confirmó el comando.") }
        return
      }
      if CommandLine.arguments.dropFirst().first == "micro" {
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        guard let first = arguments.first, let command = MicroCommand(rawValue: first),
              [.on, .off, .toggle, .status, .show].contains(command),
              arguments.dropFirst().allSatisfy({ $0 == "--json" }) else {
          throw S136Error.message("Uso: s136ctl micro on|off|toggle|status|show [--json]")
        }
        let response = try MicroControlSocket.send(command)
        if arguments.contains("--json") {
          let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
          print(String(decoding: try encoder.encode(response), as: UTF8.self))
        } else {
          print("Micro: \(response.status.hardwareActive ? "ACTIVO" : response.status.recoveryPending ? "RECUPERACIÓN PENDIENTE" : "DESACTIVADO") · \(response.status.message)")
          if let error = response.error { FileHandle.standardError.write(Data((error + "\n").utf8)) }
        }
        if !response.ok { exit(1) }
        return
      }
      if CommandLine.arguments.dropFirst().first == "codex-state", CommandLine.arguments.count == 3 {
        let reader = CodexRolloutReader(url: URL(fileURLWithPath: CommandLine.arguments[2]))
        let state = try await reader.read()
        print("thread=\(state.threadID ?? "unknown") state=\(state.state.rawValue) pendingQuestions=\(state.pendingQuestions.count)")
        return
      }
      let controller = HardwareController()
      let endpoints = await controller.endpoints()
      let command = CommandLine.arguments.dropFirst().first ?? "list"
      if command == "list" {
        for endpoint in endpoints { print(endpoint.id, endpoint.title) }
        return
      }
      guard ["read", "restore", "verify-roundtrip", "verify-macro", "verify-micro", "verify-live", "verify-live-mode", "verify-boca"].contains(command),
        CommandLine.arguments.count >= 3,
        let endpoint = endpoints.first(where: { $0.id == CommandLine.arguments[2] })
      else {
        throw S136Error.message(
          "Uso: s136ctl list | read ID | restore ID RESPALDO.json | verify-roundtrip ID DIRECTORIO_RESPALDO"
        )
      }
      let snapshot = try await controller.read(endpoint)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      if command == "verify-boca" {
        guard snapshot.isKeyboard, CommandLine.arguments.count == 4 else { throw S136Error.message("Uso: verify-boca ID DIRECTORIO") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try SnapshotFile.save(snapshot, to: folder.appendingPathComponent("before-boca.json"))
        var planned = snapshot
        planned.configuration[1] = 19; planned.configuration[2] = 4; planned.configuration[22] = 0
        planned.customColors = SkinPalette.colors(for: .boca, baseline: snapshot.customColors ?? [], launchers: true)
        let installed = try await controller.apply(original: snapshot, edited: planned)
        print("READY: Boca paleta guardada, azul/amarillo/azul durante 60 segundos."); fflush(stdout)
        try? await Task.sleep(for: .seconds(60))
        let restored = try await controller.apply(original: installed, edited: snapshot)
        guard restored.sameContents(as: snapshot) else { throw S136Error.message("Restauración Boca sin confirmar.") }
        print("PASS: Boca escrita, releída y restaurada byte por byte.")
        return
      }
      if command == "verify-live" || command == "verify-live-mode" {
        guard snapshot.isKeyboard, CommandLine.arguments.count == 4 else {
          throw S136Error.message("Uso: s136ctl verify-live ID DIRECTORIO_RESPALDO")
        }
        let folder = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try SnapshotFile.save(snapshot, to: folder.appendingPathComponent("before-live.json"))
        var live = snapshot
        if command == "verify-live-mode" {
          var planned = snapshot; planned.configuration[1] = 29; planned.configuration[2] = 4
          live = try await controller.apply(original: snapshot, edited: planned)
          try SnapshotFile.save(live, to: folder.appendingPathComponent("installed-live-mode.json"))
        }
        do {
          for color: [UInt8] in [[0, 80, 255], [255, 190, 0], [0, 80, 255]] {
            let frame = (0..<128).flatMap { _ in color }
            let started = Date()
            try await controller.sendLiveColors(on: live, colors: frame)
            print("Live RGB frame acknowledged in \(Date().timeIntervalSince(started)) s"); fflush(stdout)
            try await Task.sleep(for: .seconds(command == "verify-live-mode" ? 8 : 0.5))
          }
          try await controller.stopLiveColors(on: live)
        } catch {
          try? await controller.stopLiveColors(on: live)
          if command == "verify-live-mode" { _ = try? await controller.apply(original: live, edited: snapshot) }
          throw error
        }
        if command == "verify-live-mode" { _ = try await controller.apply(original: live, edited: snapshot) }
        let after = try await controller.read(endpoint)
        try SnapshotFile.save(after, to: folder.appendingPathComponent("after-live.json"))
        guard after.sameContents(as: snapshot) else { throw S136Error.message("El canal temporal alteró ajustes persistentes: conservar respaldo.") }
        print("PASS: live 0x12 / stop 0x13 acknowledged; all persistent buffers unchanged.")
        return
      }
      if command == "verify-micro" {
        guard snapshot.isKeyboard, CommandLine.arguments.count == 4 else {
          throw S136Error.message("Uso: s136ctl verify-micro ID_TECLADO DIRECTORIO_RESPALDO")
        }
        let folder = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try SnapshotFile.save(snapshot, to: folder.appendingPathComponent("keyboard-before-micro.json"))
        var bindings = MicroBinding.defaults
        bindings[0].action = .localChat
        var planned = try CodexMicroProfile.prepare(snapshot, bindings: bindings)
        planned = try CodexMicroProfile.withStates([.thinking, .attention, .complete, .idle, .failed, .disconnected], on: planned)
        let applied = try await controller.apply(original: snapshot, edited: planned)
        print("READY: Num 1 azul, 2 ámbar, 3 verde, 4 blanco, 5 rojo, 6 apagado. Pulsá Num 1; se restaurará en hasta 45 segundos.")
        fflush(stdout)
        let observed = await controller.waitForKeypad1(endpoint, seconds: 45)
        let restored = try await controller.apply(original: applied, edited: snapshot)
        guard restored.sameContents(as: snapshot) else { throw S136Error.message("La restauración Micro no coincide con el respaldo.") }
        print("PASS: perfil Micro escrito, releído y ajustes originales restaurados byte por byte.")
        print(observed ? "PASS: Num 1 emitió la tecla normal del pad desde el teclado." : "NOT VERIFIED: no se observó Num 1 durante la prueba.")
        return
      }
      if command == "restore" {
        guard CommandLine.arguments.count == 4 else {
          throw S136Error.message("Indicá un respaldo JSON.")
        }
        let backup = try SnapshotFile.load(URL(fileURLWithPath: CommandLine.arguments[3]))
          .preparedForRestore(on: snapshot)
        _ = try await controller.apply(original: snapshot, edited: backup)
        print("PASS: respaldo restaurado y verificado byte por byte.")
        return
      }
      if command == "verify-roundtrip" || command == "verify-macro" {
        guard CommandLine.arguments.count == 4 else {
          throw S136Error.message(
            "Indicá un directorio para el respaldo antes de probar escrituras.")
        }
        let folder = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(
          to: folder.appendingPathComponent(
            "\(snapshot.isKeyboard ? "keyboard" : "mouse")-before-roundtrip.json"), options: .atomic
        )
        var edited = snapshot
        edited.configuration[2] = snapshot.configuration[2] == 3 ? 4 : 3
        try edited.assign(0x200068, to: snapshot.isKeyboard ? 0 : 1)
        if !snapshot.isKeyboard {
          try edited.setDPI(snapshot.dpi(at: 0) == 1200 ? 800 : 1200, at: 0)
          edited.configuration[11] = snapshot.configuration[11] == 2 ? 3 : 2
        }
        if snapshot.isKeyboard { try edited.setKeyColor([20, 120, 255], at: 0) }
        try edited.appendMacro(
          events: [MacroEvent(button: 0x68, down: true), MacroEvent(button: 0x68, down: false)],
          to: snapshot.isKeyboard ? 0 : 1)
        let changed = try await controller.apply(original: snapshot, edited: edited)
        print(
          "PASS: memoria de macros, asignación de macro"
            + (snapshot.isKeyboard ? ", color por tecla" : "") + ", iluminación, asignación"
            + (snapshot.isKeyboard ? "" : ", DPI y polling") + " escritos y releídos.")
        var executed: Bool? = nil
        if command == "verify-macro" {
          print(
            "READY: pulsá \(snapshot.isKeyboard ? "Esc en el teclado" : "la rueda del mouse") en los próximos 45 segundos."
          )
          fflush(stdout)
          executed = await controller.waitForF13(endpoint)
        }
        let restored = try await controller.apply(original: changed, edited: snapshot)
        guard restored.sameContents(as: snapshot) else {
          throw S136Error.message("La restauración no coincide con el respaldo.")
        }
        print(
          "PASS: configuración, mapa, macros y colores originales restaurados y verificados byte por byte."
        )
        if let executed {
          print(
            executed
              ? "PASS: macro emitió F13 desde el hardware."
              : "NOT VERIFIED: no se observó F13; la macro quedó restaurada.")
        }
        return
      }
      print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
    } catch {
      FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      exit(1)
    }
  }
}
