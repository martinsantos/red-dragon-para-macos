// SPDX-License-Identifier: MIT
import RedragonCore
import SwiftUI

struct KeyboardDiagram: View {
  enum Mode { case mapping, colors, lighting }
  let snapshot: Snapshot
  var mode = Mode.mapping
  @Binding var selectedSlot: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("K628 · vista superior", systemImage: "keyboard").font(.headline)
      GeometryReader { geometry in
        let unit = (geometry.size.width - 20) / KeyboardLayout.columns
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.045))
          ForEach(KeyboardLayout.keys.filter { $0.slot < snapshot.keyCount }) { key in
            keyButton(key, unit: unit)
              .frame(width: unit * key.width - 4, height: 42)
              .offset(x: 10 + unit * key.column + 2, y: 10 + CGFloat(key.row) * 47)
          }
        }
      }.frame(height: CGFloat(KeyboardLayout.rowCount) * 47 + 15)
      Text(mode == .lighting ? "Tocá una tecla y elegí un color abajo. El dibujo muestra los ajustes de color; los efectos animados se representan con su color configurado." : "Tocá una tecla en el dibujo. Abajo podés revisar su función y cambiarla.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Dibujo interactivo del teclado K628")
  }

  private func keyButton(_ key: PhysicalKey, unit: Double) -> some View {
    let selected = key.slot == selectedSlot
    let rgb = keyRGB(key.slot)
    let foreground: Color =
      mode != .mapping
      ? (rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722 > 0.5 ? .black : .white) : .primary
    return Button {
      selectedSlot = key.slot
    } label: {
      Text(key.label).font(
        .system(size: max(10, min(13, unit * 0.36)), weight: selected ? .bold : .medium)
      )
      .lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity, maxHeight: .infinity)
      .foregroundStyle(foreground)
      .background(
        RoundedRectangle(cornerRadius: 6).fill(
          mode != .mapping
            ? Color(red: rgb[0], green: rgb[1], blue: rgb[2])
            : selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6).stroke(
          selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 3 : 1))
    }
    .buttonStyle(.plain)
    .help(
      "\(KeyCatalog.physicalName(slot:key.slot,keyboard:true)) · \(KeyCatalog.name(snapshot.assignment(at:key.slot)))"
    )
    .accessibilityLabel(KeyCatalog.physicalName(slot: key.slot, keyboard: true))
    .accessibilityValue(
      mode == .mapping ? KeyCatalog.name(snapshot.assignment(at: key.slot)) : "Color personalizado"
    )
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func keyRGB(_ slot: Int) -> [Double] {
    if mode == .lighting && snapshot.configuration[1] != 19 {
      return snapshot.lightingRGB.map { Double($0) / 255 }
    }
    guard let colors = snapshot.customColors, slot * 3 + 2 < colors.count else { return [0, 0, 0] }
    return colors[slot * 3..<slot * 3 + 3].map { Double($0) / 255 }
  }
}
