// SPDX-License-Identifier: MIT
import AppKit
import Darwin
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var instanceLock: Int32 = -1

  func applicationWillFinishLaunching(_ notification: Notification) {
    let identifier = Bundle.main.bundleIdentifier ?? "local.redragonmac.S136"
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("RedragonMac", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("\(identifier).instance.lock")
      instanceLock = Darwin.open(url.path, O_CREAT | O_RDWR, 0o600)
      guard instanceLock >= 0 else { return }
      guard flock(instanceLock, LOCK_EX | LOCK_NB) == 0 else {
        Darwin.close(instanceLock); instanceLock = -1
        NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
          .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
          .activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return
      }
    } catch {
      // Launch Services also prevents duplicate instances; a filesystem failure
      // must not prevent the user from opening their configuration app.
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard let window = sender.windows.first(where: { $0.title == "RED DRAGON PARA MACOS" }) else { return true }
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
    sender.activate(ignoringOtherApps: true)
    return false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  func applicationWillTerminate(_ notification: Notification) {
    if instanceLock >= 0 { flock(instanceLock, LOCK_UN); Darwin.close(instanceLock) }
  }
}
@main
struct RedragonMacApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var mode = MicroModeController()
  var body: some Scene {
    Window("RED DRAGON PARA MACOS", id: "main") {
      ContentView(mode: mode).frame(minWidth: 940, minHeight: 640)
    }.defaultSize(width: 1120, height: 740)
      .commands {
        CommandGroup(replacing: .newItem) {}
        AppCommands(store: mode.store, mode: mode)
      }
  }
}
