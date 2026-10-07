import Foundation
import Darwin
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
  func testSolidColorUpdatesEffectRecordAndPreservesOtherSettings() throws {
    let endpoint = Endpoint(registryID: 1, productID: 0x50b8, target: 1, product: "Receiver")
    var caps = [UInt8](repeating: 0, count: 34)
    caps[8] = 2
    var snapshot = Snapshot(
      endpoint: endpoint, capabilities: caps, configuration: [UInt8](repeating: 7, count: 99),
      keymap: [UInt8](repeating: 0, count: 384))
    snapshot.configuration[1] = 2
    snapshot.configuration[2] = 0
    let before = snapshot.configuration
    try snapshot.setSolidColor([0, 0, 255])
    expectEqual(snapshot.configuration[1], 6)
    expectEqual(snapshot.configuration[2], 4)
    expectEqual(snapshot.configuration[5], 0)
    expectEqual(snapshot.keyboardModeColorOffset, 49)
    expectEqual(Array(snapshot.configuration[49..<54]), [7, 0, 0, 0, 255])
    expectEqual(snapshot.lightingRGB, [0, 0, 255])
    expectEqual(snapshot.lightingIsMulticolor, false)
    let changed = Set([1, 2, 5, 6, 7, 8, 50, 51, 52, 53])
    for i in before.indices where !changed.contains(i) {
      expectEqual(snapshot.configuration[i], before[i])
    }
    snapshot.capabilities[8] = 1
    let mouseBefore = snapshot.configuration
    try snapshot.setSolidColor([255, 0, 0])
    expectEqual(snapshot.configuration[1], 3)
    expectEqual(snapshot.lightingRGB, [255, 0, 0])
    expectEqual(Array(snapshot.configuration[29..<94]), Array(mouseBefore[29..<94]))
  }

}

func microFixture() -> Snapshot {
  let endpoint = Endpoint(registryID: 1, productID: 0x50b8, target: 1, product: "Receiver")
  var caps = [UInt8](repeating: 0, count: 34)
  caps[0] = 0xaa; caps[1] = 0x55; caps[4] = 6; caps[5] = 128; caps[6] = 24; caps[8] = 2
  var config = [UInt8](repeating: 7, count: 99)
  config[0] = 0; config[1] = 6; config[2] = 3
  var snapshot = Snapshot(endpoint: endpoint, capabilities: caps, configuration: config,
    keymap: [UInt8](repeating: 0, count: 384), macroData: [UInt8](repeating: 0, count: 3072),
    customColors: [UInt8](repeating: 20, count: 384))
  snapshot.keymap.replaceSubrange(222..<225, with: [0xa0, 1, 0])
  return snapshot
}

func checkMicroProfileAndRecovery() throws {
  let baseline = microFixture()
  var bindings = MicroBinding.defaults
  bindings[0].action = .localChat
  bindings[5].action = .prompt
  let installed = try CodexMicroProfile.prepare(baseline, bindings: bindings)
  expectEqual(installed.assignment(at: 63), 0x200059)
  expectEqual(installed.assignment(at: 83), 0x200c1f)
  expectEqual(installed.assignment(at: 82), 0x20005e)
  expectEqual(installed.assignment(at: 74), baseline.assignment(at: 74))
  expectEqual(installed.macroData, baseline.macroData)
  for slot in 0..<128 where !CodexMicroProfile.slots.contains(slot) {
    expectEqual(installed.assignment(at: slot), baseline.assignment(at: slot))
    expectEqual(Array(installed.customColors![slot * 3..<slot * 3 + 3]), Array(baseline.customColors![slot * 3..<slot * 3 + 3]))
  }
  expectEqual(try CodexMicroProfile.restore(baseline: baseline, installed: installed, current: installed).sameContents(as: baseline), true)
  var external = installed
  try external.assign(0x200005, to: 33)
  let merged = try CodexMicroProfile.restore(baseline: baseline, installed: installed, current: external)
  expectEqual(merged.assignment(at: 33), 0x200005)
  try external.assign(0x200006, to: 63)
  expectFailure(try CodexMicroProfile.restore(baseline: baseline, installed: installed, current: external))
  expectFailure(try CodexMicroProfile.prepare(baseline, bindings: Array(bindings.prefix(5))))
  expectFailure(try CodexMicroProfile.withStates([.thinking], on: installed))
  let lit = try CodexMicroProfile.withStates([.thinking, .attention, .complete, .idle, .failed, .disconnected], on: installed)
  expectEqual(Array(lit.customColors![63 * 3..<63 * 3 + 3]), MicroState.thinking.rgb)
  expectEqual(lit.keymap, installed.keymap)
  expectEqual(try CodexMicroProfile.restore(baseline: baseline, installed: lit, current: lit).sameContents(as: baseline), true)
}

func checkSingleKeyLightingFromGlobalEffect() throws {
  var baseline = microFixture()
  baseline.configuration[2] = 0
  try baseline.setSolidColor([0, 0, 255])
  baseline.configuration[2] = 0
  var changed = baseline
  try changed.setVisibleKeyColor([0, 255, 0], at: 63)
  expectEqual(changed.configuration[1], 19)
  expectEqual(changed.configuration[2], 4)
  expectEqual(changed.configuration[22], 0)
  expectEqual(changed.keymap, baseline.keymap)
  expectEqual(changed.macroData, baseline.macroData)
  for slot in 0..<128 {
    let rgb = Array(changed.customColors![slot * 3..<slot * 3 + 3])
    let expected: [UInt8] = slot == 63 ? [0, 255, 0]
      : KeyboardLayout.keys.contains(where: { $0.slot == slot }) ? [0, 0, 255] : [20, 20, 20]
    expectEqual(rgb, expected)
  }
  for index in baseline.configuration.indices where ![1, 2, 22].contains(index) {
    expectEqual(changed.configuration[index], baseline.configuration[index])
  }
  try changed.setVisibleKeyColor([255, 0, 0], at: 83)
  expectEqual(Array(changed.customColors![63 * 3..<63 * 3 + 3]), [0, 255, 0])
  expectFailure(try changed.setVisibleKeyColor([1, 2, 3], at: 99))
}

func checkLocalCodexStateReducer() throws {
  var state = CodexRolloutState()
  func consume(_ type: String, _ payload: [String: Any]) throws {
    state.consume(try JSONSerialization.data(withJSONObject: ["type": type, "timestamp": "2026-10-06T12:00:00.000Z", "payload": payload]))
  }
  try consume("session_meta", ["id": "11111111-1111-4111-8111-111111111111"])
  try consume("event_msg", ["type": "task_started", "turn_id": "t1"])
  expectEqual(state.state, .thinking)
  try consume("response_item", ["type": "function_call", "name": "request_user_input_async", "call_id": "call_one"])
  expectEqual(state.state, .attention)
  try consume("response_item", ["type": "function_call_output", "call_id": "call_one", "output": "Question displayed"])
  expectEqual(state.state, .attention)
  try consume("response_item", ["type": "function_call", "name": "request_user_input_async", "call_id": "call_two"])
  let reply = "<send_user_message_question_reply>\n[{\"questionItemId\":\"[\\\"request_user_input_async\\\",\\\"call_one\\\",0]\",\"answer\":\"Sí\"}]\n</send_user_message_question_reply>"
  try consume("response_item", ["type": "message", "role": "user", "content": [["type": "input_text", "text": reply]]])
  expectEqual(state.pendingQuestions, Set(["call_two"]))
  expectEqual(state.state, .attention)
  try consume("response_item", ["type": "function_call_output", "call_id": "call_two", "output": "{\"answers\":{\"q\":\"yes\"}}"])
  expectEqual(state.state, .thinking)
  try consume("event_msg", ["type": "task_complete", "turn_id": "old"])
  expectEqual(state.state, .thinking)
  try consume("event_msg", ["type": "item_completed", "item": ["type": "CommandExecution", "status": "failed"]])
  expectEqual(state.state, .thinking) // A failed command is not a failed agent.
  try consume("event_msg", ["type": "task_complete", "turn_id": "t1"])
  expectEqual(state.state, .complete)
  expectEqual(state.pendingQuestions.isEmpty, true)
  try consume("event_msg", ["type": "task_started", "turn_id": "t2"])
  try consume("response_item", ["type": "function_call", "name": "request_user_input_async", "call_id": "call_one"])
  try consume("event_msg", ["type": "task_complete", "turn_id": "t2"])
  expectEqual(state.state, .attention) // Ending a turn must not hide its pending question.
  try consume("response_item", ["type": "message", "role": "user", "content": [["type": "input_text", "text": reply]]])
  expectEqual(state.state, .complete)
  state.consume(Data("incomplete JSON".utf8))
  expectEqual(state.state, .complete)
  expectEqual(MicroState.runtime(["type": "notLoaded"]), .disconnected)
  expectEqual(MicroState.runtime(["type": "active", "activeFlags": ["waitingOnApproval"]]), .attention)
}

func checkLocalReaderPartialLinesAndTruncation() async throws {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent("micro-check-\(UUID().uuidString).jsonl")
  defer { try? FileManager.default.removeItem(at: file) }
  let header = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"11111111-1111-4111-8111-111111111111\"}}\n"
  try Data((header + "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_sta").utf8).write(to: file)
  let reader = CodexRolloutReader(url: file)
  expectEqual(try await reader.read().state, .disconnected)
  let writer = try FileHandle(forWritingTo: file)
  try writer.seekToEnd()
  try writer.write(contentsOf: Data("rted\",\"turn_id\":\"t1\"}}\n".utf8))
  try writer.close()
  expectEqual(try await reader.read().state, .thinking)
  try Data(header.utf8).write(to: file)
  expectEqual(try await reader.read().state, .disconnected)
}

func checkMicroAttentionTransitions() throws {
  var tracker = MicroAttentionTracker()
  expectEqual(tracker.update([1: .attention, 2: .thinking]), []) // Replayed questions are not new notices.
  expectEqual(tracker.update([1: .attention, 2: .attention]), [2])
  expectEqual(tracker.update([1: .attention, 2: .attention]), [])
  expectEqual(tracker.update([1: .thinking, 2: .complete]), [])
  expectEqual(tracker.update([1: .attention, 2: .complete]), [1])
  expectEqual(tracker.update([1: .disconnected]), [])
  expectEqual(tracker.update([1: .attention]), []) // Reconnection must not replay an old question.
  expectEqual(tracker.update([:]), [])
  expectEqual(tracker.update([1: .attention]), []) // Newly attached route establishes a baseline.
  var requests = MicroAttentionTracker()
  expectEqual(requests.update([1: .attention], questions: [1: ["old"]]), [])
  expectEqual(requests.update([1: .attention], questions: [1: ["old", "new"]]), [1])
  expectEqual(requests.update([1: .attention], questions: [1: ["old", "new"]]), [])
  expectEqual(requests.update([1: .attention], questions: [1: ["old"]]), [])
}

func checkMicroControlBoundary() throws {
  let decoder = JSONDecoder()
  for command in MicroCommand.allCases {
    let decoded = try decoder.decode(MicroControlRequest.self, from: JSONEncoder().encode(MicroControlRequest(command)))
    expectEqual(decoded.command, command)
    try decoded.validate()
  }
  expectFailure(try decoder.decode(MicroControlRequest.self, from: Data("{\"version\":1,\"command\":\"reset\"}".utf8)))
  let future = try decoder.decode(MicroControlRequest.self, from: Data("{\"version\":2,\"command\":\"on\"}".utf8))
  expectFailure(try future.validate())
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("micro-channel-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  try MicroControlSocket.validateDirectory(directory)
  expectFailure(try MicroControlSocket.send(.status, directory: directory)) // No app, never fallback to hardware writes.
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
  expectFailure(try MicroControlSocket.validateDirectory(directory))
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  let link = directory.appendingPathComponent("alias")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
  expectFailure(try MicroControlSocket.validateDirectory(link))
  var pair: [Int32] = [-1, -1]
  expectEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
  defer { pair.forEach { Darwin.close($0) } }
  try MicroControlSocket.validatePeer(pair[0])
  try MicroControlSocket.write(Data(repeating: 65, count: 200), to: pair[1])
  shutdown(pair[1], SHUT_WR)
  expectFailure(try MicroControlSocket.read(pair[0], limit: 64))
}

actor ModeQueueFixture {
  var sequence: [Bool] = []
  var active = 0
  var maxActive = 0
  private var gate: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  private var offQueued: CheckedContinuation<Void, Never>?
  private var didQueueOff = false
  func transition(_ target: Bool) async -> MicroControlResponse {
    active += 1; maxActive = max(active, maxActive)
    sequence.append(target)
    if sequence.count == 1 {
      await withCheckedContinuation { continuation in
        gate = continuation; started?.resume(); started = nil
      }
    }
    active -= 1
    return .init(ok: true, status: .init(hardwareActive: target, recoveryPending: target,
      skinVisible: target, busy: false, message: target ? "on" : "off"))
  }
  func changed(_ target: Bool?, revision: UInt64) {
    if target == false { didQueueOff = true; offQueued?.resume(); offQueued = nil }
  }
  func waitForStart() async {
    if gate != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func waitForOff() async {
    if didQueueOff { return }
    await withCheckedContinuation { offQueued = $0 }
  }
  func release() { gate?.resume(); gate = nil }
}

func checkModeRequestsDuringActivation() async throws {
  let fixture = ModeQueueFixture()
  let queue = MicroModeRequestQueue(transition: { await fixture.transition($0) },
    changed: { await fixture.changed($0, revision: $1) })
  let on = Task { await queue.submit(.toggle, currentActive: false) }
  await fixture.waitForStart()
  // The hardware still reports Normal while the first write is pending.
  // A second toggle must request OFF, not duplicate the activation or reject it.
  let off = Task { await queue.submit(.toggle, currentActive: false) }
  await fixture.waitForOff()
  await fixture.release()
  let activated = await on.value
  let restored = await off.value
  expectEqual(activated.ok, true)
  expectEqual(activated.status.hardwareActive, true)
  expectEqual(restored.ok, true)
  expectEqual(restored.status.hardwareActive, false)
  expectEqual(await fixture.sequence, [true, false])
  expectEqual(await fixture.maxActive, 1)
  expectEqual(await queue.submit(.status, currentActive: false).ok, false)
  expectEqual(await fixture.sequence, [true, false])
}

func checkLiveModeSelectiveRecovery() throws {
  let endpoint = Endpoint(registryID: 1, productID: 0x50b8, target: 1, product: "K628")
  var caps = [UInt8](repeating: 0, count: 34)
  caps[0] = 0xaa; caps[1] = 0x55; caps[4] = 6; caps[5] = 128; caps[6] = 24; caps[8] = 2
  var baseline = Snapshot(endpoint: endpoint, capabilities: caps, configuration: [UInt8](repeating: 0, count: 99), keymap: [UInt8](repeating: 0, count: 384), macroData: [UInt8](repeating: 0, count: 3072), customColors: [UInt8](repeating: 70, count: 384))
  baseline.configuration[1] = 7
  let installed = try LiveLightingProfile.prepare(baseline)
  expectEqual(installed.configuration[1], 0xfe)
  expectEqual(installed.configuration[2], 4)
  expectEqual(installed.keymap, baseline.keymap)
  expectEqual(installed.customColors, baseline.customColors)
  expectEqual(installed.macroData, baseline.macroData)
  var current = installed
  try current.assign(0x200004, to: 1); current.configuration[3] = 3
  let merged = try LiveLightingProfile.restore(baseline: baseline, installed: installed, current: current)
  expectEqual(merged.configuration[1], 7); expectEqual(merged.configuration[2], 0)
  expectEqual(merged.configuration[3], 3); expectEqual(merged.assignment(at: 1), 0x200004)
  current.configuration[1] = 6
  expectFailure(try LiveLightingProfile.restore(baseline: baseline, installed: installed, current: current))
  let micro = try CodexMicroProfile.prepare(baseline, bindings: MicroBinding.defaults, liveLighting: true)
  expectEqual(micro.configuration[1], 0xfe)
  let restored = try CodexMicroProfile.restore(baseline: baseline, installed: micro, current: micro)
  expectEqual(restored.sameContents(as: baseline), true)
}

func checkStaticSkinAndLauncherRecovery() throws {
  let endpoint = Endpoint(registryID: 1, productID: 0x50b8, target: 1, product: "K628")
  var caps = [UInt8](repeating: 0, count: 34)
  caps[0] = 0xaa; caps[1] = 0x55; caps[4] = 6; caps[5] = 128; caps[6] = 24; caps[8] = 2
  var original = Snapshot(endpoint: endpoint, capabilities: caps, configuration: [UInt8](repeating: 0, count: 99), keymap: [UInt8](repeating: 0, count: 384), macroData: [UInt8](repeating: 0, count: 3072), customColors: [UInt8](repeating: 70, count: 384))
  original.configuration[1] = 2; original.configuration[2] = 4
  let flag = try StaticLightingProfile.prepare(original, skin: .boca, launchers: true)
  expectEqual(flag.configuration[1], 19); expectEqual(flag.configuration[22], 0)
  expectEqual(flag.keymap, original.keymap); expectEqual(flag.macroData, original.macroData)
  var current = flag
  try current.assign(0x200004, to: 1); current.configuration[3] = 2; current.customColors![300] = 200
  let restored = try StaticLightingProfile.restore(baseline: original, installed: flag, current: current)
  expectEqual(restored.configuration[1], 2); expectEqual(restored.assignment(at: 1), 0x200004)
  expectEqual(restored.customColors![300], 200)
  current.customColors![99] = 100
  expectFailure(try StaticLightingProfile.restore(baseline: original, installed: flag, current: current))
  let micro = try CodexMicroProfile.prepare(original, bindings: MicroBinding.defaults, launcherColors: true)
  expectEqual(micro.assignment(at: 74), original.assignment(at: 74))
  for slot in 1...4 { expectEqual(micro.assignment(at: slot), original.assignment(at: slot)) }
  let microRestored = try CodexMicroProfile.restore(baseline: original, installed: micro, current: micro, launcherColors: true)
  expectEqual(microRestored.sameContents(as: original), true)
}

func checkSkinPaletteAndAudio() throws {
  let original = (0..<384).map { UInt8($0 % 256) }
  let flag = SkinPalette.colors(for: .boca, baseline: original, launchers: false)
  for key in KeyboardLayout.keys {
    expectEqual(Array(flag[key.slot*3..<key.slot*3+3]), key.row == 2 ? [255,190,0] : [0,45,220])
  }
  let visible = Set(KeyboardLayout.keys.map(\.slot))
  for slot in 0..<128 where !visible.contains(slot) {
    expectEqual(Array(flag[slot*3..<slot*3+3]), Array(original[slot*3..<slot*3+3]))
  }
  let silence = AudioSpectrum.bands([Float](repeating: 0, count: 2048), sampleRate: 48000)
  expectEqual(silence, [Float](repeating: 0, count: 18))
  let quiet = SkinPalette.colors(for: .music, baseline: original, bands: silence, launchers: false)
  for key in KeyboardLayout.keys { expectEqual(Array(quiet[key.slot*3..<key.slot*3+3]), [0,0,0]) }
  for frequency: Double in [1000, 5000] {
    let tone = (0..<2048).map { Float(0.2 * sin(2 * Double.pi * frequency * Double($0)/48000)) }
    let bands = AudioSpectrum.bands(tone, sampleRate: 48000)
    let peak = bands.indices.max { bands[$0] < bands[$1] }!
    let low = 60 * pow(16000.0/60, Double(peak)/18)
    let high = 60 * pow(16000.0/60, Double(peak+1)/18)
    guard frequency >= low - 100, frequency <= high + 100, bands[peak] > 0.5 else { fatalError("Audio spectrum failed tone \(frequency): \(bands)") }
    let wave = SkinPalette.colors(for: .music, baseline: original, bands: bands, launchers: true)
    for i in 0..<4 { expectEqual(Array(wave[(i+1)*3..<(i+1)*3+3]), SkinPalette.launcherColors[i]) }
  }
}
actor SkinQueueFixture {
  var sequence: [KeyboardSkin] = []
  var active = 0
  var maximum = 0
  private var gate: CheckedContinuation<Void, Never>?
  func transition(_ skin: KeyboardSkin) async -> MicroControlResponse {
    active += 1; maximum = max(maximum, active); sequence.append(skin)
    if sequence.count == 1 { await withCheckedContinuation { gate = $0 } }
    active -= 1
    return .init(ok: true, status: .init(hardwareActive: skin != .normal, recoveryPending: skin != .normal, skinVisible: true, busy: false, message: skin.title, skin: skin.rawValue))
  }
  func release() { gate?.resume(); gate = nil }
}
func checkSkinRequestQueue() async {
  let fixture = SkinQueueFixture()
  let queue = SkinRequestQueue { await fixture.transition($0) }
  let first = Task { await queue.submit(nil, current: .normal) }
  while await fixture.sequence.isEmpty { await Task.yield() }
  let second = Task { await queue.submit(nil, current: .normal) }
  while await queue.pendingTargets.last != .codex { await Task.yield() }
  let third = Task { await queue.submit(nil, current: .normal) }
  while await queue.pendingTargets.last != .claude { await Task.yield() }
  let fourth = Task { await queue.submit(nil, current: .normal) }
  while await queue.pendingTargets.last != .boca { await Task.yield() }
  let fifth = Task { await queue.submit(nil, current: .normal) }
  while await queue.pendingTargets.last != .music { await Task.yield() }
  let sixth = Task { await queue.submit(nil, current: .normal) }
  while await queue.pendingTargets.last != .normal { await Task.yield() }
  await fixture.release()
  let results = await [first.value, second.value, third.value, fourth.value, fifth.value, sixth.value]
  expectEqual(results.map { $0.status.skin }, ["apps", "normal", "normal", "normal", "normal", "normal"])
  expectEqual(results.last!.status.busy, false)
  expectEqual(results.last!.status.requestedSkin, nil)
  expectEqual(await fixture.sequence, [.apps, .normal])
  expectEqual(await fixture.maximum, 1)
  let toggles = SkinQueueFixture()
  let toggleQueue = SkinRequestQueue { await toggles.transition($0) }
  let on = Task { await toggleQueue.submit(nil, current: .normal, toggleCodex: true) }
  while await toggles.sequence.isEmpty { await Task.yield() }
  let off = Task { await toggleQueue.submit(nil, current: .normal, toggleCodex: true) }
  while await toggleQueue.pendingTargets.count < 2 { await Task.yield() }
  await toggles.release(); _ = await on.value; _ = await off.value
  expectEqual(await toggles.sequence, [.codex, .normal])
}

func checkDirectSkinTransitions() throws {
  let baseline = microFixture()
  let bindings = MicroBinding.defaults
  let codex = try KeyboardSkinSession.plan(.codex, from: nil, current: baseline,
    bindings: bindings, states: [.thinking, .attention, .complete, .idle, .failed, .disconnected], launchers: true)
  let boca = try KeyboardSkinSession.plan(.boca, from: codex.session, current: codex.snapshot,
    bindings: bindings, states: nil, launchers: true)
  expectEqual(boca.snapshot.keymap, baseline.keymap)
  expectEqual(boca.session!.baseline.sameContents(as: baseline), true)
  let back = try KeyboardSkinSession.plan(.codex, from: boca.session, current: boca.snapshot,
    bindings: bindings, states: nil, launchers: false)
  for slot in 1...4 { expectEqual(Array(back.snapshot.customColors![slot*3..<slot*3+3]), Array(baseline.customColors![slot*3..<slot*3+3])) }
  let normal = try KeyboardSkinSession.plan(.normal, from: back.session, current: back.snapshot,
    bindings: bindings, states: nil, launchers: false)
  expectEqual(normal.snapshot.sameContents(as: baseline), true)
  expectEqual(normal.session == nil, true)
  var outside = boca.snapshot
  outside.configuration[3] = 4; try outside.assign(0x200004, to: 18)
  let merged = try KeyboardSkinSession.plan(.codex, from: boca.session, current: outside,
    bindings: bindings, states: nil, launchers: false)
  expectEqual(merged.snapshot.configuration[3], 4); expectEqual(merged.snapshot.assignment(at: 18), 0x200004)
  var conflict = boca.snapshot; conflict.customColors![18*3] = 77
  expectFailure(try KeyboardSkinSession.plan(.normal, from: boca.session, current: conflict,
    bindings: bindings, states: nil, launchers: false))
}

func checkInterruptedSkinTransition() throws {
  let baseline = microFixture()
  let boca = try KeyboardSkinSession.plan(.boca, from: nil, current: baseline, bindings: MicroBinding.defaults, states: nil, launchers: false)
  let codex = try KeyboardSkinSession.plan(.codex, from: boca.session, current: boca.snapshot, bindings: MicroBinding.defaults, states: nil, launchers: false)
  let journal = SkinTransitionJournal(previous: boca.session, proposed: codex.session, before: boca.snapshot, after: codex.snapshot)
  // Failed write rolled back: Boca survives, with the original baseline retained.
  expectEqual(try journal.resolved(on: boca.snapshot)?.skin, .boca)
  // Crash after device commit and before journal commit: recover Codex, not an invented Normal.
  expectEqual(try journal.resolved(on: codex.snapshot)?.skin, .codex)
  var partial = codex.snapshot; partial.configuration[2] = 0
  expectFailure(try journal.resolved(on: partial))
  let normal = try KeyboardSkinSession.plan(.normal, from: codex.session, current: codex.snapshot, bindings: MicroBinding.defaults, states: nil, launchers: false)
  let exiting = SkinTransitionJournal(previous: codex.session, proposed: nil, before: codex.snapshot, after: normal.snapshot)
  expectEqual(try exiting.resolved(on: baseline) == nil, true)
}

func checkWiredK628Recovery() throws {
  expectEqual(KeyboardLayout.keys.contains { $0.slot == LiveLightingProfile.refreshOffset / 3 }, false)
  let wireless = microFixture()
  var wired = wireless
  wired.endpoint = Endpoint(registryID: 99, productID: 0x509d, target: 0, product: "Gaming KB")
  try wired.validateStructure()
  expectEqual(wired.endpoint.supportsLiveLighting, true)
  let restored = try wireless.preparedForRestore(on: wired)
  expectEqual(restored.endpoint, wired.endpoint)
  expectEqual(restored.sameContents(as: wireless), true)
  var unknown = wired
  unknown.endpoint = Endpoint(registryID: 100, productID: 0x509e, target: 0, product: "Unknown")
  expectFailure(try unknown.validateStructure())
  var otherRevision = wired; otherRevision.capabilities[20] = 1
  expectFailure(try wireless.preparedForRestore(on: otherRevision))
}

func checkApplicationControlsAndRecovery() throws {
  let baseline = microFixture()
  var current = baseline
  var session: KeyboardSkinSession?
  for skin in [KeyboardSkin.apps, .codex, .claude, .boca, .music, .apps, .normal] {
    let plan = try KeyboardSkinSession.plan(skin, from: session, current: current,
      bindings: MicroBinding.defaults, states: nil, launchers: true, controlPad: true, launcherKeys: true)
    if skin != .normal {
      for index in 0..<4 { expectEqual(plan.snapshot.assignment(at: index+1), ApplicationControlProfile.launcherAssignments[index]) }
      if skin.hasActionPad {
        for index in 0..<6 { expectEqual(plan.snapshot.assignment(at: CodexMicroProfile.slots[index]), ApplicationControlProfile.padAssignments[index]) }
      } else {
        for slot in CodexMicroProfile.slots { expectEqual(plan.snapshot.assignment(at: slot), baseline.assignment(at: slot)) }
      }
    }
    expectEqual(plan.snapshot.assignment(at: 74), baseline.assignment(at: 74))
    expectEqual(plan.snapshot.macroData, baseline.macroData)
    current = plan.snapshot; session = plan.session
  }
  expectEqual(current.sameContents(as: baseline), true)
  let apps = try KeyboardSkinSession.plan(.apps, from: nil, current: baseline, bindings: MicroBinding.defaults, states: nil, launchers: true, controlPad: true, launcherKeys: true)
  var conflict = apps.snapshot; try conflict.assign(0x200004, to: 1)
  expectFailure(try apps.session!.restored(on: conflict))
  let disabled = try KeyboardSkinSession.plan(.apps, from: apps.session, current: apps.snapshot, bindings: MicroBinding.defaults, states: nil, launchers: false, controlPad: true, launcherKeys: true)
  expectEqual(disabled.snapshot.keymap, baseline.keymap)
  expectEqual(disabled.session?.launcherKeys, false)
  expectEqual(SkinPalette.launcherColors, [[30,110,255],[255,140,70],[155,90,255],[40,220,80]])
}

func checkLegacyAndChatPadRecovery() throws {
  let baseline = microFixture()
  let legacy = try KeyboardSkinSession.plan(.codex, from: nil, current: baseline,
    bindings: MicroBinding.defaults, states: nil, launchers: true)
  let encoded = try JSONEncoder().encode(legacy.session!)
  let decoded = try JSONDecoder().decode(KeyboardSkinSession.self, from: encoded)
  expectEqual(decoded.launcherKeys, false)
  expectEqual(try decoded.restored(on: legacy.snapshot).sameContents(as: baseline), true)
  let chats = try KeyboardSkinSession.plan(.codex, from: decoded, current: legacy.snapshot,
    bindings: MicroBinding.defaults, states: Array(repeating: .attention, count: 6), launchers: true, controlPad: true, launcherKeys: true, chatPad: true)
  for index in 0..<6 {
    let slot = CodexMicroProfile.slots[index]
    expectEqual(chats.snapshot.assignment(at: slot), ApplicationControlProfile.padAssignments[index])
    expectEqual(Array(chats.snapshot.customColors![slot*3..<slot*3+3]), MicroState.attention.rgb)
  }
  expectEqual(try chats.session!.restored(on: chats.snapshot).sameContents(as: baseline), true)
}

func checkApplicationRouting() {
  expectEqual(ApplicationProfileRouting.chromeIndex(count: 2, remembered: 1, focused: 0, isFrontmost: false), 1)
  expectEqual(ApplicationProfileRouting.chromeIndex(count: 2, remembered: 1, focused: 1, isFrontmost: true), 0)
  expectEqual(ApplicationProfileRouting.chromeIndex(count: 2, remembered: 0, focused: 0, isFrontmost: true), 1)
  expectEqual(ApplicationProfileRouting.chromeIndex(count: 0, remembered: 0, focused: 0, isFrontmost: true), nil)
  expectEqual(ApplicationProfileRouting.chromeIndex(count: 1, remembered: 99, focused: nil, isFrontmost: true), 0)
  expectEqual(ApplicationProfileRouting.skin(for: "com.openai.codex"), .codex)
  expectEqual(ApplicationProfileRouting.skin(for: "com.anthropic.claudefordesktop"), .claude)
  expectEqual(ApplicationProfileRouting.skin(for: "com.google.Chrome"), .apps)
  expectEqual(ApplicationProfileRouting.skin(for: "com.apple.systempreferences"), nil)
  expectEqual(ApplicationPadAction.actions(for: .codex), [.usage,.attention,.dictation,.model,.review,.newChat])
  expectEqual(ApplicationPadAction.actions(for: .claude).last, .settings)
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
try checks.testSolidColorUpdatesEffectRecordAndPreservesOtherSettings()
try checkMicroProfileAndRecovery()
try checkSingleKeyLightingFromGlobalEffect()
try checkLocalCodexStateReducer()
try await checkLocalReaderPartialLinesAndTruncation()
try checkMicroAttentionTransitions()
try checkMicroControlBoundary()
try await checkModeRequestsDuringActivation()
try checkLiveModeSelectiveRecovery()
try checkStaticSkinAndLauncherRecovery()
try checkSkinPaletteAndAudio()
await checkSkinRequestQueue()
try checkDirectSkinTransitions()
try checkInterruptedSkinTransition()
try checkWiredK628Recovery()
try checkApplicationControlsAndRecovery()
try checkLegacyAndChatPadRecovery()
checkApplicationRouting()
print("PASS: 28 protocol, recovery, lighting, routing, command, skin queue and audio checks.")
