// SPDX-License-Identifier: MIT
import RedragonCore
import SwiftUI

struct MouseDiagram: View {
  let snapshot: Snapshot
  var lighting = false
  @Binding var selectedSlot: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("M693 · vista superior", systemImage: "computermouse").font(.headline)
      HStack(spacing: 28) {
        ZStack {
          MouseBody().fill(Color.primary.opacity(0.06))
          MouseBody().stroke(
            lighting ? lightColor : Color.primary.opacity(0.18), lineWidth: lighting ? 4 : 1)
          VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
              hitArea(0, label: "Izquierdo").frame(width: 78, height: 90)
              hitArea(1, label: "Rueda").frame(width: 34, height: 70)
              hitArea(2, label: "Derecho").frame(width: 78, height: 90)
            }
            hitArea(6, label: "DPI +").frame(width: 62, height: 32)
            hitArea(7, label: "DPI −").frame(width: 62, height: 32)
            Spacer(minLength: 4)
            Text("M693").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
          }.padding(.top, 28).padding(.bottom, 16)
          VStack(spacing: 10) {
            hitArea(4, label: "↑").frame(width: 28, height: 46)
            hitArea(5, label: "↓").frame(width: 28, height: 46)
          }.offset(x: -121, y: 5)
        }.frame(width: 260, height: 300).padding(.leading, 18)
        VStack(alignment: .leading, spacing: 12) {
          Text(lighting ? "Color elegido" : "Elegí un botón").font(.title3.weight(.semibold))
          if lighting {
            RoundedRectangle(cornerRadius: 8).fill(lightColor).frame(width: 100, height: 28)
            Text("Vista previa del color. El efecto de iluminación se ejecuta en el mouse.")
              .foregroundStyle(.secondary)
          } else {
            ForEach([0, 2, 1, 4, 5, 6, 7], id: \.self) { slot in
              Button {
                selectedSlot = slot
              } label: {
                HStack {
                  Text(KeyCatalog.physicalName(slot: slot, keyboard: false)).fontWeight(
                    selectedSlot == slot ? .semibold : .regular)
                  Spacer(minLength: 8)
                  if selectedSlot == slot {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                  }
                }.padding(8)
              }.buttonStyle(.plain)
                .background(
                  RoundedRectangle(cornerRadius: 6).fill(
                    selectedSlot == slot ? Color.accentColor.opacity(0.1) : .clear))
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      if !lighting {
        Text(
          "Los botones laterales están a la izquierda. Tocá el dibujo o elegí su nombre para ver qué hace cada uno."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Dibujo interactivo del mouse M693")
  }

  private var lightColor: Color {
    Color(
      red: Double(snapshot.configuration[6]) / 255, green: Double(snapshot.configuration[7]) / 255,
      blue: Double(snapshot.configuration[8]) / 255)
  }
  private func hitArea(_ slot: Int, label: String) -> some View {
    Button {
      selectedSlot = slot
    } label: {
      Text(label).font(.system(size: label == "Rueda" ? 9 : 11, weight: .medium))
        .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: slot == 1 ? 10 : 7).fill(
            !lighting && selectedSlot == slot
              ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
        )
        .overlay(
          RoundedRectangle(cornerRadius: slot == 1 ? 10 : 7).stroke(
            !lighting && selectedSlot == slot ? Color.accentColor : Color.primary.opacity(0.16),
            lineWidth: !lighting && selectedSlot == slot ? 2 : 1))
    }.buttonStyle(.plain).disabled(lighting)
      .help(KeyCatalog.name(snapshot.assignment(at: slot)))
      .accessibilityLabel(KeyCatalog.physicalName(slot: slot, keyboard: false))
      .accessibilityValue(KeyCatalog.name(snapshot.assignment(at: slot)))
  }
}

private struct MouseBody: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let w = rect.width
    let h = rect.height
    p.move(to: CGPoint(x: w * 0.5, y: 0))
    p.addCurve(
      to: CGPoint(x: w * 0.96, y: h * 0.3), control1: CGPoint(x: w * 0.86, y: 0),
      control2: CGPoint(x: w * 0.95, y: h * 0.06))
    p.addCurve(
      to: CGPoint(x: w * 0.9, y: h * 0.84), control1: CGPoint(x: w, y: h * 0.52),
      control2: CGPoint(x: w * 0.99, y: h * 0.68))
    p.addCurve(
      to: CGPoint(x: w * 0.5, y: h), control1: CGPoint(x: w * 0.84, y: h * 0.97),
      control2: CGPoint(x: w * 0.66, y: h))
    p.addCurve(
      to: CGPoint(x: w * 0.1, y: h * 0.84), control1: CGPoint(x: w * 0.34, y: h),
      control2: CGPoint(x: w * 0.16, y: h * 0.97))
    p.addCurve(
      to: CGPoint(x: w * 0.04, y: h * 0.3), control1: CGPoint(x: w * 0.01, y: h * 0.68),
      control2: CGPoint(x: 0, y: h * 0.52))
    p.addCurve(
      to: CGPoint(x: w * 0.5, y: 0), control1: CGPoint(x: w * 0.05, y: h * 0.06),
      control2: CGPoint(x: w * 0.14, y: 0))
    p.closeSubpath()
    return p
  }
}
