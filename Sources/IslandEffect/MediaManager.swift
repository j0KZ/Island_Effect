import AppKit
import Combine

struct NowPlaying: Equatable {
    var app: MediaApp = .none
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false
    var duration: Double = 0
    var elapsed: Double = 0
    var trackKey: String = ""
    var artworkURL: String? = nil

    var isActive: Bool { app != .none && !title.isEmpty }
    static let empty = NowPlaying()

    static func == (l: NowPlaying, r: NowPlaying) -> Bool {
        l.app == r.app && l.title == r.title && l.artist == r.artist && l.album == r.album
            && l.isPlaying == r.isPlaying && abs(l.duration - r.duration) < 0.5
            && abs(l.elapsed - r.elapsed) < 0.4 && l.trackKey == r.trackKey
    }
}

enum MediaApp: String, Equatable {
    case none, music, spotify

    var bundleID: String? {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .none: return nil
        }
    }

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .none: return "—"
        }
    }
}

/// Lee y controla la reproducción de Apple Music y Spotify vía AppleScript.
///
/// Nota: macOS 15.4+ bloqueó el framework privado MediaRemote para apps sin
/// entitlements de Apple, así que no hay forma pública de leer el "now playing"
/// global (Safari, Chrome, etc.). Music y Spotify sí exponen scripting.
final class MediaManager: ObservableObject {
    static let shared = MediaManager()

    @Published private(set) var info = NowPlaying.empty
    @Published private(set) var artwork: NSImage?
    /// true si macOS negó el permiso de Automatización para el reproductor.
    @Published private(set) var automationDenied = false
    /// Se dispara cuando cambia la canción o el estado play/pausa.
    var onTrackChange: ((NowPlaying) -> Void)?

    private let queue = DispatchQueue(label: "cafe.island.media", qos: .utility)
    private var timer: Timer?
    private var currentInterval: TimeInterval = 0
    private var busy = false
    private var denied = Set<String>()
    private var lastArtworkKey = ""
    private var lastSampledAt = Date()
    private var lastAnnouncedKey = ""
    private var lastAnnouncedPlaying = false
    private var artworkTask: URLSessionDataTask?

    private init() {}

    func start() {
        // Music y Spotify publican una notificación distribuida en cada cambio
        // de pista o de estado, con los metadatos incluidos. Escucharlas evita
        // lanzar un osascript por segundo: en reposo el coste baja a cero.
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                           object: nil, queue: .main) { [weak self] note in
            self?.handleNotification(note, app: .spotify)
        }
        center.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"),
                           object: nil, queue: .main) { [weak self] note in
            self?.handleNotification(note, app: .music)
        }
        // Si el reproductor se cierra, limpiamos sin esperar al sondeo lento.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self.info.app.bundleID else { return }
            self.apply(.empty)
        }

        // Una sola consulta inicial para enterarnos de lo que ya estaba sonando.
        poll()
        schedule(interval: idleInterval)
    }

    /// Solo hace falta sondear la posición cuando la isla está abierta (barra de
    /// progreso). El resto del tiempo basta una red de seguridad muy espaciada.
    private var needsProgress = false
    func setNeedsProgress(_ needed: Bool) {
        guard needsProgress != needed else { return }
        needsProgress = needed
        schedule(interval: needed ? 1.0 : idleInterval)
        if needed { poll() }
    }

    /// Si el reproductor publica notificaciones, sondear es casi innecesario.
    /// Mientras no hayamos visto ninguna, mantenemos un sondeo corto para no
    /// perdernos los cambios de canción (algunas versiones no las publican).
    private var sawNotification = false
    private var idleInterval: TimeInterval {
        // Sin aviso de canción no hay para qué enterarse rápido de nada.
        guard Prefs.shared.liveMusic else { return 60 }
        if sawNotification { return info.isPlaying ? 30 : 60 }
        return info.isPlaying ? 3 : 8
    }

    private func handleNotification(_ note: Notification, app: MediaApp) {
        guard let userInfo = note.userInfo else { return }
        let state = (userInfo["Player State"] as? String) ?? ""

        // Si suena otra app, no dejamos que la que está en pausa se imponga.
        if info.isActive, info.app != app, info.isPlaying, state != "Playing" { return }

        guard state != "Stopped" else {
            if info.app == app { apply(.empty) }
            return
        }

        var np = NowPlaying()
        np.app = app
        np.isPlaying = state == "Playing"
        np.title = userInfo["Name"] as? String ?? ""
        np.artist = userInfo["Artist"] as? String ?? ""
        np.album = userInfo["Album"] as? String ?? ""
        switch app {
        case .spotify:
            np.duration = (userInfo["Duration"] as? Double ?? 0) / 1000
            np.elapsed = userInfo["Playback Position"] as? Double ?? 0
            np.trackKey = userInfo["Track ID"] as? String ?? (np.title + np.artist)
        case .music:
            np.duration = (userInfo["Total Time"] as? Double ?? 0) / 1000
            // playerInfo no trae la posición; si es la misma pista, conservamos
            // la estimación que ya teníamos.
            let key = String(describing: userInfo["PersistentID"] ?? (np.title + np.artist))
            np.trackKey = key
            np.elapsed = key == info.trackKey ? estimatedElapsed : 0
        case .none:
            return
        }
        guard !np.title.isEmpty else { return }
        if !sawNotification {
            sawNotification = true
            IslandDebug.log("el reproductor publica notificaciones: se deja de sondear")
        }
        IslandDebug.log("notificación de \(app.rawValue): \(np.title) (\(state))")
        apply(np)
        // Un único osascript para la carátula y la posición exacta.
        if needsProgress { poll() }
    }

    /// Sondea cada segundo mientras suena algo y cada 3 s cuando no, para no gastar
    /// batería lanzando osascript sin necesidad.
    private func schedule(interval: TimeInterval) {
        guard currentInterval != interval else { return }
        guard interval > 0 else { timer?.invalidate(); timer = nil; currentInterval = 0; return }
        currentInterval = interval
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = interval * 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Posición estimada entre sondeos, para que la barra de progreso avance suave.
    var estimatedElapsed: Double {
        guard info.isPlaying else { return info.elapsed }
        let delta = Date().timeIntervalSince(lastSampledAt)
        return min(info.duration, info.elapsed + delta)
    }

    private func runningApps() -> [MediaApp] {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var apps: [MediaApp] = []
        if ids.contains("com.spotify.client") { apps.append(.spotify) }
        if ids.contains("com.apple.Music") { apps.append(.music) }
        return apps
    }

    private func poll() {
        // Si una consulta sigue en curso (por ejemplo, esperando el diálogo de
        // permisos), no encolamos otra.
        guard !busy else { return }
        let candidates = runningApps().filter { !denied.contains($0.rawValue) }
        guard !candidates.isEmpty else {
            if info.isActive { apply(.empty) }
            return
        }
        busy = true
        queue.async { [weak self] in
            guard let self else { return }
            var best: NowPlaying?
            for app in candidates {
                let deniedBefore = self.automationDenied
                if let np = self.query(app) {
                    if np.isPlaying { best = np; break }
                    if best == nil { best = np }
                } else if !deniedBefore, self.automationDenied {
                    self.denied.insert(app.rawValue)
                    IslandDebug.log("permiso de automatización denegado para \(app.rawValue)")
                }
            }
            let result = best ?? .empty
            DispatchQueue.main.async {
                self.busy = false
                self.apply(result)
            }
        }
    }

    private func apply(_ np: NowPlaying) {
        if np.isActive, np.trackKey != info.trackKey {
            IslandDebug.log("now playing: \(np.app.rawValue) · \(np.title) — \(np.artist) (playing: \(np.isPlaying))")
        }
        let sameTrack = np.trackKey == info.trackKey && np.app == info.app
        lastSampledAt = Date()
        info = np
        if !sameTrack {
            artwork = nil
            fetchArtwork(for: np)
        }
        let key = np.app.rawValue + "|" + np.trackKey
        if np.isActive, key != lastAnnouncedKey || np.isPlaying != lastAnnouncedPlaying {
            lastAnnouncedKey = key
            lastAnnouncedPlaying = np.isPlaying
            onTrackChange?(np)
        }
        if !np.isActive { lastAnnouncedKey = "" }
        // Después de actualizar `info`, no antes: el ritmo depende de si suena.
        schedule(interval: needsProgress ? 1.0 : idleInterval)
    }

    // MARK: - AppleScript

    @discardableResult
    private func runScript(_ source: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-"]
        let input = Pipe(), output = Pipe(), errPipe = Pipe()
        task.standardInput = input
        task.standardOutput = output
        task.standardError = errPipe
        do { try task.run() } catch { return nil }
        input.fileHandleForWriting.write(Data(source.utf8))
        input.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            IslandDebug.log("osascript falló (\(task.terminationStatus)): \(message)")
            if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") {
                DispatchQueue.main.async { self.automationDenied = true }
            }
            return nil
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func query(_ app: MediaApp) -> NowPlaying? {
        let script: String
        switch app {
        case .spotify:
            script = """
            tell application id "com.spotify.client"
                set playerState to player state as text
                if playerState is "stopped" then return ""
                set theTrack to current track
                set line1 to "spotify" & tab & playerState & tab & (name of theTrack) & tab & (artist of theTrack) & tab & (album of theTrack)
                set line1 to line1 & tab & ((duration of theTrack) / 1000) & tab & (player position) & tab & (id of theTrack) & tab & (artwork url of theTrack)
                return line1
            end tell
            """
        case .music:
            script = """
            tell application id "com.apple.Music"
                set playerState to player state as text
                if playerState is "stopped" then return ""
                try
                    set theTrack to current track
                on error
                    return ""
                end try
                set line1 to "music" & tab & playerState & tab & (name of theTrack) & tab & (artist of theTrack) & tab & (album of theTrack)
                set line1 to line1 & tab & (duration of theTrack) & tab & (player position) & tab & (persistent ID of theTrack) & tab & ""
                return line1
            end tell
            """
        case .none:
            return nil
        }
        guard let raw = runScript(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "\t")
        guard parts.count >= 8 else { return nil }
        var np = NowPlaying()
        np.app = app
        np.isPlaying = parts[1].lowercased() == "playing"
        np.title = parts[2]
        np.artist = parts[3]
        np.album = parts[4]
        np.duration = Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        np.elapsed = Double(parts[6].replacingOccurrences(of: ",", with: ".")) ?? 0
        np.trackKey = parts[7].isEmpty ? (np.title + np.artist) : parts[7]
        if parts.count >= 9, !parts[8].isEmpty { np.artworkURL = parts[8] }
        return np
    }

    // MARK: - Carátula

    private func fetchArtwork(for np: NowPlaying) {
        guard np.isActive else { return }
        let key = np.app.rawValue + np.trackKey
        lastArtworkKey = key
        switch np.app {
        case .spotify:
            guard let urlString = np.artworkURL, let url = URL(string: urlString) else { return }
            artworkTask?.cancel()
            artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard self.lastArtworkKey == key else { return }
                    self.artwork = image
                }
            }
            artworkTask?.resume()
        case .music:
            queue.async { [weak self] in
                guard let self else { return }
                let path = NSTemporaryDirectory() + "island-artwork.png"
                let script = """
                set imageData to missing value
                tell application id "com.apple.Music"
                    try
                        set theTrack to current track
                        if (count of artworks of theTrack) is 0 then return ""
                        set imageData to raw data of artwork 1 of theTrack
                    on error
                        return ""
                    end try
                end tell
                if imageData is missing value then return ""
                try
                    set fileRef to open for access POSIX file "\(path)" with write permission
                    set eof fileRef to 0
                    write imageData to fileRef
                    close access fileRef
                on error
                    try
                        close access POSIX file "\(path)"
                    end try
                    return ""
                end try
                return "ok"
                """
                guard self.runScript(script) == "ok", let image = NSImage(contentsOfFile: path) else { return }
                DispatchQueue.main.async {
                    guard self.lastArtworkKey == key else { return }
                    self.artwork = image
                }
            }
        case .none:
            break
        }
    }

    // MARK: - Controles

    private func control(_ command: String) {
        guard let bundle = info.app.bundleID else { return }
        queue.async { [weak self] in
            self?.runScript("tell application id \"\(bundle)\" to \(command)")
            DispatchQueue.main.async { self?.poll() }
        }
    }

    func playPause() { control("playpause") }
    func next() { control("next track") }
    func previous() {
        // En Music, "previous track" al inicio de la canción vuelve a la anterior.
        control("previous track")
    }

    func seek(to seconds: Double) {
        guard let bundle = info.app.bundleID else { return }
        let target = max(0, min(info.duration, seconds))
        info.elapsed = target
        lastSampledAt = Date()
        queue.async { [weak self] in
            self?.runScript("tell application id \"\(bundle)\" to set player position to \(target)")
        }
    }

    /// Vuelve a intentar tras conceder permisos en Ajustes del Sistema.
    func retryAfterPermissionChange() {
        denied.removeAll()
        automationDenied = false
        poll()
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func activateApp() {
        guard let bundle = info.app.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
