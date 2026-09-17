import Foundation
import Testing
@testable import IslandEffectKit

/// Pruebas de cómo se interpreta lo que reportan Música y Spotify.
///
/// Se ejercen las funciones de lectura, nunca `MediaManager.shared`: el singleton
/// lanza `osascript` contra los reproductores de verdad.
struct MediaManagerTests {

    // MARK: - Línea del AppleScript

    /// Una línea de Spotify tal como la devuelve el script: app, estado, título,
    /// artista, álbum, duración, posición, id y carátula.
    private static func spotifyLine(state: String = "playing",
                                    duration: String = "215.5",
                                    position: String = "42.25") -> String {
        ["spotify", state, "Canción", "Artista", "Álbum", duration, position,
         "spotify:track:123", "https://i.scdn.co/image/abc"].joined(separator: "\t")
    }

    @Test("Se leen todos los campos de la línea")
    func parseSpotifyLine() throws {
        let np = try #require(MediaManager.parse(Self.spotifyLine(), app: .spotify))
        #expect(np.app == .spotify)
        #expect(np.isPlaying)
        #expect(np.title == "Canción")
        #expect(np.artist == "Artista")
        #expect(np.album == "Álbum")
        #expect(np.duration == 215.5)
        #expect(np.elapsed == 42.25)
        #expect(np.trackKey == "spotify:track:123")
        #expect(np.artworkURL == "https://i.scdn.co/image/abc")
        #expect(np.isActive)
    }

    @Test("Los números con coma decimal se leen igual")
    func parseAcceptsCommaDecimals() throws {
        // En un Mac en español, AppleScript devuelve "215,5" y no "215.5".
        let np = try #require(MediaManager.parse(Self.spotifyLine(duration: "215,5", position: "42,25"),
                                                 app: .spotify))
        #expect(np.duration == 215.5)
        #expect(np.elapsed == 42.25)
    }

    @Test("En pausa se leen los datos igual, pero sin sonar")
    func parsePausedState() throws {
        let np = try #require(MediaManager.parse(Self.spotifyLine(state: "paused"), app: .spotify))
        #expect(!np.isPlaying)
        #expect(np.isActive)
    }

    @Test("Una respuesta vacía o incompleta no se interpreta")
    func parseRejectsGarbage() {
        #expect(MediaManager.parse("", app: .spotify) == nil)
        #expect(MediaManager.parse("spotify\tplaying\tCanción", app: .spotify) == nil)
    }

    @Test("Sin identificador de pista se usa el título con el artista")
    func parseFallsBackToTitleAndArtist() throws {
        let line = ["music", "playing", "Canción", "Artista", "Álbum", "200", "10", "", ""]
            .joined(separator: "\t")
        let np = try #require(MediaManager.parse(line, app: .music))
        #expect(np.trackKey == "CanciónArtista")
        #expect(np.artworkURL == nil)
    }

    // MARK: - Avisos del reproductor

    @Test("El aviso de Spotify trae la duración en milisegundos")
    func spotifyNotification() throws {
        let np = try #require(MediaManager.nowPlaying(fromNotification: [
            "Player State": "Playing", "Name": "Canción", "Artist": "Artista", "Album": "Álbum",
            "Duration": 215_500.0, "Playback Position": 42.0, "Track ID": "spotify:track:123"
        ], app: .spotify))
        #expect(np.isPlaying)
        #expect(np.duration == 215.5)
        #expect(np.elapsed == 42)
        #expect(np.trackKey == "spotify:track:123")
    }

    @Test("El aviso de Música no trae la posición")
    func musicNotification() throws {
        let np = try #require(MediaManager.nowPlaying(fromNotification: [
            "Player State": "Paused", "Name": "Canción", "Artist": "Artista",
            "Total Time": 180_000.0, "PersistentID": 4_815_162_342
        ], app: .music))
        #expect(!np.isPlaying)
        #expect(np.duration == 180)
        #expect(np.elapsed == 0)
        #expect(np.trackKey == "4815162342")
    }

    @Test("Un aviso sin metadatos deja el recorte vacío, no activo")
    func emptyNotification() throws {
        let np = try #require(MediaManager.nowPlaying(fromNotification: ["Player State": "Playing"],
                                                      app: .spotify))
        #expect(np.title.isEmpty)
        #expect(!np.isActive)
    }

    // MARK: - Comparación de pistas

    @Test("Un salto de medio segundo en la posición se considera la misma pista")
    func nowPlayingEqualityTolerance() {
        var a = NowPlaying()
        a.app = .spotify; a.title = "Canción"; a.trackKey = "k"; a.elapsed = 10
        var b = a
        b.elapsed = 10.2
        #expect(a == b)          // el sondeo no llega clavado al segundo
        b.elapsed = 11
        #expect(a != b)          // esto ya es un salto de verdad
    }

    @Test("Sin título no hay nada sonando")
    func isActiveNeedsTitle() {
        var np = NowPlaying()
        np.app = .music
        #expect(!np.isActive)
        np.title = "Canción"
        #expect(np.isActive)
    }

    // MARK: - Reloj

    @Test("El tiempo se muestra como en el reproductor")
    func clockFormat() {
        #expect(TimeFormat.clock(0) == "0:00")
        #expect(TimeFormat.clock(65) == "1:05")
        #expect(TimeFormat.clock(3725) == "1:02:05")
        #expect(TimeFormat.clock(-5) == "0:00")       // una posición negativa no existe
        #expect(TimeFormat.clock(59.6) == "1:00")     // se redondea al segundo
    }

    // MARK: - Números que llegan del sistema

    @Test("Un número sin sentido no se cuela como duración")
    func nonFiniteNumbersAreRejected() {
        // `Double("inf")` sí parsea, y más adelante ese valor se convierte a
        // entero para pintar el reloj: eso aborta el proceso.
        #expect(MediaManager.seconds("inf") == 0)
        #expect(MediaManager.seconds("nan") == 0)
        #expect(MediaManager.seconds("hola") == 0)
        #expect(MediaManager.seconds("215,5") == 215.5)
    }

    @Test("El reloj aguanta una duración imposible")
    func clockSurvivesGarbage() {
        #expect(TimeFormat.clock(Double.infinity) == "0:00")
        #expect(TimeFormat.clock(Double.nan) == "0:00")
    }

    // MARK: - Estado del reproductor

    @Test("El estado se entiende en cualquier capitalización")
    func stateIsCaseInsensitive() {
        #expect(MediaManager.isPlayingState("Playing"))
        #expect(MediaManager.isPlayingState("playing"))
        #expect(!MediaManager.isPlayingState("paused"))
        #expect(!MediaManager.isPlayingState(nil))
        #expect(MediaManager.isStoppedState("Stopped"))
        #expect(MediaManager.isStoppedState("stopped"))
        #expect(!MediaManager.isStoppedState("paused"))
    }

    // MARK: - Ritmo de sondeo

    @Test("Con los avisos del reproductor funcionando se sondea poco")
    func idleIntervalWithNotifications() {
        #expect(MediaManager.idleInterval(liveMusic: true, sawNotification: true, isPlaying: true) == 30)
        #expect(MediaManager.idleInterval(liveMusic: true, sawNotification: true, isPlaying: false) == 60)
    }

    @Test("Sin avisos hay que preguntar más seguido")
    func idleIntervalWithoutNotifications() {
        // Cada sondeo lanza un osascript: la diferencia entre 3 s y 30 s es la
        // diferencia entre gastar batería y no gastarla.
        #expect(MediaManager.idleInterval(liveMusic: true, sawNotification: false, isPlaying: true) == 3)
        #expect(MediaManager.idleInterval(liveMusic: true, sawNotification: false, isPlaying: false) == 8)
    }

    @Test("Con los avisos de música apagados casi no se pregunta")
    func idleIntervalWhenDisabled() {
        #expect(MediaManager.idleInterval(liveMusic: false, sawNotification: false, isPlaying: true) == 60)
    }

    // MARK: - Permiso de automatización

    @Test("Se reconoce la negativa de permiso")
    func automationDenied() {
        // Si dejara de reconocerse, la app se quedaría en "nada sonando" para
        // siempre y nunca ofrecería el panel de permisos.
        #expect(MediaManager.isAutomationDenied(stderr: "execution error: No autorizado. (-1743)"))
        #expect(MediaManager.isAutomationDenied(stderr: "Not authorized to send Apple events"))
        #expect(MediaManager.isAutomationDenied(stderr: "NOT AUTHORIZED"))
    }

    @Test("Otros errores no se confunden con falta de permiso")
    func otherErrorsAreNotDenial() {
        #expect(!MediaManager.isAutomationDenied(stderr: "execution error: Spotify got an error (-1728)"))
        #expect(!MediaManager.isAutomationDenied(stderr: ""))
    }

    // MARK: - Cuándo sale la píldora

    private static func playing(_ title: String, key: String, playing: Bool = true) -> NowPlaying {
        var np = NowPlaying()
        np.app = .spotify
        np.title = title
        np.trackKey = key
        np.isPlaying = playing
        return np
    }

    @Test("Cada canción nueva se anuncia una sola vez")
    func announcesNewTracksOnce() {
        // `shouldAnnounce` muta la compuerta, así que el resultado se guarda
        // antes de comprobarlo: dentro de #expect no se puede mutar.
        var gate = AnnouncementGate()
        let primera = gate.shouldAnnounce(Self.playing("Una", key: "1"))
        let repetida = gate.shouldAnnounce(Self.playing("Una", key: "1"))   // el sondeo repite lo mismo
        let otra = gate.shouldAnnounce(Self.playing("Otra", key: "2"))
        #expect(primera)
        #expect(!repetida)
        #expect(otra)
    }

    @Test("Pausar y reanudar la misma canción sí se anuncia")
    func announcesPlayPause() {
        var gate = AnnouncementGate()
        _ = gate.shouldAnnounce(Self.playing("Una", key: "1"))
        let pausada = gate.shouldAnnounce(Self.playing("Una", key: "1", playing: false))
        let reanudada = gate.shouldAnnounce(Self.playing("Una", key: "1", playing: true))
        #expect(pausada)
        #expect(reanudada)
    }

    @Test("Cuando no suena nada no hay nada que anunciar")
    func silenceIsNotAnnounced() {
        var gate = AnnouncementGate()
        let silencio = gate.shouldAnnounce(NowPlaying())
        #expect(!silencio)
    }

    @Test("Si se cierra el reproductor y se vuelve a la misma canción, se anuncia otra vez")
    func announcesAgainAfterSilence() {
        var gate = AnnouncementGate()
        _ = gate.shouldAnnounce(Self.playing("Una", key: "1"))
        _ = gate.shouldAnnounce(NowPlaying())                        // se cerró el reproductor
        let devuelta = gate.shouldAnnounce(Self.playing("Una", key: "1"))
        #expect(devuelta)
    }
}
