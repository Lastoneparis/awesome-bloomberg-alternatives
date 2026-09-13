import SwiftUI
import CriticalStrikeCore

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var tab: Tab = .controls

    enum Tab: String, CaseIterable {
        case controls = "Controls"
        case graphics = "Graphics"
        case audio = "Audio"
        case account = "Account"
    }

    private var settings: GameSettings { app.profile.settings }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Settings", onBack: { app.goBack() })

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(spacing: 10) {
                    switch tab {
                    case .controls: controlsSection
                    case .graphics: graphicsSection
                    case .audio: audioSection
                    case .account: accountSection
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: Controls

    private var controlsSection: some View {
        VStack(spacing: 10) {
            settingGroup("Aiming") {
                slider("Look sensitivity", value: binding(\.lookSensitivity), range: 0.2...3)
                slider("ADS sensitivity", value: binding(\.adsSensitivityScale), range: 0.2...1.5)
                slider("Scope sensitivity", value: binding(\.scopeSensitivityScale), range: 0.2...1.5)
                toggle("Invert vertical", binding(\.invertY))
                picker("Aim assist", selection: binding(\.aimAssist), options: AimAssistLevel.allCases) {
                    $0.displayName
                }
                Text("""
                Aim assist slows the camera near a target and applies a small pull while \
                you are aiming. It never changes where bullets land.
                """)
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textTertiary)
            }

            settingGroup("Gyro") {
                toggle("Gyro aiming", binding(\.gyroEnabled))
                if settings.gyroEnabled {
                    slider("Gyro sensitivity", value: binding(\.gyroSensitivity), range: 0.2...3)
                }
            }

            settingGroup("Firing") {
                picker("Fire mode", selection: binding(\.triggerMode), options: TriggerMode.allCases) {
                    $0.displayName
                }
                toggle("Auto sprint", binding(\.autoSprint))
                toggle("Auto reload", binding(\.autoReload))
                toggle("Tap to crouch / slide", binding(\.tapToCrouchSlide))
            }

            settingGroup("Layout") {
                toggle("Left-handed layout", binding(\.leftHanded))
                toggle("Joystick follows touch", binding(\.joystickFollowsTouch))
                slider("Stick dead zone", value: binding(\.joystickDeadZone), range: 0.02...0.35)
                Button("Customise HUD") { app.go(to: .hudEditor) }
                    .buttonStyle(SecondaryButtonStyle(wide: true))
            }
        }
    }

    // MARK: Graphics

    private var graphicsSection: some View {
        VStack(spacing: 10) {
            settingGroup("Quality") {
                picker("Preset", selection: binding(\.quality), options: GraphicsQuality.allCases) {
                    $0.displayName
                }
                picker("Frame rate", selection: binding(\.frameRateCap),
                       options: availableFrameRates) { $0.displayName }
                toggle("Dynamic resolution", binding(\.dynamicResolution))
                Text(DeviceCapabilities.summary())
                    .font(Theme.caption(9))
                    .foregroundStyle(Theme.textTertiary)
            }

            settingGroup("Camera") {
                slider("Field of view", value: binding(\.fieldOfView), range: 60...100, step: 1,
                       format: { String(format: "%.0f°", $0) })
                slider("Screen shake", value: binding(\.screenShake), range: 0...1)
            }

            settingGroup("HUD") {
                picker("Crosshair", selection: binding(\.crosshairStyle),
                       options: CrosshairKind.allCases) { $0.rawValue.capitalized }
                slider("Crosshair scale", value: binding(\.crosshairScale), range: 0.5...2)
                slider("HUD opacity", value: binding(\.hudOpacity), range: 0.3...1)
                toggle("Show minimap", binding(\.showMinimap))
                toggle("Show kill feed", binding(\.showKillFeed))
                toggle("Damage numbers", binding(\.showDamageNumbers))
                toggle("Blood effects", binding(\.showBlood))
            }

            settingGroup("Accessibility") {
                picker("Colour blind mode", selection: binding(\.colorBlindMode),
                       options: ColorBlindMode.allCases) { $0.displayName }
                Text("Changes team colours across the HUD, minimap and player outlines.")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var availableFrameRates: [FrameRateCap] {
        FrameRateCap.allCases.filter { $0.rawValue <= DeviceCapabilities.maximumFrameRate }
    }

    // MARK: Audio

    private var audioSection: some View {
        VStack(spacing: 10) {
            settingGroup("Volume") {
                slider("Master", value: binding(\.masterVolume), range: 0...1)
                slider("Music", value: binding(\.musicVolume), range: 0...1)
                slider("Effects", value: binding(\.sfxVolume), range: 0...1)
                slider("Voice", value: binding(\.voiceVolume), range: 0...1)
            }
            settingGroup("Options") {
                toggle("Spatial audio", binding(\.spatialAudioEnabled))
                toggle("Haptics", binding(\.hapticsEnabled))
                Text("Spatial audio places footsteps and gunfire in 3D. Headphones strongly recommended.")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(spacing: 10) {
            settingGroup("Profile") {
                HStack {
                    Text("Display name").font(Theme.body(14)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(app.profile.displayName).font(Theme.body(14))
                        .foregroundStyle(Theme.textPrimary)
                }
                HStack {
                    Text("Player ID").font(Theme.body(14)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(String(app.profile.accountID.prefix(8)).uppercased())
                        .font(Theme.mono(12)).foregroundStyle(Theme.textTertiary)
                }
                if app.gameCenter.isAuthenticated {
                    HStack {
                        Text("Game Center").font(Theme.body(14)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(app.gameCenter.playerDisplayName)
                            .font(Theme.body(14)).foregroundStyle(Theme.success)
                    }
                }
            }

            settingGroup("Multiplayer") {
                picker("Region", selection: binding(\.preferredRegion), options: Region.allCases) {
                    $0.displayName
                }
                picker("Bot difficulty", selection: binding(\.preferredBotDifficulty),
                       options: BotDifficulty.allCases) { $0.displayName }
                toggle("Text chat", binding(\.textChatEnabled))
                toggle("Profanity filter", binding(\.profanityFilter))
                toggle("Allow crossplay", binding(\.allowCrossplay))
            }

            settingGroup("Purchases") {
                if app.profile.entitlements.hasActiveVIP,
                   let expiry = app.profile.entitlements.vipExpiresAt {
                    HStack {
                        Text("VIP active").font(Theme.body(14)).foregroundStyle(Theme.warning)
                        Spacer()
                        Text(expiry.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Button("Restore Purchases") { app.restorePurchases() }
                    .buttonStyle(SecondaryButtonStyle(wide: true))
                Link("Manage Subscription",
                     destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.accentSecondary)
            }

            settingGroup("Legal") {
                Link("Privacy Policy", destination: URL(string: "https://criticalstrike.game/privacy")!)
                    .font(Theme.body(13)).foregroundStyle(Theme.accentSecondary)
                Link("Terms of Service", destination: URL(string: "https://criticalstrike.game/terms")!)
                    .font(Theme.body(13)).foregroundStyle(Theme.accentSecondary)
                Text("Version 1.0.0 (build 1)")
                    .font(Theme.caption(10)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: Helpers

    private func binding<T>(_ keyPath: WritableKeyPath<GameSettings, T>) -> Binding<T> {
        Binding(
            get: { app.profile.settings[keyPath: keyPath] },
            set: { newValue in app.updateSettings { $0[keyPath: keyPath] = newValue } })
    }

    private func settingGroup<Content: View>(_ title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(Theme.caption(10))
                .foregroundStyle(Theme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panel()
    }

    private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value)
            .font(Theme.body(14))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
    }

    private func slider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>,
                        step: Float = 0.05,
                        format: ((Float) -> String)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(Theme.body(14)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(format?(value.wrappedValue) ?? String(format: "%.2f", value.wrappedValue))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(Theme.accent)
        }
    }

    private func picker<T: Hashable>(_ title: String, selection: Binding<T>, options: [T],
                                     label: @escaping (T) -> String) -> some View {
        HStack {
            Text(title).font(Theme.body(14)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) { selection.wrappedValue = option }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(label(selection.wrappedValue))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.accent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

/// Drag-to-position HUD editor. Everything it writes is the same `HUDElementLayout` the
/// live HUD reads, so what you arrange here is exactly what you play with.
struct HUDLayoutEditorView: View {
    @EnvironmentObject private var app: AppState
    @State private var selected: String?

    /// A named struct rather than a tuple: SwiftUI's ForEach needs a key path to an id,
    /// and Swift has no key paths into tuple elements.
    private struct EditableElement: Identifiable {
        let id: String
        let label: String
    }

    private let editableElements: [EditableElement] = [
        EditableElement(id: "movementStick", label: "Movement"),
        EditableElement(id: "fireButton", label: "Fire"),
        EditableElement(id: "adsButton", label: "Aim"),
        EditableElement(id: "jumpButton", label: "Jump"),
        EditableElement(id: "crouchButton", label: "Crouch"),
        EditableElement(id: "reloadButton", label: "Reload"),
        EditableElement(id: "lethalButton", label: "Lethal"),
        EditableElement(id: "tacticalButton", label: "Tactical"),
        EditableElement(id: "meleeButton", label: "Melee"),
        EditableElement(id: "weaponSwap", label: "Swap"),
        EditableElement(id: "useButton", label: "Interact"),
        EditableElement(id: "pingButton", label: "Ping"),
        EditableElement(id: "minimap", label: "Minimap"),
        EditableElement(id: "healthBar", label: "Health"),
        EditableElement(id: "ammoCounter", label: "Ammo"),
        EditableElement(id: "killFeed", label: "Kill Feed"),
        EditableElement(id: "scoreHeader", label: "Score")
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.9).ignoresSafeArea()

                ForEach(editableElements) { element in
                    let layout = app.profile.settings.layout(for: element.id)
                    Text(element.label)
                        .font(Theme.caption(10))
                        .foregroundStyle(selected == element.id ? Theme.accent : Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(selected == element.id
                                  ? Theme.accent.opacity(0.25) : Theme.surfaceElevated))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected == element.id ? Theme.accent : Theme.stroke,
                                          lineWidth: 1))
                        .scaleEffect(CGFloat(layout.scale))
                        .opacity(layout.hidden ? 0.35 : Double(layout.opacity))
                        .position(x: geometry.size.width * CGFloat(layout.x),
                                  y: geometry.size.height * CGFloat(layout.y))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    selected = id
                                    var updated = layout
                                    updated.x = Float(min(max(value.location.x / geometry.size.width, 0.04), 0.96))
                                    updated.y = Float(min(max(value.location.y / geometry.size.height, 0.05), 0.95))
                                    app.updateSettings { $0.updateLayout(updated) }
                                }
                        )
                        .onTapGesture { selected = element.id }
                }

                VStack {
                    HStack {
                        Button("Done") { app.goBack() }
                            .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                        Button("Reset Layout") {
                            app.updateSettings { $0.resetHUDLayout() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer()
                    if let selected, let layout = app.profile.settings.hudLayout
                        .first(where: { $0.id == selected }) {
                        controlPanel(for: layout)
                    } else {
                        Text("Drag an element to move it. Tap to resize or hide.")
                            .font(Theme.caption(11))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.bottom, 12)
                    }
                }
                .padding(16)
            }
        }
    }

    private func controlPanel(for layout: HUDElementLayout) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Size").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                Slider(value: Binding(
                    get: { layout.scale },
                    set: { newValue in
                        var updated = layout
                        updated.scale = newValue
                        app.updateSettings { $0.updateLayout(updated) }
                    }), in: 0.6...1.6)
                    .tint(Theme.accent)
            }
            HStack {
                Text("Opacity").font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                Slider(value: Binding(
                    get: { layout.opacity },
                    set: { newValue in
                        var updated = layout
                        updated.opacity = newValue
                        app.updateSettings { $0.updateLayout(updated) }
                    }), in: 0.2...1)
                    .tint(Theme.accent)
                Toggle("Hidden", isOn: Binding(
                    get: { layout.hidden },
                    set: { newValue in
                        var updated = layout
                        updated.hidden = newValue
                        app.updateSettings { $0.updateLayout(updated) }
                    }))
                    .font(Theme.caption(11))
                    .tint(Theme.accent)
                    .fixedSize()
            }
        }
        .padding(12)
        .panel(elevated: true)
    }
}
