import AppKit

@MainActor
final class SnowMarker: NSView {
    private var pointerOffset: NSPoint?

    var isDragging: Bool { pointerOffset != nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func cancelDrag() {
        pointerOffset = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        NSColor(calibratedRed: 0.90, green: 0.95, blue: 1, alpha: 0.96).setFill()
        circle.fill()
        NSColor(calibratedRed: 0.44, green: 0.62, blue: 0.82, alpha: 0.9).setStroke()
        circle.lineWidth = 1
        circle.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let cursor = NSEvent.mouseLocation
        pointerOffset = NSPoint(x: cursor.x - window.frame.minX, y: cursor.y - window.frame.minY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let pointerOffset else { return }
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) else { return }
        let area = screen.visibleFrame
        let x = max(area.minX, min(cursor.x - pointerOffset.x, area.maxX - window.frame.width))
        let y = max(area.minY, min(cursor.y - pointerOffset.y, area.maxY - window.frame.height))
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    override func mouseUp(with event: NSEvent) {
        cancelDrag()
    }
}
