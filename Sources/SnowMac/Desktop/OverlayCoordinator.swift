import AppKit
import SwiftUI

enum DisplaySelection: String { case all, primary }
enum DesktopSnowTool: String { case none, collect, shovel }

@MainActor
final class OverlayCoordinator: NSObject, ObservableObject {
    @Published private(set) var isLocked = true
    @Published private(set) var intensity = 0.25
    @Published var floorDepth: Double = 40
    @Published var wind: Double = 0
    @Published var snowOnSupports = true
    @Published var autoPlow = false {
        didSet { autoPlowTime = 0 }
    }
    @Published var clearsDock = false
    var plowAcrossDisplays = false
    @Published var displaySelection: DisplaySelection = .all {
        didSet {
            guard displaySelection != oldValue else { return }
            if displaySelection == .primary {
                for display in displays.dropFirst() { display.setVisible(false) }
            }
            lastSampleTime = nil
        }
    }
    @Published private(set) var tool: DesktopSnowTool = .none

    private let provider = WindowGeometryProvider()
    private let dockGeometry = DockGeometryProvider()
    private var displays: [DisplaySnow] = []
    private var sceneImage: NSImage?
    private var autoPlowTime: TimeInterval = 0
    private var timer: Timer?
    private var motion = WindowMotion()
    private var lastFrameTime: TimeInterval?
    private var lastSampleTime: TimeInterval?
    private var isSleeping = false
    @Published private(set) var isDesktopActive = false

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildDisplays),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(displaySlept),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(displayWoke),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        rebuildDisplays()
        frontmostApplicationChanged()
        if timer == nil { armTimer() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        closeWindows()
    }

    func setLocked(_ locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
        if locked { cancelPlay() }
        armTimer()
    }

    func setIntensity(_ intensity: Double) {
        self.intensity = min(max(intensity, 0), 1)
    }

    @objc private func rebuildDisplays() {
        guard !isSleeping else { return }
        closeWindows()
        resetMotion()
        let screens = NSScreen.screens
        displays = screens.map { DisplaySnow(screen: $0) }

        for display in displays { display.setWallpaper(sceneImage) }
    }

    func setWallpaper(_ url: URL?) {
        sceneImage = url.flatMap { NSImage(contentsOf: $0) }
        for display in displays { display.setWallpaper(sceneImage) }
    }

    func spawn(_ kind: SnowBodyKind) {
        guard !isLocked, let display = activeDisplay else { return }
        display.world.spawn(kind)
        display.render()
    }

    func startPlow() {
        guard !isLocked else { return }
        let targets = plowAcrossDisplays ? displays.filter(\.isVisible) : activeDisplay.map { [$0] } ?? []
        for display in targets { display.world.startPlow(clearsDock: clearsDock) }
    }

    func setTool(_ tool: DesktopSnowTool) {
        guard tool == .none || !isLocked else { return }
        self.tool = self.tool == tool ? .none : tool
        for display in displays { display.configureInteraction(locked: isLocked, tool: self.tool) }
    }

    private var activeDisplay: DisplaySnow? {
        let cursor = NSEvent.mouseLocation
        return displays.first { $0.isVisible && $0.geometry.frame.contains(cursor) }
            ?? displays.first { $0.isVisible }
    }

    private func cancelPlay() {
        tool = .none
        autoPlowTime = 0
        for display in displays {
            display.world.cancelInteraction()
            display.configureInteraction(locked: true, tool: .none)
        }
    }

    @objc private func frontmostApplicationChanged() {
        let app = NSWorkspace.shared.frontmostApplication
        let identifier = app?.bundleIdentifier
        let snowMacIdentifier = Bundle.main.bundleIdentifier
        let hasVisibleWindow: Bool?
        if identifier != "com.apple.finder", identifier != snowMacIdentifier,
           let owner = app?.processIdentifier, let primary = displays.first {
            hasVisibleWindow = provider.windows(primaryFrame: primary.geometry.frame).map { windows in
                Self.hasVisibleWindow(owner: owner, windows: windows, frames: displays.map(\.geometry.visibleFrame))
            }
        } else {
            hasVisibleWindow = nil
        }
        let next = Self.showsDesktopSnow(
            bundleIdentifier: identifier,
            snowMacIdentifier: snowMacIdentifier,
            previouslyVisible: isDesktopActive,
            hasVisibleForegroundWindow: hasVisibleWindow
        )
        guard next != isDesktopActive else { return }
        isDesktopActive = next
        resetMotion()
        if !next {
            for display in displays { display.setVisible(false) }
            cancelPlay()
        }
        armTimer()
    }

    nonisolated static func showsDesktopSnow(
        bundleIdentifier: String?,
        snowMacIdentifier: String?,
        previouslyVisible: Bool,
        hasVisibleForegroundWindow: Bool? = nil
    ) -> Bool {
        guard let bundleIdentifier else { return false }
        if bundleIdentifier == snowMacIdentifier { return previouslyVisible }
        return bundleIdentifier == "com.apple.finder" || hasVisibleForegroundWindow == false
    }

    nonisolated static func hasVisibleWindow(owner: Int32, windows: [DesktopWindow], frames: [CGRect]) -> Bool {
        windows.contains { window in
            guard window.identity.owner == owner, window.isSupport else { return false }
            return frames.contains { frame in
                let visible = window.frame.intersection(frame)
                return visible.width >= 24 && visible.height >= 24
            }
        }
    }

    @objc private func spaceChanged() {
        cancelPlay()
        resetMotion()
        for display in displays {
            display.world.update(size: display.geometry.frame.size, supports: [])
        }
    }

    @objc private func displaySlept() {
        isSleeping = true
        armTimer()
        resetMotion()
        for display in displays {
            display.setVisible(false)
        }
        cancelPlay()
    }

    @objc private func displayWoke() {
        isSleeping = false
        let currentGeometry = NSScreen.screens.map {
            DisplayGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        if currentGeometry != displays.map(\.geometry) {
            rebuildDisplays()
        } else {
            resetMotion()
        }
        armTimer()
    }

    private func armTimer() {
        timer?.invalidate()
        timer = nil
        guard !isSleeping else { return }
        let interval = isDesktopActive ? 1.0 / (isLocked ? 30.0 : 60.0) : 0.25
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func closeWindows() {
        cancelPlay()
        for display in displays { display.setVisible(false) }
        displays.removeAll()
    }

    private func resetMotion() {
        lastFrameTime = nil
        lastSampleTime = nil
        motion.reset()
        for display in displays { display.world.resetClock() }
    }

    @objc private func tick() {
        guard !isSleeping, let primary = displays.first else { return }
        if !isDesktopActive {
            frontmostApplicationChanged()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastFrameTime.map { now - $0 } ?? 0
        lastFrameTime = now

        let sampleInterval = 1.0 / (isLocked ? 15.0 : 30.0)
        if now - (lastSampleTime ?? -.infinity) >= sampleInterval - 0.002 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.finder" {
                frontmostApplicationChanged()
                guard isDesktopActive else { return }
            }
            sampleWindows(primary: primary.geometry.frame, now: now)
            lastSampleTime = now
        }

        if autoPlow && !isLocked {
            autoPlowTime += elapsed
            if autoPlowTime >= 45 {
                autoPlowTime = 0
                startPlow()
            }
        }

        for display in displays where display.isVisible {
            display.world.advance(elapsed: elapsed, intensity: intensity, locked: isLocked,
                                  floorDepth: floorDepth, wind: wind, snowOnSupports: snowOnSupports,
                                  toolsEnabled: !isLocked)
            display.configureInteraction(locked: isLocked, tool: tool)
            display.render()
        }
    }

    private func sampleWindows(primary: CGRect, now: TimeInterval) {
        let observedWindows = provider.windows(primaryFrame: primary)
        if observedWindows == nil { motion.reset() }
        let windows = observedWindows ?? []
        let velocity = motion.update(windows: windows, timestamp: now)

        let screens = NSScreen.screens
        for (index, display) in displays.enumerated() {
            let frame = display.geometry.frame
            if let screen = screens.first(where: { $0.frame == frame }) {
                display.geometry = DisplayGeometry(frame: frame, visibleFrame: screen.visibleFrame)
            }
            let selected = displaySelection == .all || index == 0
            let visible = selected && DesktopSupports.displayIsVisible(for: observedWindows, on: display.geometry)
            display.setVisible(visible)
            guard visible else { continue }

            let surfaces = DesktopSupports.surfaces(for: windows, on: display.geometry)
            var supports = surfaces.map { surface in
                SnowSupport(
                    id: surface.id,
                    minX: surface.xRange.lowerBound,
                    maxX: surface.xRange.upperBound,
                    y: surface.y,
                    velocityX: velocity[surface.identity]?.dx ?? 0,
                    velocityY: velocity[surface.identity]?.dy ?? 0,
                    visibleRanges: surface.visibleRanges
                )
            }
            display.dockBounds = dockGeometry.bottomBounds(for: display.geometry, primaryFrame: primary)
            if let dock = display.dockBounds {
                supports.append(SnowSupport(id: "dock", minX: dock.minX, maxX: dock.maxX,
                                            y: dock.maxY, velocityX: 0))
            }
            display.world.update(size: frame.size, supports: supports)
        }
    }
}

@MainActor
final class PassiveSnowPanel: NSPanel {
    init(frame: CGRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.level = level
        configureOverlay()
        ignoresMouseEvents = true
    }
}

extension NSPanel {
    fileprivate func configureOverlay() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        animationBehavior = .none
        isMovable = false
    }
}

@MainActor
final class SnowMarkerWindow: NSPanel {
    private let marker = SnowMarker(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
    private var hasBeenUnlocked = false

    init(origin: NSPoint) {
        super.init(contentRect: NSRect(origin: origin, size: marker.frame.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        configureOverlay()
        ignoresMouseEvents = true
        contentView = marker
    }

    func reconcile(locked: Bool, visibleFrames: [CGRect]) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let onVisibleDisplay = visibleFrames.contains { $0.contains(center) }
        if !locked && onVisibleDisplay { hasBeenUnlocked = true }
        ignoresMouseEvents = locked || !onVisibleDisplay
        if ignoresMouseEvents { marker.cancelDrag() }
        if hasBeenUnlocked && onVisibleDisplay {
            if !isVisible { orderFrontRegardless() }
        } else if isVisible {
            orderOut(nil)
        }
    }
}
