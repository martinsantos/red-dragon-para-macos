// SPDX-License-Identifier: MIT
import AppKit

/// AppKit is confined to native file panels and system navigation.
@MainActor
struct MacSystemIntegration {
  func openInputSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    else { return }
    NSWorkspace.shared.open(url)
  }

  func showApplication() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }

  func openDirectory(_ url: URL) {
    NSWorkspace.shared.open(url)
  }

  func chooseBackup(in directory: URL) -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.directoryURL = directory
    return panel.runModal() == .OK ? panel.url : nil
  }
}
