import AppKit
import SwiftUI

@MainActor
final class DisplaySnow {
    var geometry: DisplayGeometry
    var world: SnowWorld
    private let falling: PassiveSnowPanel
    private let settled: PassiveSnowPanel
    private let dockSnow: PassiveSnowPanel
    private let windowSnow: PassiveSnowPanel
    private let plowSnow: PassiveSnowPanel
    private let wallpaper: PassiveSnowPanel
    private let wallpaperView = WallpaperView(frame: .zero)
    private lazy var gameWindows = SnowGameWindows(display: self)
    private var locked = true
    private var tool = DesktopSnowTool.none
    private let fallingView: NSHostingView<SnowView>
    private let settledView: NSHostingView<SnowView>
    private let dockView: NSHostingView<SnowView>
    private let windowView: NSHostingView<SnowView>
    private let plowView: NSHostingView<SnowView>
    private var lastFallingFrame: SnowFrame?
    var dockBounds: CGRect?
    private var lastSettledFrame: SnowFrame?
    private var lastDockBounds: CGRect?
    private var lastPlow: CGPoint?
    private var lastPlowLoad: CGFloat = 0
    private var lastWindowFrame: SnowFrame?
    private var lastDockFrame: SnowFrame?
    private(set) var isVisible = false

    init(screen: NSScreen) {
        geometry = DisplayGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame)
        let world = SnowWorld(size: screen.frame.size)
        self.world = world

        let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) - 1
        wallpaper = PassiveSnowPanel(frame: screen.frame, level: NSWindow.Level(rawValue: desktopLevel - 1))
        wallpaper.contentView = wallpaperView
        falling = PassiveSnowPanel(frame: screen.frame, level: NSWindow.Level(rawValue: desktopLevel))
        settled = PassiveSnowPanel(frame: screen.frame, level: NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 2))
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        // The moving plow can cross the Dock, while its snow stays below the icons.
        dockSnow = PassiveSnowPanel(frame: screen.frame, level: NSWindow.Level(rawValue: dockLevel - 3))
        plowSnow = PassiveSnowPanel(frame: screen.frame, level: NSWindow.Level(rawValue: dockLevel + 1))
        windowSnow = PassiveSnowPanel(
            frame: screen.frame, level: NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
        )
        let empty = SnowFrame(size: screen.frame.size, flakes: [], drifts: [])
        dockView = NSHostingView(rootView: SnowView(frame: empty))
        windowView = NSHostingView(rootView: SnowView(frame: empty, layer: .settled))
        plowView = NSHostingView(rootView: SnowView(frame: empty))
        dockSnow.contentView = dockView
        windowSnow.contentView = windowView
        plowSnow.contentView = plowView
        fallingView = NSHostingView(rootView: SnowView(frame: world.frame, layer: .falling))
        settledView = NSHostingView(rootView: SnowView(frame: world.frame, layer: .settled))
        falling.contentView = fallingView
        settled.contentView = settledView
    }

    func setWallpaper(_ image: NSImage?) {
        wallpaperView.image = image
        if isVisible && image != nil {
            wallpaper.orderFrontRegardless()
        } else {
            wallpaper.orderOut(nil)
        }
    }

    func configureInteraction(locked: Bool, tool: DesktopSnowTool) {
        let changed = self.locked != locked || self.tool != tool
        self.locked = locked
        self.tool = tool
        if locked && changed { gameWindows.cancel() }
    }

    func render() {
        guard isVisible else { return }
        let game = world.gameFrame
        let frame = world.frame
        gameWindows.synchronize(bodies: game.bodies, locked: locked, tool: tool, snowFrame: frame)
        var fallingFlakes: [SnowFlake] = []
        var dislodgedFlakes: [SnowFlake] = []
        for flake in frame.flakes {
            if flake.isDislodged {
                dislodgedFlakes.append(flake)
            } else {
                fallingFlakes.append(flake)
            }
        }

        let fallingFrame = SnowFrame(size: frame.size, flakes: fallingFlakes, drifts: [])
        if lastFallingFrame != fallingFrame {
            lastFallingFrame = fallingFrame
            fallingView.rootView = SnowView(frame: fallingFrame, layer: .falling)
        }

        let settledFrame = SnowFrame(size: frame.size, flakes: [], drifts: frame.drifts.filter { $0.id == nil })
        if lastSettledFrame != settledFrame || lastDockBounds != dockBounds {
            lastSettledFrame = settledFrame
            lastDockBounds = dockBounds
            settledView.rootView = SnowView(frame: settledFrame, layer: .settled, dockBounds: dockBounds)
        }

        let dockFrame = SnowFrame(size: frame.size, flakes: [], drifts: frame.drifts.filter { $0.id == "dock" })
        if lastDockFrame != dockFrame {
            lastDockFrame = dockFrame
            dockView.rootView = SnowView(frame: dockFrame)
        }
        setLayer(dockSnow, visible: dockBounds != nil && !dockFrame.drifts.isEmpty)

        let windowFrame = SnowFrame(size: frame.size, flakes: dislodgedFlakes,
                                    drifts: frame.drifts.filter { $0.id != nil && $0.id != "dock" })
        if lastWindowFrame != windowFrame {
            lastWindowFrame = windowFrame
            windowView.rootView = SnowView(frame: windowFrame, layer: .settled)
        }
        setLayer(windowSnow, visible: !windowFrame.drifts.isEmpty || !dislodgedFlakes.isEmpty)

        if lastPlow != game.plow || lastPlowLoad != game.plowLoad {
            lastPlow = game.plow
            lastPlowLoad = game.plowLoad
            let empty = SnowFrame(size: frame.size, flakes: [], drifts: [])
            plowView.rootView = SnowView(frame: empty, plow: game.plow, plowLoad: game.plowLoad)
        }
        setLayer(plowSnow, visible: game.plow != nil)
    }

    private func setLayer(_ layer: NSPanel, visible: Bool) {
        guard layer.isVisible != visible else { return }
        if visible { layer.orderFrontRegardless() } else { layer.orderOut(nil) }
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            if wallpaperView.image != nil { wallpaper.orderFrontRegardless() }
            falling.orderFrontRegardless()
            settled.orderFrontRegardless()
        } else {
            world.resetClock()
            world.cancelInteraction()
            gameWindows.hide()
            wallpaper.orderOut(nil)
            falling.orderOut(nil)
            settled.orderOut(nil)
            dockSnow.orderOut(nil)
            plowSnow.orderOut(nil)
            windowSnow.orderOut(nil)
        }
    }
}


@MainActor
private final class WallpaperView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let target = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                            width: size.width, height: size.height)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: target)
    }
}
