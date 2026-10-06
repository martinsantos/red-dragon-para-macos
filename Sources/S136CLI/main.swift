// SPDX-License-Identifier: MIT
import Foundation
import RedragonCore

@main
struct CLI {
  static func main() async {
    do {
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
      guard ["read", "restore", "verify-roundtrip", "verify-macro", "verify-micro"].contains(command),
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
