import AppKit
import Combine
import Darwin
import SwiftUI

@main
enum SnowMacApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = SnowMacDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class SnowMacDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var coordinator: OverlayCoordinator?
    private var instanceLock: Int32 = -1
    private var preferences: SnowMacPreferences?
    private var preferencesSubscription: AnyCancellable?
    private var appearanceObservation: NSKeyValueObservation?
    private var wallpaperURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil { return }
        let lockPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("app.snowmac.SnowMac.lock").path
        instanceLock = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard instanceLock >= 0, flock(instanceLock, LOCK_EX | LOCK_NB) == 0 else {
            NSApplication.shared.terminate(nil)
            return
        }
        let coordinator = OverlayCoordinator()
        self.coordinator = coordinator
        let preferences = SnowMacPreferences()
        self.preferences = preferences

        let popover = NSPopover()
        popover.behavior = .transient
        let panel = NSHostingController(
            rootView: StatusPanel(coordinator: coordinator, preferences: preferences)
        )
        panel.sizingOptions = []
        popover.contentViewController = panel
        self.popover = popover

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "SnowMac")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        coordinator.start()
        preferencesSubscription = preferences.$settings.sink { [weak self] settings in
            self?.apply(settings, to: coordinator)
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                if let self, let preferences = self.preferences {
                    self.applyWallpaper(preferences.settings)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appearanceObservation?.invalidate()
        preferencesSubscription?.cancel()
        coordinator?.stop()
        if instanceLock >= 0 {
            close(instanceLock)
            instanceLock = -1
        }
    }

    private func apply(_ settings: SnowMacSettings, to coordinator: OverlayCoordinator) {
        if coordinator.intensity != settings.snowfall { coordinator.setIntensity(settings.snowfall) }
        if coordinator.floorDepth != settings.depth { coordinator.floorDepth = settings.depth }
        if coordinator.wind != settings.wind { coordinator.wind = settings.wind }
        if coordinator.snowOnSupports != settings.snowOnSupports {
            coordinator.snowOnSupports = settings.snowOnSupports
        }
        if coordinator.autoPlow != settings.autoPlow { coordinator.autoPlow = settings.autoPlow }
        if coordinator.clearsDock != settings.clearsDock { coordinator.clearsDock = settings.clearsDock }
        coordinator.plowAcrossDisplays = settings.plowAcrossDisplays ?? false
        let displays = DisplaySelection(rawValue: settings.displays) ?? .all
        if coordinator.displaySelection != displays { coordinator.displaySelection = displays }
        applyWallpaper(settings)
    }

    private func applyWallpaper(_ settings: SnowMacSettings) {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let url = settings.scene.imageURL(lighting: settings.lighting, darkAppearance: dark)
        guard wallpaperURL != url else { return }
        wallpaperURL = url
        coordinator?.setWallpaper(url)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let workArea = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                popover.contentSize = Self.panelContentSize(in: workArea)
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.async { [weak popover, weak button] in
                guard let popover, popover.isShown, let button, let buttonWindow = button.window,
                      let screen = buttonWindow.screen,
                      let window = popover.contentViewController?.view.window else { return }
                let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                let origin = Self.panelOrigin(frame: window.frame, below: anchor, in: screen.visibleFrame)
                if origin != window.frame.origin { window.setFrameOrigin(origin) }
            }
        }
    }

    nonisolated static func panelContentSize(in workArea: CGRect) -> CGSize {
        CGSize(width: max(1, min(306, workArea.width - 24)),
               height: max(1, min(505, workArea.height - 40)))
    }

    nonisolated static func panelOrigin(frame: CGRect, below anchor: CGRect, in workArea: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(frame.minX, workArea.minX + 4), max(workArea.minX + 4, workArea.maxX - frame.width - 4)),
            y: max(workArea.minY + 4, min(workArea.maxY - 4, anchor.minY - 2) - frame.height)
        )
    }
}
