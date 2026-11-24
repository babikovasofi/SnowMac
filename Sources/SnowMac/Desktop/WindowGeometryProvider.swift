import AppKit
import CoreGraphics

struct WindowGeometryProvider {
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let normalLevel = Int(CGWindowLevelForKey(.normalWindow))

    func windows(primaryFrame: CGRect) -> [DesktopWindow]? {
        guard let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        return entries.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let owner = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value != ownPID,
                  let level = entry[kCGWindowLayer as String] as? NSNumber,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  quartzFrame.width > 1, quartzFrame.height > 1,
                  (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue != 0 else {
                return nil
            }

            let frame = DisplayGeometry.appKitRect(for: quartzFrame, primaryFrame: primaryFrame)
            let isSupport = level.intValue == normalLevel && frame.width >= 80 && frame.height >= 48
            return DesktopWindow(
                identity: .init(number: number.uint32Value, owner: owner.int32Value),
                frame: frame,
                isSupport: isSupport
            )
        }
    }
}
