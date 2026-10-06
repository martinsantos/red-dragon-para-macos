import Foundation
import RedragonCore

func expectEqual<T: Equatable>(
  _ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line
) {
  guard actual == expected else {
    fatalError("Expected \(expected), got \(actual)", file: file, line: line)
  }
}
func expectFailure<T>(
  _ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line
) {
  do { _ = try expression() } catch { return }
  fatalError("Expected rejection of invalid input", file: file, line: line)
}

final class ProtocolChecks {
  func testKnownCapabilitiesQueryForReceiver() throws {
    let packet = try S136Packet.make(command: 3, size: 24, target: 1)
    expectEqual(Array(packet.prefix(8)), [4, 27, 0, 3, 24, 0, 0, 0])
    expectEqual(packet[32], 1)
    expectEqual(packet.count, 64)
  }
  func testChecksumAndLittleEndianOffset() throws {
    let packet = try S136Packet.make(
      command: 6, offset: 0x1234, size: 3, data: [255, 128, 1], target: 2)
    let expected = 6 + 3 + 0x34 + 0x12 + 255 + 128 + 1
    expectEqual(packet[1], UInt8(expected & 255))
    expectEqual(packet[2], UInt8(expected >> 8))
    expectEqual(packet[5], 0x34)
    expectEqual(packet[6], 0x12)
    expectEqual(Array(packet[8..<11]), [255, 128, 1])
  }
  func testRejectWrongDeviceStaleOffsetAndFirmwareErrors() throws {
    let request = try S136Packet.make(command: 5, offset: 24, size: 2, target: 1)
    var reply = request
    reply[8] = 3
    reply[9] = 4
    expectEqual(try S136Packet.validate(reply, request: request), [3, 4])
    reply[32] = 2
    expectFailure(try S136Packet.validate(reply, request: request))
    reply = request
    reply[5] = 0
    expectFailure(try S136Packet.validate(reply, request: request))
    reply = request
    reply[7] = 255
    expectFailure(try S136Packet.validate(reply, request: request))
    expectFailure(try S136Packet.make(command: 5, size: 25, target: 1))
    let wired = try S136Packet.make(command: 9, size: 56, data: Array(0..<56), target: 0)
    expectEqual(wired[32], 24)
    expectEqual(Array(wired[8...]), Array(0..<56))
    expectFailure(try S136Packet.make(command: 9, size: 57))
  }
  func testDPIChangesOnlyExpectedSensorFields() throws {
    let endpoint = Endpoint(registryID: 1, productID: 0x2225, target: 0, product: "Mouse")
    var caps = [UInt8](repeating: 0, count: 34)
    caps[8] = 1
    var snapshot = Snapshot(
      endpoint: endpoint, capabilities: caps, configuration: [UInt8](repeating: 7, count: 99),
      keymap: [UInt8](repeating: 0, count: 126))
    let before = snapshot.configuration
    try snapshot.setDPI(7200, at: 4)
    expectEqual(snapshot.dpi(at: 4), 7200)
    expectEqual(snapshot.configuration[52], 96)
    for i in 0..<99 where !(52...55).contains(i) {
      expectEqual(snapshot.configuration[i], before[i])
    }
    expectFailure(try snapshot.setDPI(900, at: 1))
  }
  func testModifierEncodingAndFnPreservation() throws {
    let endpoint = Endpoint(registryID: 1, productID: 0x50b8, target: 1, product: "Receiver")
    var caps = [UInt8](repeating: 0, count: 34)
    caps[8] = 2
    var snapshot = Snapshot(
      endpoint: endpoint, capabilities: caps, configuration: [UInt8](repeating: 0, count: 99),
      keymap: [UInt8](repeating: 0, count: 384))
    try snapshot.assign(0x200800, to: 66)
    expectEqual(snapshot.assignment(at: 66), 0x200800)
    expectEqual(Array(snapshot.keymap[198..<201]), [32, 8, 0])
    expectFailure(try snapshot.assign(0x200004, to: 74))
  }
  func testMacroWireFormatBalancedKeysAndOpaqueFields() throws {
    let endpoint = Endpoint(registryID: 1, productID: 0x2225, target: 0, product: "Mouse")
    var caps = [UInt8](repeating: 0, count: 34)
    caps[8] = 1
    var snapshot = Snapshot(
      endpoint: endpoint, capabilities: caps, configuration: [UInt8](repeating: 0, count: 99),
      keymap: [UInt8](repeating: 0, count: 126), macroData: [UInt8](repeating: 0, count: 3072))
    let events = [
      MacroEvent(delay: 10, button: 0x68, down: true),
      MacroEvent(delay: 20, button: 0x68, down: false),
    ]
    try snapshot.appendMacro(events: events, to: 1)
    let bytes = snapshot.macroData!
    expectEqual(Array(bytes.prefix(6)), [170, 85, 30, 0, 1, 0])
    expectEqual(Array(bytes[16..<18]), [18, 0])
    expectEqual(Array(bytes[18..<30]), [2, 0, 0, 0, 10, 0, 128, 104, 20, 0, 0, 104])
    expectEqual(snapshot.assignment(at: 1), 0x710001)
    expectEqual(try MacroTable(bytes: bytes).definitions[0].events, events)
    expectFailure(try snapshot.appendMacro(events: [events[0]], to: 1))
    expectFailure(try snapshot.appendMacro(events: [events[1]], to: 1))
    expectFailure(try snapshot.appendMacro(events: events, to: 1, replacing: 1))
    var broken = bytes
    broken[16] = 255
    broken[17] = 255
    expectFailure(try MacroTable(bytes: broken))
  }
  func testCustomColorPreservesOtherKeysAndSelectsBank() throws {
    let endpoint = Endpoint(registryID: 1, productID: 0x50b8, target: 1, product: "Receiver")
    var caps = [UInt8](repeating: 0, count: 34)
    caps[8] = 2
    var snapshot = Snapshot(
      endpoint: endpoint, capabilities: caps, configuration: [UInt8](repeating: 7, count: 99),
      keymap: [UInt8](repeating: 0, count: 384), customColors: [UInt8](repeating: 10, count: 384))
    try snapshot.setKeyColor([1, 2, 3], at: 74)
    expectEqual(Array(snapshot.customColors![222..<225]), [1, 2, 3])
    for i in 0..<384 where !(222..<225).contains(i) { expectEqual(snapshot.customColors![i], 10) }
    expectEqual(snapshot.configuration[1], 19)
    expectEqual(snapshot.configuration[22], 0)
    for i in 0..<99 where i != 1 && i != 22 { expectEqual(snapshot.configuration[i], 7) }
  }
  func testImportedSnapshotValidationAndRestore() throws {
    let endpoint = Endpoint(registryID: 1, productID: 0x2225, target: 0, product: "Mouse")
    var caps = [UInt8](repeating: 0, count: 34)
    caps[0] = 0xaa
    caps[1] = 0x55
    caps[4] = 32
    caps[5] = 42
    caps[6] = 24
    caps[8] = 1
    let current = Snapshot(
      endpoint: endpoint, capabilities: caps, configuration: [UInt8](repeating: 0, count: 99),
      keymap: [UInt8](repeating: 0, count: 126), macroData: [UInt8](repeating: 0, count: 3072))
    try current.validateStructure()
    var old = current
    old.macroData = nil
    old.endpoint = Endpoint(registryID: 99, productID: 0x2225, target: 0, product: "Mouse")
    let restored = try old.preparedForRestore(on: current)
    expectEqual(restored.endpoint, current.endpoint)
    expectEqual(restored.macroData, current.macroData)
    var broken = current
    broken.configuration = []
    expectFailure(try broken.validateStructure())
    broken = current
    broken.keymap = [0]
    expectFailure(try broken.validateStructure())
    broken = current
    broken.capabilities = []
    expectFailure(try broken.validateStructure())
    broken = current
    broken.macroData = [0]
    expectFailure(try broken.validateStructure())
    broken = current
    broken.customColors = [0]
    expectFailure(try broken.validateStructure())
    broken = current
    broken.configuration[0] = 1
    expectFailure(try broken.preparedForRestore(on: current))
    broken = current
    broken.endpoint = Endpoint(registryID: 1, productID: 0x50b8, target: 1, product: "Receiver")
    expectFailure(try broken.validateStructure())
  }
  func testSnapshotFileRoundTrip() throws {
    let endpoint = Endpoint(registryID: 1, productID: 0x50b8, target: 1, product: "Receiver")
    var caps = [UInt8](repeating: 0, count: 34)
    caps[0] = 0xaa
    caps[1] = 0x55
    caps[4] = 6
    caps[5] = 128
    caps[6] = 24
    caps[8] = 2
    let snapshot = Snapshot(
      endpoint: endpoint, capabilities: caps, configuration: [UInt8](repeating: 0, count: 99),
      keymap: [UInt8](repeating: 0, count: 384), macroData: [UInt8](repeating: 0, count: 3072),
      customColors: [UInt8](repeating: 0, count: 384))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      "s136-check-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    try SnapshotFile.save(snapshot, to: file)
    let loaded = try SnapshotFile.load(file)
    expectEqual(loaded.sameContents(as: snapshot), true)
    expectEqual(loaded.endpoint, snapshot.endpoint)
  }

}

let checks = ProtocolChecks()
let physicalKeys = KeyboardLayout.keys
expectEqual(physicalKeys.count, 78)
expectEqual(Set(physicalKeys.map(\.slot)).count, 78)
expectEqual(physicalKeys.first(where: { $0.slot == 69 })?.width, 6.25)
expectEqual(physicalKeys.first(where: { $0.slot == 74 })?.row, 4)
for row in 0..<KeyboardLayout.rowCount {
  let keys = physicalKeys.filter { $0.row == row }.sorted { $0.column < $1.column }
  expectEqual(keys.first?.column, 0)
  expectEqual(keys.last.map { $0.column + $0.width }, KeyboardLayout.columns)
  for i in 1..<keys.count { expectEqual(keys[i - 1].column + keys[i - 1].width, keys[i].column) }
}
try checks.testKnownCapabilitiesQueryForReceiver()
try checks.testChecksumAndLittleEndianOffset()
try checks.testRejectWrongDeviceStaleOffsetAndFirmwareErrors()
try checks.testDPIChangesOnlyExpectedSensorFields()
try checks.testModifierEncodingAndFnPreservation()
try checks.testMacroWireFormatBalancedKeysAndOpaqueFields()
try checks.testCustomColorPreservesOtherKeysAndSelectsBank()
try checks.testImportedSnapshotValidationAndRestore()
try checks.testSnapshotFileRoundTrip()
print("PASS: 10 protocol, backup and physical-layout checks.")
