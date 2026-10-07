// SPDX-License-Identifier: MIT
import AppKit
import RedragonCore

@MainActor
enum ApplicationFocus {
  /// Launch Services also handles an explicit global action while this app is inactive.
  /// An activate() request alone can be refused under cooperative activation on macOS 14+.
  static func focus(_ bundleID: String, title: String) async throws -> NSRunningApplication {
    let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      .first { $0.activationPolicy == .regular && !$0.isTerminated }
    if let existing, NSWorkspace.shared.frontmostApplication?.processIdentifier == existing.processIdentifier { return existing }
    guard let url = existing?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      throw S136Error.message("Instalá \(title) o asigná otra app al acceso.")
    }
    if let existing, NSApp.isActive { NSApp.yieldActivation(to: existing) }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = false
    let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    for _ in 0..<40 {
      if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return app }
      try await Task.sleep(for: .milliseconds(50))
    }
    throw S136Error.message("No se pudo enfocar \(title); no se envió el atajo.")
  }
}
