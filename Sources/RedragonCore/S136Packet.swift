// SPDX-License-Identifier: MIT
import Foundation

/// Packet format recovered from S136_Setup.exe, CEevisionUSBDevice.
/// The receiver's routing byte is deliberately outside the checksum (vendor behavior).
public enum S136Packet {
  public static func make(
    command: UInt8, offset: Int = 0, size: Int = 0,
    data: [UInt8] = [], target: UInt8 = 0
  ) throws -> [UInt8] {
    guard (0...(target == 0 ? 56 : 24)).contains(size), (0...65535).contains(offset),
      data.count <= size,
      target <= 2
    else { throw S136Error.message("Parámetros USB inválidos.") }
    var p = [UInt8](repeating: 0, count: 64)
    p[0] = 4
    p[3] = command
    p[4] = UInt8(size)
    p[5] = UInt8(offset & 255)
    p[6] = UInt8(offset >> 8)
    p.replaceSubrange(8..<8 + data.count, with: data)
    let sum = p[3...].reduce(0) { $0 + Int($1) }
    p[1] = UInt8(sum & 255)
    p[2] = UInt8(sum >> 8)
    if target != 0 { p[32] = target }
    return p
  }
  public static func validate(_ reply: [UInt8], request: [UInt8]) throws -> [UInt8] {
    guard request.count == 64, reply.count == 64, reply[0] == 4, request[4] <= 56,
      [1, 2, 3, 5, 6].allSatisfy({ reply[$0] == request[$0] }),
      request[32] == 0 || request[4] > 24 || reply[32] == request[32], reply[4] == request[4]
    else {
      throw S136Error.message("La respuesta USB no coincide con la consulta.")
    }
    guard reply[7] == 0 else {
      throw S136Error.message("El dispositivo rechazó el comando (\(reply[7])).")
    }
    return Array(reply[8..<8 + Int(request[4])])
  }
}
