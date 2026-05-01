import AppKit
import SwiftUI

/// A native, keyboard-accessible NSSlider with the compact track in the reference.
struct CompactSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var accessibilityName: String
    var onCommit: (() -> Void)? = nil
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> TrackingSlider {
        let slider = TrackingSlider()
        slider.cell = CompactSliderCell()
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.controlSize = .small
        return slider
    }
    func updateNSView(_ slider: TrackingSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = range.lowerBound; slider.maxValue = range.upperBound
        slider.doubleValue = value; slider.isEnabled = enabled
        slider.setAccessibilityLabel(accessibilityName)
        slider.finishedTracking = onCommit
        slider.needsDisplay = true
    }
    final class Coordinator: NSObject {
        var parent: CompactSlider
        init(_ parent: CompactSlider) { self.parent = parent }
        @objc func changed(_ slider: TrackingSlider) {
            parent.value = slider.doubleValue
            if !slider.tracking { parent.onCommit?() }
        }
    }
}

final class TrackingSlider: NSSlider {
    var tracking = false
    var finishedTracking: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        tracking = true
        super.mouseDown(with: event)
        tracking = false
        finishedTracking?()
    }
}

final class CompactSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 2.5, width: rect.width, height: 5)
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.22 : 0.1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
        let fraction = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * min(1, max(0, fraction)), height: track.height)
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.95 : 0.3).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        let circle = NSRect(x: knobRect.midX - 9, y: knobRect.midY - 9, width: 18, height: 18)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 2; shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.set()
        NSColor.white.withAlphaComponent(isEnabled ? 0.95 : 0.4).setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
