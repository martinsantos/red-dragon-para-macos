// SPDX-License-Identifier: MIT
import RedragonCore
import SwiftUI

struct DeviceSidebar: View {
  let endpoints: [Endpoint]
  let selectedID: String?
  let canSelect: Bool
  let select: (String) -> Void
  @Binding var section: AppSection

  init(
    endpoints: [Endpoint], selectedID: String?, section: Binding<AppSection>, canSelect: Bool,
    select: @escaping (String) -> Void
  ) {
    self.endpoints = endpoints
    self.selectedID = selectedID
    self._section = section
    self.canSelect = canSelect
    self.select = select
  }

  var body: some View {
    List {
      Section("RED DRAGON · macOS") {
        ForEach(endpoints) { endpoint in
          Button {
            select(endpoint.id)
          } label: {
            Label(endpoint.title, systemImage: endpoint.target == 1 ? "keyboard" : "computermouse")
              .foregroundStyle(selectedID == endpoint.id ? Color.accentColor : .primary)
          }
          .buttonStyle(.plain)
          .disabled(!canSelect)
        }
      }
      Section("CONFIGURACIÓN") {
        ForEach(AppSection.allCases) { item in
          Button {
            section = item
          } label: {
            Label(item.rawValue, systemImage: item.symbol)
              .foregroundStyle(section == item ? Color.accentColor : .primary)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .listStyle(.sidebar)
    .navigationSplitViewColumnWidth(min: 210, ideal: 230)
  }
}
