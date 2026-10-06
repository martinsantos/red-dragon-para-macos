// SPDX-License-Identifier: MIT
import SwiftUI

struct DeviceStatusBar: View {
  let status: String
  let canDiscard: Bool
  let canApply: Bool
  let discard: () -> Void
  let apply: () -> Void

  var body: some View {
    HStack {
      Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      Spacer()
      Button("Descartar", action: discard).disabled(!canDiscard)
      Button("Aplicar al dispositivo", action: apply)
        .buttonStyle(.borderedProminent).disabled(!canApply)
    }
    .padding(16)
  }
}
