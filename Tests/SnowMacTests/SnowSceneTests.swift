import AppKit
import XCTest
@testable import SnowMac

final class SnowSceneTests: XCTestCase {
    func testStatusPanelStaysBelowMenuBarOnAShortSecondaryDisplay() {
        let screen = CGRect(x: -640, y: -120, width: 640, height: 380)
        let anchor = CGRect(x: -35, y: 260, width: 28, height: 28)
        let content = SnowMacDelegate.panelContentSize(in: screen)
        let nativeSize = CGSize(width: content.width + 12, height: content.height + 18)
        let frame = CGRect(origin: CGPoint(x: -180, y: 20), size: nativeSize)
        let origin = SnowMacDelegate.panelOrigin(frame: frame, below: anchor, in: screen)
        let positioned = CGRect(origin: origin, size: nativeSize)
        XCTAssertTrue(screen.contains(positioned))
        XCTAssertLessThan(positioned.maxY, anchor.minY)
    }

    func testSystemLightingFollowsTheCurrentAppearanceAndOverridesAreStable() {
        XCTAssertFalse(SceneLighting.system.isNight(darkAppearance: false))
        XCTAssertTrue(SceneLighting.system.isNight(darkAppearance: true))
        XCTAssertFalse(SceneLighting.day.isNight(darkAppearance: true))
        XCTAssertTrue(SceneLighting.night.isNight(darkAppearance: false))
    }

    func testSceneCatalogAndCurrentWallpaperRoundTrip() throws {
        let builtInScenes = SnowScene.allCases.filter { $0 != .current }
        XCTAssertEqual(builtInScenes.count, 5)
        var decodedURLs: Set<URL> = []
        for scene in builtInScenes {
            for lighting in [SceneLighting.day, .night] {
                let url = try XCTUnwrap(scene.imageURL(lighting: lighting, darkAppearance: false), scene.rawValue)
                XCTAssertNotNil(NSImage(contentsOf: url), url.lastPathComponent)
                XCTAssertTrue(decodedURLs.insert(url).inserted)
            }
            let preview = try XCTUnwrap(scene.previewURL(), scene.rawValue)
            XCTAssertNotNil(NSImage(contentsOf: preview), preview.lastPathComponent)
        }
        XCTAssertEqual(decodedURLs.count, 10)
        XCTAssertNil(SnowScene.current.imageURL(lighting: .night, darkAppearance: true))
        XCTAssertNil(SnowScene.current.previewURL())
    }

    @MainActor
    func testChangingWallpaperKeepsTheLiveSnowWorld() throws {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("No local display") }
        let display = DisplaySnow(screen: screen)
        let step = 1.0 / 60
        for _ in 0..<(16 * 60) {
            display.world.advance(elapsed: step, intensity: 0.5, locked: false)
        }
        display.world.spawn(.snowman)
        let snow = display.world.frame
        let game = display.world.gameFrame
        XCTAssertTrue(snow.drifts.flatMap(\.heights).contains { $0 > 0 })
        XCTAssertEqual(game.bodies.count, 1)

        display.setWallpaper(NSImage(size: CGSize(width: 100, height: 60)))
        XCTAssertEqual(display.world.frame, snow)
        XCTAssertEqual(display.world.gameFrame, game)
        display.setWallpaper(nil)
        XCTAssertEqual(display.world.frame, snow)
        XCTAssertEqual(display.world.gameFrame, game)
    }

    func testPreferencesPersistAndQuickGuideCanBeReplayed() throws {
        let suite = "SnowMacTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = SnowMacPreferences(defaults: defaults)
        XCTAssertEqual(fresh.settings, SnowMacSettings())
        XCTAssertEqual(fresh.settings.scene, .current)
        XCTAssertFalse(fresh.settings.hasSeenGuide)
        fresh.settings.snowfall = 0.6
        fresh.settings.scene = .village
        fresh.settings.lighting = .night
        fresh.settings.hasSeenGuide = true

        let reloaded = SnowMacPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.settings, fresh.settings)
        reloaded.settings.hasSeenGuide = false
        XCTAssertFalse(SnowMacPreferences(defaults: defaults).settings.hasSeenGuide)
        XCTAssertEqual(reloaded.settings.scene, .village)
    }

    func testUnreadablePreferencesFallBackToSafeDefaults() throws {
        let suite = "SnowMacTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("missing keys".utf8), forKey: SnowMacPreferences.storageKey)
        XCTAssertEqual(SnowMacPreferences(defaults: defaults).settings, SnowMacSettings())
    }
}
