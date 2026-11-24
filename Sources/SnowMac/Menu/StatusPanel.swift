import AppKit
import SwiftUI

struct StatusPanel: View {
    @ObservedObject var coordinator: OverlayCoordinator
    @ObservedObject var preferences: SnowMacPreferences
    @State private var showsSettings = false
    @State private var guideStep = 0

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !preferences.settings.hasSeenGuide { guide }
                    snowfall
                    driftDepth
                    gameplay
                    sceneControls
                    if showsSettings {
                        Divider()
                        settings
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
                .padding(14)
        }
    }

    private var header: some View {
        HStack {
            Label("SnowMac", systemImage: "snowflake")
                .font(.headline)
            Spacer()
            Button {
                coordinator.setLocked(!coordinator.isLocked)
            } label: {
                Image(systemName: coordinator.isLocked ? "lock.fill" : "lock.open")
                    .frame(width: 24, height: 22)
                    .foregroundStyle(coordinator.isLocked ? Color.accentColor : Color.secondary)
            }
            .accessibilityLabel("Desktop interaction lock")
            .accessibilityValue(coordinator.isLocked ? "Locked" : "Unlocked")
            .help(coordinator.isLocked ? "Unlock desktop interaction" : "Lock desktop interaction")
        }
    }

    private var snowfall: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Snowfall").fontWeight(.medium)
                Spacer()
                Text(preferences.settings.snowfall, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $preferences.settings.snowfall, in: 0...1) { Text("Snowfall") }
                .labelsHidden()
        }
    }

    private var driftDepth: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Snowdrift depth")
                .fontWeight(.medium)
                .accessibilityHidden(true)
            Slider(value: $preferences.settings.depth, in: 0...80) { Text("Snowdrift depth") }
                .labelsHidden()
        }
    }

    private var gameplay: some View {
        Button {
            coordinator.startPlow()
        } label: {
            Label("Call snowplow", systemImage: "truck.box")
        }
        .disabled(coordinator.isLocked || !coordinator.isDesktopActive)
        .help("Unlock on the desktop to send the plow across the snow.")
    }

    private var sceneControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(SnowScene.allCases) { scene in
                    Button {
                        preferences.settings.scene = scene
                    } label: {
                        if scene == preferences.settings.scene {
                            Label(scene.title, systemImage: "checkmark")
                        } else {
                            Label {
                                Text(scene.title)
                            } icon: {
                                scenePreview(for: scene)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    scenePreview(for: preferences.settings.scene)
                    Text(preferences.settings.scene.title).lineLimit(1)
                    Spacer()
                }
            }
            .accessibilityLabel("Desktop scene")
            .accessibilityValue(preferences.settings.scene.title)

            if preferences.settings.scene != .current {
                Picker("Lighting", selection: $preferences.settings.lighting) {
                    ForEach(SceneLighting.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private func scenePreview(for scene: SnowScene) -> some View {
        if let url = scene.previewURL(), let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 22)
                .clipShape(.rect(cornerRadius: 3))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "photo")
                .frame(width: 36, height: 22)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                showsSettings.toggle()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            Button("Quit SnowMac") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $preferences.settings.wind, in: -1...1) {
                Text("Wind")
            }
            Toggle("Snow on windows and Dock", isOn: $preferences.settings.snowOnSupports)
            Toggle("Run plow automatically", isOn: $preferences.settings.autoPlow)
            Toggle("Plow clears Dock", isOn: $preferences.settings.clearsDock)
            Toggle("Plow all enabled displays", isOn: Binding(
                get: { preferences.settings.plowAcrossDisplays ?? false },
                set: { preferences.settings.plowAcrossDisplays = $0 }
            ))
            Picker("Displays", selection: $preferences.settings.displays) {
                Text("All displays").tag(DisplaySelection.all.rawValue)
                Text("Main display").tag(DisplaySelection.primary.rawValue)
            }
            Button("Show quick guide") {
                guideStep = 0
                preferences.settings.hasSeenGuide = false
                showsSettings = false
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(guideStep == 0 ? "Snow in the menu bar" : "Play on the desktop")
                .font(.subheadline.weight(.semibold))
            Text(guideStep == 0
                 ? "Try the snowfall slider. Open SnowMac anytime from the snowflake icon."
                 : "Unlock, then drag across settled snow to roll a snowball. Stack three to make a snowman.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip") { finishGuide() }
                Spacer()
                if guideStep == 0 {
                    Button("Next") { guideStep = 1 }
                } else {
                    Button("Done") { finishGuide() }
                }
            }
        }
        .padding(9)
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }

    private func finishGuide() {
        preferences.settings.hasSeenGuide = true
        guideStep = 0
    }
}
