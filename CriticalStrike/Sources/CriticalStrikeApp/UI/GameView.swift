import SwiftUI
import SceneKit
import CriticalStrikeCore

/// The in-match screen: the 3D view, the HUD on top of it, and the overlays.
struct GameView: View {
    @EnvironmentObject private var app: AppState
    @State private var showPauseMenu = false
    @State private var showPingWheel = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let session = app.session {
                    GameSceneView(session: session)
                        .ignoresSafeArea()
                        .onAppear { session.setScreenSize(geometry.size) }

                    HUDView(session: session, size: geometry.size)
                        .allowsHitTesting(true)

                    TouchControlsView(session: session, size: geometry.size) {
                        showPingWheel = true
                    }

                    if showPingWheel {
                        PingWheelView(
                            onSelect: { kind in session.sendPing(kind: kind) },
                            onDismiss: { showPingWheel = false })
                    }

                    if session.showScoreboard {
                        ScoreboardOverlay(session: session)
                            .transition(.opacity)
                    }

                    if session.showBuyMenu {
                        BuyMenuView(session: session)
                            .transition(.move(edge: .bottom))
                    }

                    if !session.hud.isAlive {
                        DeathOverlay(hud: session.hud)
                            .allowsHitTesting(false)
                    }

                    if showPauseMenu {
                        PauseMenuView(
                            onResume: { showPauseMenu = false; session.resume() },
                            onSettings: { app.go(to: .settings) },
                            onQuit: { app.leaveMatch() })
                    }

                    // Pause button lives in the top-left corner, away from thumbs.
                    VStack {
                        HStack {
                            Button {
                                showPauseMenu = true
                                session.pause()
                            } label: {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.black.opacity(0.45)))
                            }
                            .padding(.leading, 14)
                            .padding(.top, 10)
                            Spacer()
                        }
                        Spacer()
                    }
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
        }
        .background(Color.black)
        .persistentSystemOverlays(.hidden)
    }
}

/// Thin UIViewRepresentable around SCNView. Everything interesting happens in
/// `GameRenderer`; this exists only to own the view and wire the delegate.
struct GameSceneView: UIViewRepresentable {
    let session: GameSession

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.isUserInteractionEnabled = false   // all input goes through the SwiftUI layer
        view.allowsCameraControl = false
        view.showsStatistics = false
        view.isOpaque = true
        session.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

struct PauseMenuView: View {
    var onResume: () -> Void
    var onSettings: () -> Void
    var onQuit: () -> Void
    @State private var confirmQuit = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("PAUSED")
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.textPrimary)

                Button("Resume", action: onResume)
                    .buttonStyle(PrimaryButtonStyle())

                Button("Settings", action: onSettings)
                    .buttonStyle(SecondaryButtonStyle(wide: true))

                if confirmQuit {
                    VStack(spacing: 8) {
                        Text("Leaving forfeits this match and any rewards.")
                            .font(Theme.caption())
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            Button("Cancel") { confirmQuit = false }
                                .buttonStyle(SecondaryButtonStyle(wide: true))
                            Button("Leave", action: onQuit)
                                .buttonStyle(SecondaryButtonStyle(wide: true))
                                .foregroundStyle(Theme.danger)
                        }
                    }
                } else {
                    Button("Leave Match") { confirmQuit = true }
                        .buttonStyle(SecondaryButtonStyle(wide: true))
                        .foregroundStyle(Theme.danger)
                }
            }
            .frame(maxWidth: 320)
            .padding(24)
            .panel(elevated: true)
        }
    }
}

struct DeathOverlay: View {
    let hud: HUDState

    var body: some View {
        ZStack {
            // Desaturated red vignette rather than a full-screen wash, so the death cam
            // stays readable.
            RadialGradient(colors: [.clear, Color.red.opacity(0.35)],
                           center: .center, startRadius: 120, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("ELIMINATED")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.textPrimary)
                    .hudText()
                if hud.respawnSeconds > 0 {
                    Text("Respawning in \(Int(ceil(hud.respawnSeconds)))")
                        .font(Theme.title(18))
                        .foregroundStyle(Theme.textSecondary)
                        .hudText()
                } else {
                    Text("Waiting for the next round")
                        .font(Theme.body())
                        .foregroundStyle(Theme.textSecondary)
                        .hudText()
                }
            }
        }
    }
}
