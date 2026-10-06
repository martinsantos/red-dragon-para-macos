// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import RedragonCore

final class MicroControlServer: @unchecked Sendable {
  private var descriptor: Int32 = -1
  private let directory: URL
  private let handler: @Sendable (MicroCommand) async -> MicroControlResponse
  private let queue = DispatchQueue(label: "RedragonMac.micro-control", qos: .utility)

  init(directory: URL = MicroControlSocket.directory,
       handler: @escaping @Sendable (MicroCommand) async -> MicroControlResponse) {
    self.directory = directory; self.handler = handler
  }
  func start() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                           attributes: [.posixPermissions: 0o700])
    try MicroControlSocket.validateDirectory(directory)
    let path = directory.appendingPathComponent("micro.sock").path
    var info = stat()
    if lstat(path, &info) == 0 {
      guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else {
        throw S136Error.message("El canal de comandos existente no es válido.")
      }
      // The application instance lock is already held before starting this service.
      guard unlink(path) == 0 else { throw S136Error.message("No se pudo renovar el canal local.") }
    }
    var address = try MicroControlSocket.address(in: directory)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw S136Error.message("No se pudo crear el canal de comandos.") }
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 4) == 0 else {
      Darwin.close(fd)
      throw S136Error.message("No se pudo escuchar el canal local.")
    }
    descriptor = fd
    queue.async { [handler] in
      while true {
        let client = accept(fd, nil, nil)
        if client < 0 {
          if errno == EINTR { continue }
          return
        }
        MicroControlSocket.configure(client, timeout: 2)
        do { try MicroControlSocket.validatePeer(client) }
        catch { Darwin.close(client); continue }
        do {
          let data = try MicroControlSocket.read(client, limit: 2048)
          let request = try JSONDecoder().decode(MicroControlRequest.self, from: data)
          try request.validate()
          Task {
            let response = await handler(request.command)
            Self.reply(response, to: client)
          }
        } catch {
          let message = error.localizedDescription
          Task {
            let current = await handler(.status)
            Self.reply(MicroControlResponse(ok: false, status: current.status, error: message), to: client)
          }
        }
      }
    }
  }
  private static func reply(_ response: MicroControlResponse, to fd: Int32) {
    defer { Darwin.close(fd) }
    if let data = try? JSONEncoder().encode(response) { try? MicroControlSocket.write(data, to: fd) }
  }
  deinit {
    if descriptor >= 0 { shutdown(descriptor, SHUT_RDWR); Darwin.close(descriptor) }
  }
}
