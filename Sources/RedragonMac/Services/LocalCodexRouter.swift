// SPDX-License-Identifier: MIT
import AppKit
import Combine
import Foundation
import RedragonCore
import UniformTypeIdentifiers

struct LocalMicroRoute: Codable, Equatable, Identifiable {
  var number: Int
  var file: URL
  var id: Int { number }
}

/// Follows only the JSONL files explicitly selected by the user (or launch argument).
@MainActor
final class LocalCodexRouter: ObservableObject {
  @Published private(set) var routes: [LocalMicroRoute] = []
  @Published private(set) var states: [Int: MicroState] = [:]
  @Published private(set) var threadIDs: [Int: String] = [:]
  @Published private(set) var eventDates: [Int: Date] = [:]
  @Published private(set) var issues: [Int: String] = [:]
  private var readers: [Int: CodexRolloutReader] = [:]
  private var watcher: Task<Void, Never>?
  private let defaults: UserDefaults
  private let preview: Bool

  init(defaults: UserDefaults = .standard, preview: Bool = false) {
    self.defaults = defaults
    self.preview = preview
    guard !preview else { return }
    if let data = defaults.data(forKey: "micro.localRoutes"),
       let saved = try? JSONDecoder().decode([LocalMicroRoute].self, from: data) {
      routes = saved.filter { (1...6).contains($0.number) && $0.file.isFileURL && $0.file.pathExtension == "jsonl" }
      for route in routes { readers[route.number] = CodexRolloutReader(url: route.file) }
    }
    start()
  }
  func chooseFile(for number: Int) {
    let panel = NSOpenPanel()
    panel.title = "Conectar un chat local de Codex a Num \(number)"
    panel.message = "Elegí el archivo rollout .jsonl del chat. Se leerán sus eventos de estado en esta Mac."
    panel.allowedContentTypes = [.init(filenameExtension: "jsonl") ?? .plainText]
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url { attach(url, to: number) }
  }
  func attach(_ url: URL, to number: Int) {
    guard (1...6).contains(number), url.isFileURL, url.pathExtension == "jsonl" else { return }
    detach(number)
    routes.append(LocalMicroRoute(number: number, file: url))
    readers[number] = CodexRolloutReader(url: url)
    persist()
    start()
  }
  func detach(_ number: Int) {
    routes.removeAll { $0.number == number }
    readers[number] = nil
    states[number] = nil
    threadIDs[number] = nil
    eventDates[number] = nil
    issues[number] = nil
    persist()
  }
  private func persist() {
    guard !preview else { return }
    if let data = try? JSONEncoder().encode(routes) { defaults.set(data, forKey: "micro.localRoutes") }
  }
  private func start() {
    guard watcher == nil else { return }
    watcher = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        for route in self.routes {
          guard let reader = self.readers[route.number] else { continue }
          do {
            let result = try await reader.read()
            guard self.readers[route.number] === reader else { continue }
            self.states[route.number] = result.threadID == nil ? .disconnected : result.state
            self.threadIDs[route.number] = result.threadID
            self.eventDates[route.number] = result.lastEventAt
            self.issues[route.number] = result.threadID == nil ? "No se reconoce como registro de Codex." : nil
          } catch {
            self.states[route.number] = .disconnected
            self.issues[route.number] = "No se puede leer este chat. Volvé a conectar su archivo."
          }
        }
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }
}
