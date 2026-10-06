// SPDX-License-Identifier: MIT
import Foundation
import IOKit.hid

/// One synchronous transaction owns its run loop and never seizes input devices.
final class HIDTransport {
  let device: IOHIDDevice
  let target: UInt8
  private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
  private let runLoop = CFRunLoopGetCurrent()!
  private var reply: [UInt8]?
  private var pending: [UInt8]?
  private var opened = false

  init(endpoint: Endpoint) throws {
    target = endpoint.target
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 12815] as CFDictionary)
    let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    guard let match = devices.first(where: { Self.registry($0) == endpoint.registryID }) else {
      buffer.deallocate()
      throw S136Error.message("El dispositivo se desconectó. Volvé a detectarlo.")
    }
    device = match
    let status = IOHIDDeviceOpen(device, 0)
    guard status == 0 else {
      throw S136Error.message(
        "macOS no permite abrir el dispositivo (\(String(format: "%08x", status))). En Ajustes del Sistema → Privacidad y seguridad → Monitoreo de entrada, habilitá RED DRAGON PARA MACOS. Si no aparece, agregá esta aplicación con +. Después cerrala, volvé a abrirla y pulsá Detectar."
      )
    }
    opened = true
    IOHIDDeviceRegisterInputReportCallback(
      device, buffer, 64,
      { context, result, sender, type, id, report, count in
        guard result == 0, id == 4, let context else { return }
        let transport = Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: count))
        // Ignore normal key/mouse input and stale reports from previous requests.
        if let request = transport.pending, bytes.count == 64,
          [0, 1, 2, 3, 5, 6].allSatisfy({ bytes[$0] == request[$0] }),
          transport.target == 0 || bytes[32] == transport.target
        {
          transport.reply = bytes
        }
      }, Unmanaged.passUnretained(self).toOpaque())
    IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
  }

  deinit {
    if opened {
      IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
      IOHIDDeviceClose(device, 0)
    }
    buffer.deallocate()
  }

  static func registry(_ device: IOHIDDevice) -> UInt64 {
    var id: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
    return id
  }
  func query(command: UInt8, offset: Int = 0, size: Int = 0, data: [UInt8] = []) throws -> [UInt8] {
    // Manufacturer waits 10 ms before commit so the last table write settles.
    if command == 2 { Thread.sleep(forTimeInterval: 0.01) }
    let packet = try S136Packet.make(
      command: command, offset: offset, size: size, data: data, target: target)
    pending = packet
    reply = nil
    defer { pending = nil }
    let result = packet.withUnsafeBufferPointer {
      IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 4, $0.baseAddress!, 64)
    }
    guard result == 0 else {
      throw S136Error.message("Error de escritura USB: \(String(format:"%08x", result)).")
    }
    let deadline = Date().addingTimeInterval(1.5)
    while reply == nil && Date() < deadline {
      CFRunLoopRunInMode(.defaultMode, 0.01, false)
    }
    guard let reply else {
      throw S136Error.message(
        "Sin respuesta al comando \(command), posición \(offset). Encendé el periférico y seleccioná USB o 2,4 GHz; Bluetooth no está implementado."
      )
    }
    return try S136Packet.validate(reply, request: packet)
  }
  func read(command: UInt8, offset: Int = 0, count: Int) throws -> [UInt8] {
    var bytes: [UInt8] = []
    while bytes.count < count {
      bytes += try query(
        command: command, offset: offset + bytes.count,
        size: min(target == 0 ? 56 : 24, count - bytes.count))
    }
    return bytes
  }
  func write(command: UInt8, offset: Int = 0, bytes: [UInt8]) throws {
    var i = 0
    while i < bytes.count {
      let count = min(target == 0 ? 56 : 24, bytes.count - i)
      _ = try query(
        command: command, offset: offset + i, size: count, data: Array(bytes[i..<i + count]))
      i += count
    }
  }
}
