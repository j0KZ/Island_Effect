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
        GeometryReader { geo in
            let h = geo.size.height
            // El panel se puede achicar bastante: por debajo de cierto alto la
            // ficha se compacta en vez de reventar el layout.
            let compact = h < 120
            let tiny = h < 88
            // Nunca mayor que el alto disponible: si no, empuja el resto fuera.
            let art = min(h, max(36, geo.size.width * 0.34))
            let playSize: CGFloat = compact ? 30 : 40
            let sideSize: CGFloat = compact ? 24 : 30

            HStack(spacing: compact ? 11 : 16) {
                Button { media.activateApp() } label: {
                    ArtworkView(size: art, corner: max(8, art * 0.13))
                        .shadow(color: .black.opacity(0.55), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .help("Open \(info.app.displayName)")

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.system(size: compact ? 13 : 15, weight: .semibold))
                            .lineLimit(1)
                        Text(info.artist.isEmpty ? info.album : info.artist)
                            .font(.system(size: compact ? 11 : 12))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                        if !compact, !info.album.isEmpty, !info.artist.isEmpty {
                            Text(info.album)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: compact ? 5 : 10)

                    VStack(spacing: 4) {
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
                        .frame(height: 10)

                        if !tiny {
                            HStack {
                                Text(TimeFormat.clock(scrubbing ? scrubValue : displayElapsed))
                                Spacer()
                                if !compact {
                                    Text(info.app.displayName)
                                        .foregroundStyle(.white.opacity(0.3))
                                    Spacer()
                                }
                                Text(TimeFormat.clock(info.duration))
                            }
                            .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45))
                        }
                    }

                    if !tiny {
                    Spacer(minLength: compact ? 5 : 10)

                    HStack(spacing: compact ? 10 : 14) {
                        CircleButton(symbol: "backward.fill", size: sideSize, iconSize: compact ? 10 : 12) { media.previous() }
                        CircleButton(symbol: info.isPlaying ? "pause.fill" : "play.fill",
                                     size: playSize, iconSize: compact ? 12 : 15, filled: true) { media.playPause() }
                        CircleButton(symbol: "forward.fill", size: sideSize, iconSize: compact ? 10 : 12) { media.next() }

                        Spacer(minLength: 8)

                        if true {
                            Image(systemName: volume.muted || volumeValue < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 16)
                                .onTapGesture { volume.setMuted(!volume.muted) }
                            IslandSlider(value: Binding(
                                get: { volumeValue },
                                set: { volumeValue = $0; volume.setVolume(Float($0)) }
                            ), height: 5)
                            .frame(width: compact ? 70 : 96, height: 12)
                        }
                    }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                // Panel muy bajo: el transporte se va al costado.
                if tiny {
                    HStack(spacing: 8) {
                        CircleButton(symbol: "backward.fill", size: 22, iconSize: 9) { media.previous() }
                        CircleButton(symbol: info.isPlaying ? "pause.fill" : "play.fill",
                                     size: 28, iconSize: 11, filled: true) { media.playPause() }
                        CircleButton(symbol: "forward.fill", size: 22, iconSize: 9) { media.next() }
                    }
                }
            }
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
            Text("Automation permission missing")
                .font(.system(size: 13, weight: .medium))
            Text("System Settings › Privacy & Security › Automation\nEnable Music and Spotify for Island Effect.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                Button("Open Settings") { media.openAutomationSettings() }
                    .buttonStyle(PillButtonStyle())
                Button("Retry") { media.retryAfterPermissionChange() }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            EqualizerBars(active: false, tint: .white.opacity(0.35))
                .frame(width: 34, height: 20)
            Text("Nothing playing")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("Open Music or Spotify and it will show up here")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            HStack(spacing: 8) {
                launchButton(name: "Music", bundle: "com.apple.Music")
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
