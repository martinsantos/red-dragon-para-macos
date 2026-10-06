// SPDX-License-Identifier: MIT
import Darwin
import Foundation

/// Same-user local channel. No TCP listener, commands from websites, or hardware buffers.
public enum MicroControlSocket {
  public static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("RedragonMac/control", isDirectory: true)
  }
  public static func validateDirectory(_ directory: URL) throws {
    var info = stat()
    guard lstat(directory.path, &info) == 0, info.st_uid == getuid(),
      info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else {
      throw S136Error.message("El directorio de comandos debe ser privado y pertenecer a este usuario.")
    }
  }
  public static func address(in directory: URL) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let path = Array(directory.appendingPathComponent("micro.sock").path.utf8) + [0]
    guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
      throw S136Error.message("La ruta del canal local es demasiado larga.")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: path) }
    return address
  }
  public static func configure(_ fd: Int32, timeout: Int = 35) {
    var noSignal: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    var interval = timeval(tv_sec: timeout, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
  }
  public static func validatePeer(_ fd: Int32) throws {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
      throw S136Error.message("El canal de comandos pertenece a otro usuario.")
    }
  }
  public static func read(_ fd: Int32, limit: Int = 8192) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while true {
      let count = Darwin.read(fd, &buffer, buffer.count)
      if count == 0 { return data }
      if count < 0 {
        if errno == EINTR { continue }
        throw S136Error.message("El canal de comandos dejó de responder.")
      }
      guard data.count + count <= limit else { throw S136Error.message("Comando local demasiado grande.") }
      data.append(contentsOf: buffer.prefix(count))
    }
  }
  public static func write(_ data: Data, to fd: Int32) throws {
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw S136Error.message("No se pudo enviar el comando local.") }
        offset += count
      }
    }
  }
  public static func send(_ command: MicroCommand, directory: URL = directory) throws -> MicroControlResponse {
    try validateDirectory(directory)
    let path = directory.appendingPathComponent("micro.sock").path
    var info = stat()
    guard lstat(path, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else {
      throw S136Error.message("Abrí RED DRAGON PARA MACOS 0.4.0 o posterior para usar micro on/off.")
    }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw S136Error.message("No se pudo abrir el canal local.") }
    defer { Darwin.close(fd) }
    configure(fd)
    var address = try address(in: directory)
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else { throw S136Error.message("La app no está abierta o todavía está arrancando.") }
    try validatePeer(fd)
    try write(JSONEncoder().encode(MicroControlRequest(command)), to: fd)
    shutdown(fd, SHUT_WR)
    return try JSONDecoder().decode(MicroControlResponse.self, from: read(fd))
  }
}
