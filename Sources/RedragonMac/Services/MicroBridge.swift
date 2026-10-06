// SPDX-License-Identifier: MIT
import Combine
import Foundation
import RedragonCore

struct MicroThread: Identifiable, Equatable {
  var id: String
  var title: String
  var state: MicroState
}

/// Read-only observer of an explicitly selected local Codex App Server.
/// Does not start/resume chats, send prompts or answer approval requests.
@MainActor
final class MicroBridge: ObservableObject {
  @Published private(set) var connected = false
  @Published private(set) var connecting = false
  @Published private(set) var status = "Sin conexión a estados en vivo"
  @Published private(set) var threads: [MicroThread] = []
  private var socket: URLSessionWebSocketTask?
  private var session: URLSession?
  private var receiver: Task<Void, Never>?
  private var poller: Task<Void, Never>?
  private var deadline: Task<Void, Never>?
  private var nextID = 1
  private var listID: Int?
  private var listDeadline: Task<Void, Never>?
  private var generation = UUID()

  func connect(_ address: String) {
    disconnect()
    guard let url = URL(string: address), url.scheme == "ws",
      ["127.0.0.1", "localhost", "[::1]", "::1"].contains(url.host ?? ""),
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
      status = "Usá un App Server local: ws://127.0.0.1:puerto"
      return
    }
    let token = generation
    connecting = true
    status = "Conectando al servidor local…"
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 8
    let session = URLSession(configuration: config)
    self.session = session
    let socket = session.webSocketTask(with: url)
    socket.maximumMessageSize = 1_048_576
    self.socket = socket
    socket.resume()
    receiver = Task { [weak self] in
      do {
        try await self?.send(["id": 0, "method": "initialize", "params": [
          "clientInfo": ["name": "red_dragon_micro", "title": "Red Dragon Micro Skin",
                         "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"]]])
        while !Task.isCancelled {
          let message = try await socket.receive()
          guard let self, self.generation == token else { return }
          let data: Data
          switch message {
          case .string(let value): data = Data(value.utf8)
          case .data(let value): data = value
          @unknown default: continue
          }
          guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
          try await self.receive(object)
        }
      } catch {
        guard let self, self.generation == token else { return }
        self.disconnect()
        self.status = "Sin conexión: \(error.localizedDescription)"
      }
    }
    deadline = Task { [weak self] in
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled, let self, self.generation == token, !self.connected else { return }
      self.disconnect()
      self.status = "El servidor no confirmó la conexión."
    }
  }

  func disconnect() {
    generation = UUID()
    receiver?.cancel()
    poller?.cancel()
    deadline?.cancel()
    listDeadline?.cancel()
    socket?.cancel(with: .normalClosure, reason: nil)
    session?.invalidateAndCancel()
    socket = nil
    session = nil
    connected = false
    connecting = false
    threads = []
    listID = nil
    status = "Sin conexión a estados en vivo"
  }

  private func send(_ object: [String: Any]) async throws {
    guard let socket else { throw URLError(.notConnectedToInternet) }
    let data = try JSONSerialization.data(withJSONObject: object)
    try await socket.send(.data(data))
  }

  private func requestThreads() async throws {
    guard listID == nil else { return }
    let id = nextID
    nextID += 1
    listID = id
    try await send(["id": id, "method": "thread/list", "params": ["limit": 50, "sortKey": "updated_at", "archived": false]])
    listDeadline?.cancel()
    let token = generation
    listDeadline = Task { [weak self] in
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled, let self, self.generation == token, self.listID == id else { return }
      self.disconnect()
      self.status = "El servidor dejó de actualizar sus estados."
    }
  }

  private func receive(_ message: [String: Any]) async throws {
    if let method = message["method"] as? String {
      if let id = message["id"] {
        try await send(["id": id, "error": ["code": -32601, "message": "This observer does not perform actions or approvals."]])
        return
      }
      let params = message["params"] as? [String: Any] ?? [:]
      if method == "thread/status/changed", let id = params["threadId"] as? String,
         let value = params["status"] as? [String: Any] {
        update(id, state: MicroState.runtime(value))
      } else if method == "turn/completed", let id = params["threadId"] as? String,
                let turn = params["turn"] as? [String: Any] {
        let state: MicroState = turn["status"] as? String == "completed" ? .complete
          : turn["status"] as? String == "failed" ? .failed : .idle
        update(id, state: state)
      } else if method == "turn/started", let id = params["threadId"] as? String {
        update(id, state: .thinking)
      } else if method == "thread/closed", let id = params["threadId"] as? String {
        update(id, state: .disconnected)
      }
      return
    }
    guard let id = message["id"] as? Int else { return }
    if let error = message["error"] as? [String: Any] {
      throw NSError(domain: "MicroBridge", code: error["code"] as? Int ?? -1,
                    userInfo: [NSLocalizedDescriptionKey: error["message"] as? String ?? "Respuesta rechazada."])
    }
    guard let result = message["result"] as? [String: Any] else { return }
    if id == 0 {
      try await send(["method": "initialized", "params": [:]])
      connected = true
      connecting = false
      deadline?.cancel()
      status = "Conectado al App Server local"
      try await requestThreads()
      poller = Task { [weak self] in
        while !Task.isCancelled {
          do {
            try await Task.sleep(for: .seconds(3))
            try Task.checkCancellation()
            try await self?.requestThreads()
          } catch {
            guard !Task.isCancelled else { return }
            self?.disconnect()
            self?.status = "Se perdió la conexión al servidor local."
            return
          }
        }
      }
    } else if id == listID {
      listDeadline?.cancel()
      listID = nil
      let values = result["data"] as? [[String: Any]] ?? []
      threads = values.compactMap { value in
        guard let id = value["id"] as? String else { return nil }
        var state = MicroState.runtime(value["status"] as? [String: Any] ?? [:])
        if state == .idle, let previous = threads.first(where: { $0.id == id }),
           previous.state == .complete { state = .complete }
        return MicroThread(id: id, title: value["name"] as? String ?? "Chat \(id.prefix(8))", state: state)
      }
    }
  }

  private func update(_ id: String, state: MicroState) {
    guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
    // The idle notification after completion must not erase the completion indicator.
    if state == .idle && threads[index].state == .complete { return }
    threads[index].state = state
  }
}
