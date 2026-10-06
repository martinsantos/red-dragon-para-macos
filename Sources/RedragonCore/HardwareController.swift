// SPDX-License-Identifier: MIT
import Foundation
import IOKit.hid

public actor HardwareController {
  public init() {}
  public func endpoints() -> [Endpoint] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 12815] as CFDictionary)
    let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    return devices.flatMap { device -> [Endpoint] in
      let pid =
        (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
      let out =
        (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? NSNumber)?
        .intValue ?? 0
      // Only this kit's two verified endpoints can currently receive writes.
      guard out == 64, [0x2225, 0x50b8].contains(pid) else { return [] }
      let product =
        IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Redragon"
      return (pid == 0x50b8 ? [UInt8(1), 2] : [UInt8(0)]).map {
        Endpoint(
          registryID: HIDTransport.registry(device), productID: pid, target: $0, product: product)
      }
    }.sorted { $0.title < $1.title }
  }
  public func read(_ endpoint: Endpoint) throws -> Snapshot {
    try read(HIDTransport(endpoint: endpoint), endpoint: endpoint)
  }
  private func read(_ transport: HIDTransport, endpoint: Endpoint) throws -> Snapshot {
    _ = try transport.query(command: 1)
    var finished = false
    defer { if !finished { _ = try? transport.query(command: 2) } }
    let caps = try transport.read(command: 3, count: 34)
    guard caps[0] == 0xaa, caps[1] == 0x55, caps[6] == 24,
      (caps[8] == 1 && caps[4] == 32 && caps[5] == 42)
        || (caps[8] == 2 && caps[4] == 6 && caps[5] == 128)
    else {
      throw S136Error.message("Esta revisión de hardware no está reconocida.")
    }
    let profile = Int(try transport.read(command: 5, count: 1)[0])
    guard (0..<5).contains(profile) else {
      throw S136Error.message("Perfil del dispositivo inválido.")
    }
    var config = try transport.read(command: 5, offset: profile * 100, count: 99)
    config[0] = UInt8(profile)
    let map = try transport.read(command: 8, count: Int(caps[5]) * 3)
    let macros = try transport.read(command: 0x14, count: Int(caps[6]) * 128)
    let colors = caps[8] == 2 ? try transport.read(command: 0x0a, count: Int(caps[5]) * 3) : nil
    _ = try transport.query(command: 2)
    finished = true
    return Snapshot(
      endpoint: endpoint, capabilities: caps, configuration: config, keymap: map, macroData: macros,
      customColors: colors)
  }
  public func apply(original: Snapshot, edited: Snapshot) throws -> Snapshot {
    try original.validateStructure()
    try edited.validateStructure()
    guard original.endpoint == edited.endpoint, original.capabilities == edited.capabilities,
      original.profile == edited.profile, original.configuration.count == 99,
      edited.configuration.count == 99, original.keymap.count == edited.keymap.count,
      original.macroData?.count == edited.macroData?.count,
      original.customColors?.count == edited.customColors?.count
    else {
      throw S136Error.message("La copia no corresponde al dispositivo y perfil actuales.")
    }
    if original.isKeyboard && original.assignment(at: 74) != edited.assignment(at: 74) {
      throw S136Error.message("La tecla Fn debe conservar su función del firmware.")
    }
    let transport = try HIDTransport(endpoint: original.endpoint)
    let fresh = try read(transport, endpoint: original.endpoint)
    guard fresh.sameContents(as: original) else {
      throw S136Error.message(
        "Los ajustes cambiaron desde la última lectura. Volvé a leer antes de aplicar.")
    }
    do {
      _ = try transport.query(command: 1)
      try write(edited, comparedWith: original, using: transport)
      _ = try transport.query(command: 2)
      let verified = try read(transport, endpoint: original.endpoint)
      guard verified.sameContents(as: edited) else {
        throw S136Error.message("La lectura no coincide con los datos enviados.")
      }
      return verified
    } catch {
      let failure = error
      do {
        _ = try transport.query(command: 1)
        try write(original, comparedWith: nil, using: transport)
        _ = try transport.query(command: 2)
        let restored = try read(transport, endpoint: original.endpoint)
        guard restored.sameContents(as: original) else {
          throw S136Error.message("La restauración no coincide con el respaldo.")
        }
      } catch {
        throw S136Error.message(
          "\(failure.localizedDescription) No se pudo confirmar la restauración: \(error.localizedDescription) Conservá el respaldo y reconectá el kit."
        )
      }
      throw S136Error.message(
        "\(failure.localizedDescription) Se restauraron y verificaron los ajustes originales.")
    }
  }
  private func write(
    _ snapshot: Snapshot, comparedWith previous: Snapshot?, using transport: HIDTransport
  ) throws {
    // Send complete structured buffers, preserving unknown fields.
    if snapshot.configuration != previous?.configuration {
      try transport.write(command: 6, offset: snapshot.profile * 100, bytes: snapshot.configuration)
    }
    if let macros = snapshot.macroData, macros != previous?.macroData {
      try transport.write(command: 0x15, bytes: macros)
    }
    if let colors = snapshot.customColors, colors != previous?.customColors {
      // First custom bank, 512-byte stride recovered from the vendor program.
      try transport.write(command: 0x0b, bytes: colors)
    }
    if snapshot.keymap != previous?.keymap {
      try transport.write(command: 9, bytes: snapshot.keymap)
    }
  }
}
