// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}
@main
struct RedragonMacApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var store = DeviceStore()
  var body: some Scene {
    WindowGroup("RED DRAGON PARA MACOS", id: "main") {
      ContentView(store: store).frame(minWidth: 940, minHeight: 640)
    }.defaultSize(width: 1120, height: 740)
      .commands { AppCommands(store: store) }
  }
}
