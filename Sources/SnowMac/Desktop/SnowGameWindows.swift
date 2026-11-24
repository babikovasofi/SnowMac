import AppKit
import SwiftUI

@MainActor
final class SnowGameWindows {
    private var bodies: [Int: PassiveSnowPanel] = [:]
    private var snowPanels: [PassiveSnowPanel] = []
    private weak var display: DisplaySnow?

    init(display: DisplaySnow) {
        self.display = display
    }

    func synchronize(bodies snapshots: [SnowBody], locked: Bool, tool: DesktopSnowTool, snowFrame: SnowFrame? = nil) {
        let frame = snowFrame ?? display?.world.frame
        let drifts = frame?.drifts ?? []
        let dockBounds = display?.dockBounds
        let identities = Set(snapshots.map(\.id))
        for id in Array(bodies.keys) where !identities.contains(id) {
            bodies.removeValue(forKey: id)?.orderOut(nil)
        }
        for body in snapshots {
            let level = bodyLevel(for: body, drifts: drifts, dockBounds: dockBounds)
            let panel = bodies[body.id] ?? makeBody(body, level: level)
            guard let view = panel.contentView as? SnowBodyInteraction else { continue }
            view.kind = body.kind
            if locked { view.cancel() }
            panel.ignoresMouseEvents = locked
            let frame = screenFrame(for: body)
            if panel.level != level { panel.level = level }
            if panel.frame != frame { panel.setFrame(frame, display: false) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }

        if locked {
            hideSnowInput()
        } else if let frame {
            synchronizeSnowInput(frame: frame, dockBounds: dockBounds, tool: tool)
        }
    }

    func cancel() {
        for panel in bodies.values {
            (panel.contentView as? SnowBodyInteraction)?.cancel()
            panel.ignoresMouseEvents = true
        }
        hideSnowInput()
    }

    func hide() {
        cancel()
        for panel in bodies.values { panel.orderOut(nil) }
    }

    private func hideSnowInput() {
        for panel in snowPanels {
            (panel.contentView as? SnowSurfaceInteraction)?.cancel()
            panel.orderOut(nil)
        }
    }

    private func synchronizeSnowInput(frame: SnowFrame, dockBounds: CGRect?, tool: DesktopSnowTool) {
        // AppKit keeps sending drag events to the panel that received mouse-down.
        // Leave that panel alone until mouse-up even if its snow has been scooped away.
        guard !snowPanels.contains(where: { ($0.contentView as? SnowSurfaceInteraction)?.isTracking == true }) else {
            return
        }
        let regions = SnowInputRegions.make(from: frame, dockBounds: dockBounds)
        let origin = display?.geometry.frame.origin ?? .zero
        for (index, region) in regions.enumerated() {
            let panel = index < snowPanels.count ? snowPanels[index] : makeSnowPanel()
            let windowFrame = region.rect.offsetBy(dx: origin.x, dy: origin.y)
            let level = level(for: region.kind)
            if panel.level != level { panel.level = level }
            if panel.frame != windowFrame { panel.setFrame(windowFrame, display: false) }
            (panel.contentView as? SnowSurfaceInteraction)?.usesShovel = tool == .shovel
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        for panel in snowPanels.dropFirst(regions.count) where panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func makeSnowPanel() -> PassiveSnowPanel {
        let panel = PassiveSnowPanel(frame: .zero, level: .normal)
        let view = SnowSurfaceInteraction()
        view.begin = { [weak self] point in
            guard let self, let display else { return false }
            return display.world.beginRoll(at: local(point))
        }
        view.move = { [weak self] point, elapsed in
            guard let self, let display else { return }
            display.world.roll(to: local(point), elapsed: elapsed)
        }
        view.release = { [weak display] in display?.world.endDrag() }
        view.shovel = { [weak self] point, direction in
            guard let self, let display else { return }
            display.world.shovel(at: local(point), direction: direction)
        }
        panel.contentView = view
        panel.ignoresMouseEvents = false
        snowPanels.append(panel)
        return panel
    }

    private func level(for kind: SnowInputRegions.Kind) -> NSWindow.Level {
        switch kind {
        case .ground: Self.groundInputLevel
        case .dock: Self.dockInputLevel
        case .window: Self.windowInputLevel
        }
    }

    private func bodyLevel(for body: SnowBody, drifts: [SnowDrift], dockBounds: CGRect?) -> NSWindow.Level {
        if let dock = dockBounds,
           body.center.x >= dock.minX, body.center.x <= dock.maxX,
           body.center.y >= dock.maxY - 16 {
            return NSWindow.Level(rawValue: Self.dockInputLevel.rawValue + 1)
        }
        let bottom = body.center.y - body.size.height / 2
        let restingAboveWindow = drifts.contains { drift in
            drift.id != nil && drift.id != "dock" &&
                body.center.x >= drift.left && body.center.x <= drift.right &&
                bottom >= drift.baseY - 4 && bottom <= drift.baseY + 40
        }
        if restingAboveWindow {
            return NSWindow.Level(rawValue: Self.windowInputLevel.rawValue + 1)
        }
        return NSWindow.Level(rawValue: Self.groundInputLevel.rawValue + 1)
    }

    private func makeBody(_ body: SnowBody, level: NSWindow.Level) -> PassiveSnowPanel {
        let panel = PassiveSnowPanel(frame: screenFrame(for: body), level: level)
        let view = SnowBodyInteraction(rootView: SnowBodyArt(kind: body.kind))
        view.begin = { [weak display] in display?.world.beginDrag(id: body.id) }
        view.move = { [weak self] point, elapsed in
            guard let self, let display else { return }
            display.world.drag(to: local(point), elapsed: elapsed)
        }
        view.release = { [weak display] in display?.world.endDrag() }
        panel.contentView = view
        bodies[body.id] = panel
        return panel
    }

    private func screenFrame(for body: SnowBody) -> CGRect {
        let origin = display?.geometry.frame.origin ?? .zero
        return CGRect(x: origin.x + body.center.x - body.size.width / 2,
                      y: origin.y + body.center.y - body.size.height / 2,
                      width: body.size.width, height: body.size.height)
    }

    private func local(_ point: NSPoint) -> CGPoint {
        let origin = display?.geometry.frame.origin ?? .zero
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private static let groundInputLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 2)
    private static let dockInputLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 5)
    private static let windowInputLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
}

@MainActor
private final class SnowBodyInteraction: NSHostingView<SnowBodyArt> {
    var begin: (() -> Void)?
    var move: ((CGPoint, TimeInterval) -> Void)?
    var release: (() -> Void)?
    private var offset: CGPoint?
    private var lastDragTime: TimeInterval = 0
    var kind: SnowBodyKind {
        didSet {
            if oldValue != kind { rootView = SnowBodyArt(kind: kind) }
        }
    }

    required init(rootView: SnowBodyArt) {
        self.kind = rootView.kind
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard window?.ignoresMouseEvents == false,
              bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }


    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    func cancel() {
        offset = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, !window.ignoresMouseEvents else { return }
        let pointer = NSEvent.mouseLocation
        offset = CGPoint(x: pointer.x - window.frame.midX, y: pointer.y - window.frame.midY)
        lastDragTime = event.timestamp
        begin?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let offset, window?.ignoresMouseEvents == false else { return }
        let pointer = NSEvent.mouseLocation
        move?(CGPoint(x: pointer.x - offset.x, y: pointer.y - offset.y),
              max(1.0 / 120, event.timestamp - lastDragTime))
        lastDragTime = event.timestamp
    }

    override func mouseUp(with event: NSEvent) {
        guard let offset else { return }
        if event.timestamp - lastDragTime > 0.12 {
            let pointer = NSEvent.mouseLocation
            move?(CGPoint(x: pointer.x - offset.x, y: pointer.y - offset.y),
                  event.timestamp - lastDragTime)
        }
        cancel()
        release?()
    }
}

enum SnowInputRegions {
    enum Kind {
        case ground
        case dock
        case window
    }

    struct Region {
        let rect: CGRect
        let kind: Kind
    }

    private static let limit = 48

    static func make(from frame: SnowFrame, dockBounds: CGRect?) -> [Region] {
        var result: [Region] = []
        for drift in frame.drifts {
            appendRegions(for: drift, frame: frame.size, dockBounds: dockBounds, to: &result)
            if result.count == limit { break }
        }
        return result
    }

    private static func appendRegions(for drift: SnowDrift, frame: CGSize, dockBounds: CGRect?,
                                      to result: inout [Region]) {
        let kind: Kind = if drift.id == nil { .ground } else if drift.id == "dock" { .dock } else { .window }
        let baseline = kind == .dock ? max(drift.baseY, dockBounds?.maxY ?? 0) : drift.baseY
        let leftBound = max(0, drift.left)
        let rightBound = min(frame.width, drift.right)
        guard baseline >= 0, baseline < frame.height, leftBound < rightBound else { return }

        var runStart: CGFloat?
        var runEnd: CGFloat = 0
        var runHeight: CGFloat = 0
        for index in drift.heights.indices {
            let columnStart = drift.firstColumnX + CGFloat(index) * drift.columnWidth
            let left = max(columnStart, leftBound)
            let right = min(columnStart + drift.columnWidth, rightBound)
            let column = CGRect(x: left, y: baseline, width: max(0, right - left), height: 1)
            let snowHeight = drift.heights[index] * depthScale(at: column.midX, drift: drift, dockBounds: dockBounds)
            let avoidsDock = kind != .ground || dockBounds.map {
                column.maxX <= $0.minX || column.minX >= $0.maxX
            } ?? true
            let canRoll = column.width > 0 && snowHeight >= 0.65 && avoidsDock
            if let start = runStart, !canRoll || left > runEnd + 0.5 || left - start >= 128 {
                let height = min(frame.height - baseline, max(4, runHeight + 2))
                result.append(Region(rect: CGRect(x: start, y: baseline, width: runEnd - start, height: height), kind: kind))
                if result.count == limit { return }
                runStart = nil
                runHeight = 0
            }
            guard canRoll else { continue }
            if runStart == nil { runStart = left }
            runEnd = right
            runHeight = max(runHeight, snowHeight)
        }
        if let start = runStart {
            let height = min(frame.height - baseline, max(4, runHeight + 2))
            result.append(Region(rect: CGRect(x: start, y: baseline, width: runEnd - start, height: height), kind: kind))
        }
    }

    static func depthScale(at x: CGFloat, drift: SnowDrift, dockBounds: CGRect?) -> CGFloat {
        let distance: CGFloat
        let taper: CGFloat
        if drift.id == "dock" {
            distance = min(x - drift.left, drift.right - x)
            taper = 24
        } else if drift.id == nil, let dockBounds {
            let clearance = dockBounds.insetBy(dx: -12, dy: 0)
            distance = max(clearance.minX - x, x - clearance.maxX)
            taper = 88
        } else {
            return 1
        }
        let fraction = min(1, max(0, distance / taper))
        return fraction * fraction * (3 - 2 * fraction)
    }
}

@MainActor
private final class SnowSurfaceInteraction: NSView {
    var begin: ((CGPoint) -> Bool)?
    var move: ((CGPoint, TimeInterval) -> Void)?
    var release: (() -> Void)?
    var shovel: ((CGPoint, CGFloat) -> Void)?
    var usesShovel = false
    private var lastPoint: CGPoint?
    private var lastDragTime: TimeInterval = 0

    var isTracking: Bool { lastPoint != nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: usesShovel ? .crosshair : .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(1.0 / 255).setFill()
        dirtyRect.fill()
    }

    func cancel() {
        lastPoint = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.ignoresMouseEvents == false else { return }
        let point = NSEvent.mouseLocation
        if usesShovel {
            shovel?(point, 1)
        } else if begin?(point) != true {
            return
        }
        lastPoint = point
        lastDragTime = event.timestamp
    }

    override func mouseDragged(with event: NSEvent) {
        guard let previous = lastPoint, window?.ignoresMouseEvents == false else { return }
        let point = NSEvent.mouseLocation
        if usesShovel {
            let distance = hypot(point.x - previous.x, point.y - previous.y)
            guard distance >= 7 else { return }
            let steps = max(1, min(24, Int(ceil(distance / 12))))
            let direction: CGFloat = point.x < previous.x ? -1 : 1
            for step in 1...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                shovel?(CGPoint(x: previous.x + (point.x - previous.x) * fraction,
                                y: previous.y + (point.y - previous.y) * fraction), direction)
            }
        } else {
            move?(point, max(1.0 / 120, event.timestamp - lastDragTime))
        }
        lastPoint = point
        lastDragTime = event.timestamp
    }

    override func mouseUp(with event: NSEvent) {
        guard isTracking else { return }
        if !usesShovel {
            if event.timestamp - lastDragTime > 0.12 {
                move?(NSEvent.mouseLocation, event.timestamp - lastDragTime)
            }
            release?()
        }
        cancel()
    }
}
