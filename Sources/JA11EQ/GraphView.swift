import AppKit
import JA11EQCore
import JA11Kit
import SwiftUI

/// The response graph: gridlines, the combined curve, the pre-gain curve with a clipping marker
/// and one numbered, draggable handle per band. All coordinates come from `GraphGeometry`.
struct GraphView: View {
    let model: AppModel

    private let leftInset = 36.0
    private let bottomInset = 22.0
    private let topInset = 8.0
    private let rightInset = 12.0
    private let hitRadius = 12.0

    @State private var dragBand: Int?
    @State private var dragAdjustsQ = false
    @State private var lastY = 0.0

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let geometry = GraphGeometry(
                    width: proxy.size.width - leftInset - rightInset,
                    height: proxy.size.height - topInset - bottomInset
                )
                Canvas { context, _ in
                    draw(&context, geometry)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(geometry))
            }
            Text("Drag a handle to change frequency and gain. Option-drag to change Q.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dragGesture(_ geometry: GraphGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard model.editorEnabled else { return }
                let point = GraphPoint(x: value.location.x - leftInset, y: value.location.y - topInset)
                if dragBand == nil {
                    guard let hit = geometry.hitTest(point, in: model.editor.curve, radius: hitRadius) else { return }
                    dragBand = hit
                    dragAdjustsQ = NSEvent.modifierFlags.contains(.option)
                    lastY = point.y
                }
                guard let band = dragBand else { return }
                if dragAdjustsQ {
                    let dy = point.y - lastY
                    lastY = point.y
                    model.editor.scaleQ(band: band, by: exp(-dy * 0.01))
                } else {
                    let target = geometry.dragged(to: point)
                    model.editor.moveBand(band, frequency: target.frequency, gain: target.gain)
                }
            }
            .onEnded { _ in dragBand = nil }
    }

    private func draw(_ context: inout GraphicsContext, _ geometry: GraphGeometry) {
        guard geometry.width > 0, geometry.height > 0 else { return }
        let origin = CGPoint(x: leftInset, y: topInset)
        func pt(_ p: GraphPoint) -> CGPoint { CGPoint(x: origin.x + p.x, y: origin.y + p.y) }

        let gridColor = Color.secondary.opacity(0.25)
        for hertz in GraphGeometry.frequencyGridlines {
            let x = origin.x + geometry.x(forFrequency: hertz)
            var line = Path()
            line.move(to: CGPoint(x: x, y: origin.y))
            line.addLine(to: CGPoint(x: x, y: origin.y + geometry.height))
            context.stroke(line, with: .color(gridColor), lineWidth: 0.5)
            let label = Text(GraphGeometry.frequencyLabel(hertz)).font(.caption2).foregroundStyle(.secondary)
            context.draw(label, at: CGPoint(x: x, y: origin.y + geometry.height + 11))
        }
        for dB in GraphGeometry.gainGridlines {
            let y = origin.y + geometry.y(forGain: dB)
            var line = Path()
            line.move(to: CGPoint(x: origin.x, y: y))
            line.addLine(to: CGPoint(x: origin.x + geometry.width, y: y))
            let zero = dB == 0
            context.stroke(line, with: .color(zero ? Color.secondary.opacity(0.8) : gridColor), lineWidth: zero ? 1.5 : 0.5)
            let label = Text(String(format: "%+.0f", dB)).font(.caption2).foregroundStyle(.secondary)
            context.draw(label, at: CGPoint(x: origin.x - 16, y: y))
        }

        let curve = model.editor.curve
        let count = max(Int(geometry.width / 2), 2)
        func path(_ points: [GraphPoint]) -> Path {
            var path = Path()
            for (i, p) in points.enumerated() {
                i == 0 ? path.move(to: pt(p)) : path.addLine(to: pt(p))
            }
            return path
        }

        let withPreGain = geometry.responsePoints(for: curve, includePreGain: true, points: count)
        context.stroke(path(withPreGain), with: .color(Color.accentColor.opacity(0.35)), lineWidth: 1.5)
        let clipping = geometry.clippingRanges(for: curve, points: count)
        for range in clipping {
            let part = withPreGain.filter { range.contains($0.x) }
            context.stroke(path(part), with: .color(.red), lineWidth: 2)
        }
        if !clipping.isEmpty {
            context.draw(Text("Clipping risk").font(.caption).foregroundStyle(.red),
                         at: CGPoint(x: origin.x + geometry.width - 50, y: origin.y + 10))
        }
        let main = geometry.responsePoints(for: curve, includePreGain: false, points: count)
        context.stroke(path(main), with: .color(.accentColor), lineWidth: 2.5)

        for (index, band) in curve.bands.enumerated() {
            let center = pt(geometry.handlePosition(for: band))
            let circle = Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))
            if band.enabled {
                context.fill(circle, with: .color(.accentColor))
                context.stroke(circle, with: .color(.white), lineWidth: 1)
                context.draw(Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.white), at: center)
            } else {
                context.stroke(circle, with: .color(Color.secondary.opacity(0.6)), lineWidth: 1)
                context.draw(Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary.opacity(0.6)), at: center)
            }
        }
    }
}
