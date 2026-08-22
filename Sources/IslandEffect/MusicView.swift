import SwiftUI
import AppKit

struct MusicView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var media = MediaManager.shared
    @ObservedObject private var volume = VolumeMonitor.shared

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var displayElapsed: Double = 0
    @State private var volumeValue: Double = 0

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if media.info.isActive {
                player
            } else {
                empty
            }
        }
        .onReceive(ticker) { _ in
            if !scrubbing { displayElapsed = media.estimatedElapsed }
            volumeValue = Double(volume.readVolume())
        }
        .onAppear {
            displayElapsed = media.estimatedElapsed
            volumeValue = Double(volume.readVolume())
        }
    }

    private var info: NowPlaying { media.info }

    private var player: some View {
        HStack(spacing: 14) {
            Button { media.activateApp() } label: {
                ArtworkView(size: 104, corner: 14)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .help("Abrir \(info.app.displayName)")

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(info.artist.isEmpty ? info.album : info.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                VStack(spacing: 3) {
                    IslandSlider(
                        value: Binding(
                            get: { scrubbing ? scrubValue : displayElapsed },
                            set: { scrubValue = $0 }
                        ),
                        range: 0...max(1, info.duration),
                        height: 5,
                        onEditingChanged: { editing in
                            scrubbing = editing
                            if !editing {
                                media.seek(to: scrubValue)
                                displayElapsed = scrubValue
                            }
                        }
                    )
                    .frame(height: 12)

                    HStack {
                        Text(TimeFormat.clock(scrubbing ? scrubValue : displayElapsed))
                        Spacer()
                        Text(TimeFormat.clock(info.duration))
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                }

                HStack(spacing: 12) {
                    CircleButton(symbol: "backward.fill", size: 28, iconSize: 11) { media.previous() }
                    CircleButton(symbol: info.isPlaying ? "pause.fill" : "play.fill",
                                 size: 36, iconSize: 14, filled: true) { media.playPause() }
                    CircleButton(symbol: "forward.fill", size: 28, iconSize: 11) { media.next() }

                    Spacer(minLength: 8)

                    Image(systemName: volume.muted || volumeValue < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .onTapGesture { volume.setMuted(!volume.muted) }
                    IslandSlider(value: Binding(
                        get: { volumeValue },
                        set: { volumeValue = $0; volume.setVolume(Float($0)) }
                    ), height: 5)
                    .frame(width: 90, height: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var empty: some View {
        if media.automationDenied {
            permissionHint
        } else {
            emptyState
        }
    }

    private var permissionHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.orange)
            Text("Falta el permiso de Automatización")
                .font(.system(size: 13, weight: .medium))
            Text("Ajustes del Sistema › Privacidad y seguridad › Automatización\nActiva Música y Spotify para Island Effect.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                Button("Abrir Ajustes") { media.openAutomationSettings() }
                    .buttonStyle(PillButtonStyle())
                Button("Reintentar") { media.retryAfterPermissionChange() }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            EqualizerBars(active: false, tint: .white.opacity(0.35))
                .frame(width: 34, height: 20)
            Text("Nada sonando")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("Abre Música o Spotify y aparecerá acá")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            HStack(spacing: 8) {
                launchButton(name: "Música", bundle: "com.apple.Music")
                launchButton(name: "Spotify", bundle: "com.spotify.client")
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func launchButton(name: String, bundle: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            Button {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } label: {
                HStack(spacing: 5) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().frame(width: 14, height: 14)
                    Text(name).font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
    }
}
