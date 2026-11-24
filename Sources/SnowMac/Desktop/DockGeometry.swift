import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class DockGeometryProvider {
    private struct Snapshot {
        let observedBounds: [CGRect]
        let itemCount: Int
        let preferredTileSize: CGFloat?
    }

    private let preferences = UserDefaults(suiteName: "com.apple.dock")
    private var snapshot: Snapshot?
    private var lastRead = -TimeInterval.infinity

    func bottomBounds(for display: DisplayGeometry, primaryFrame: CGRect) -> CGRect? {
        if let orientation = preferences?.string(forKey: "orientation"), orientation != "bottom" {
            return nil
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRead >= 0.75 {
            snapshot = readSnapshot()
            lastRead = now
        }
        guard let snapshot else { return nil }
        let liveVisibleFrame = NSScreen.screens.first { $0.frame == display.frame }?.visibleFrame
        let currentDisplay = DisplayGeometry(frame: display.frame, visibleFrame: liveVisibleFrame ?? display.visibleFrame)
        for bounds in snapshot.observedBounds {
            let appKitBounds = DisplayGeometry.appKitRect(for: bounds, primaryFrame: primaryFrame)
            if let dock = currentDisplay.localBottomDockBounds(observed: appKitBounds, horizontalPadding: 8) {
                return dock
            }
        }
        let verticalPadding: CGFloat
        if #available(macOS 26, *) { verticalPadding = 26 } else { verticalPadding = 20 }
        return currentDisplay.bottomDockBounds(itemCount: snapshot.itemCount,
                                               preferredTileSize: snapshot.preferredTileSize,
                                               verticalPadding: verticalPadding)
    }

    private func readSnapshot() -> Snapshot {
        let applications = NSWorkspace.shared.runningApplications
        let dock = applications.first { $0.bundleIdentifier == "com.apple.dock" }
        let observed = dock.flatMap { Self.accessibilityBounds(for: $0.processIdentifier) }
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let pinned = preferences?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        let others = preferences?.array(forKey: "persistent-others") ?? []
        let recents = (preferences?.object(forKey: "show-recents") as? Bool ?? true)
            ? (preferences?.array(forKey: "recent-apps") as? [[String: Any]] ?? []) : []
        let known = Set((pinned + recents).compactMap(Self.tileBundleIdentifier)).union(["com.apple.finder"])
        let regular = applications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        let unpinnedApps = regular.filter { app in
            app.bundleIdentifier.map { !known.contains($0) } ?? false
        }.count

        // Quartz also returns windows on other Spaces; bound this fallback contribution.
        let minimizedEstimate = preferences?.bool(forKey: "minimize-to-application") == true ? 0
            : Self.minimizedEstimate(windows, owners: Set(regular.filter { !$0.isHidden }.map(\.processIdentifier)))
        let dockWindows = windows.compactMap { window -> CGRect? in
            guard let dock, (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dock.processIdentifier,
                  (window[kCGWindowIsOnscreen as String] as? Bool) == true,
                  (window[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.dockWindow)) else {
                return nil
            }
            return Self.bounds(of: window)
        }
        let tileSize = preferences?.double(forKey: "tilesize") ?? 0
        return Snapshot(observedBounds: dockWindows + (observed.map { [$0] } ?? []),
                        itemCount: 2 + pinned.count + others.count + min(3, recents.count)
                            + unpinnedApps + minimizedEstimate,
                        preferredTileSize: tileSize > 0 ? CGFloat(tileSize) : nil)
    }

    private static func tileBundleIdentifier(_ tile: [String: Any]) -> String? {
        (tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
    }

    private static func bounds(of window: [String: Any]) -> CGRect? {
        guard let dictionary = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    private static func minimizedEstimate(_ windows: [[String: Any]], owners: Set<pid_t>) -> Int {
        let normal = Int(CGWindowLevelForKey(.normalWindow))
        return min(6, windows.lazy.filter { window in
            guard (window[kCGWindowIsOnscreen as String] as? Bool) != true,
                  (window[kCGWindowLayer as String] as? Int) == normal,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue == 1,
                  let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  owners.contains(owner), let bounds = bounds(of: window) else { return false }
            return bounds.width >= 80 && bounds.height >= 48
        }.count)
    }

    private static func accessibilityBounds(for pid: pid_t) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let dock = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(dock, 0.03)
        let children = attribute(kAXChildrenAttribute, of: dock) as? [AXUIElement] ?? []
        for child in children.prefix(8) {
            if attribute(kAXRoleAttribute, of: child) as? String == kAXListRole {
                return elementBounds(child)
            }
            let nested = attribute(kAXChildrenAttribute, of: child) as? [AXUIElement] ?? []
            for item in nested.prefix(8) where attribute(kAXRoleAttribute, of: item) as? String == kAXListRole {
                if let bounds = elementBounds(item) { return bounds }
            }
        }
        return nil
    }

    private static func elementBounds(_ element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = attribute(kAXPositionAttribute, of: element),
              let dimensions = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(dimensions) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(dimensions as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func attribute(_ key: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
}
