import Foundation
import Testing
@testable import IslandEffectKit

/// Dónde busca la app las capturas de pantalla.
///
/// La carpeta sale de una preferencia de macOS que puede tener cualquier cosa
/// escrita: la cambian a mano con `defaults write`, la cambian apps de limpieza
/// y a veces queda un `file://`. Si esto falla, la bandeja simplemente no se
/// entera de nada y no hay ningún error que lo delate.
struct CaptureFolderTests {

    private static let home = URL(fileURLWithPath: "/Users/quien")
    private static var desktop: URL { home.appendingPathComponent("Desktop") }

    private static func folder(_ location: String?) -> URL {
        ScreenshotWatcher.captureFolder(location: location, home: home)
    }

    @Test("Sin preferencia, las capturas van al Escritorio")
    func noPreference() {
        #expect(Self.folder(nil) == Self.desktop)
        #expect(Self.folder("") == Self.desktop)
        #expect(Self.folder("   ") == Self.desktop)
    }

    @Test("Una carpeta propia se respeta")
    func customFolder() {
        #expect(Self.folder("/Users/quien/Capturas").path == "/Users/quien/Capturas")
    }

    @Test("La virgulilla se expande")
    func tildeExpands() {
        // `defaults write … location ~/Capturas` guarda la virgulilla literal:
        // sin expandirla se vigilaría una carpeta llamada "~".
        #expect(Self.folder("~/Capturas").path.hasSuffix("/Capturas"))
        #expect(!Self.folder("~/Capturas").path.contains("~"))
    }

    @Test("Un file:// también vale")
    func fileURL() {
        #expect(Self.folder("file:///Users/quien/Capturas").path == "/Users/quien/Capturas")
    }

    @Test("Los espacios de más no cuentan")
    func trimsWhitespace() {
        #expect(Self.folder("  /Users/quien/Capturas  ").path == "/Users/quien/Capturas")
    }

    @Test("Una ruta relativa cae en el Escritorio")
    func relativePathFallsBack() {
        // No sabríamos respecto a qué es relativa, y vigilar la carpeta
        // equivocada es peor que vigilar la de siempre.
        #expect(Self.folder("Capturas") == Self.desktop)
        #expect(Self.folder("../otra") == Self.desktop)
    }

    @Test("Una barra final no crea otra carpeta")
    func trailingSlash() {
        #expect(Self.folder("/Users/quien/Capturas/") == Self.folder("/Users/quien/Capturas"))
    }
}

/// Qué archivo cuenta como captura recién hecha.
///
/// La carpeta de fábrica es el Escritorio, donde también aterriza todo lo
/// demás. Colar un archivo cualquiera en la bandeja sería peor que no tenerla.
struct IsCaptureTests {

    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func isCapture(_ name: String, age: TimeInterval) -> Bool {
        ScreenshotWatcher.isCapture(name: name, created: now.addingTimeInterval(-age), now: now)
    }

    @Test("Una captura recién guardada entra")
    func freshScreenshot() {
        #expect(Self.isCapture("Screenshot 2026-09-17 at 3.13.49 PM.png", age: 0.2))
    }

    @Test("El nombre traducido entra igual")
    func localizedNames() {
        // El nombre lo pone macOS en el idioma del sistema, y con
        // `defaults write … name` se cambia entero. Por eso no se mira.
        #expect(Self.isCapture("Captura de pantalla 2026-09-17 a la(s) 15.13.49.png", age: 0.2))
        #expect(Self.isCapture("Bildschirmfoto.png", age: 0.2))
        #expect(Self.isCapture("loquesea.png", age: 0.2))
    }

    @Test("Una grabación de pantalla también")
    func screenRecording() {
        // Sale de la misma tecla (⇧⌘5) y a la misma carpeta.
        #expect(Self.isCapture("Screen Recording.mov", age: 1))
    }

    @Test("Un archivo de siempre en el Escritorio no entra")
    func oldFilesAreIgnored() {
        // Es lo que separa la bandeja de "todo el Escritorio": la carpeta se
        // relee entera con cada cambio, y sin esto la primera captura arrastraría
        // con ella todo lo que llevara años ahí.
        #expect(!Self.isCapture("presupuesto.png", age: 3600))
        #expect(!Self.isCapture("vacaciones.jpg", age: 86_400 * 30))
    }

    @Test("Los tipos que no escribe screencapture se descartan")
    func otherTypes() {
        #expect(!Self.isCapture("informe.docx", age: 0.2))
        #expect(!Self.isCapture("notas.txt", age: 0.2))
        #expect(!Self.isCapture("sin-extension", age: 0.2))
    }

    @Test("Los ocultos y los temporales a medio escribir se descartan")
    func hiddenFiles() {
        // `screencapture` escribe primero un archivo oculto y después lo renombra.
        #expect(!Self.isCapture(".DS_Store", age: 0.2))
        #expect(!Self.isCapture(".sb-a1b2c3-captura.png", age: 0.2))
    }

    @Test("Sin fecha de creación no se arriesga")
    func noCreationDate() {
        #expect(!ScreenshotWatcher.isCapture(name: "algo.png", created: nil, now: Self.now))
    }

    @Test("Un reloj adelantado no descarta la captura")
    func clockSkew() {
        // Copiar desde un disco en red o una restauración pueden dejar una fecha
        // de creación por delante del reloj. Dentro de la ventana, vale igual.
        #expect(Self.isCapture("algo.png", age: -3))
        #expect(!Self.isCapture("algo.png", age: -3600))
    }

    @Test("Justo en el borde de la ventana todavía cuenta")
    func exactlyAtTheWindow() {
        #expect(Self.isCapture("algo.png", age: ScreenshotWatcher.freshness))
        #expect(!Self.isCapture("algo.png", age: ScreenshotWatcher.freshness + 0.001))
    }

    @Test("La extensión no distingue mayúsculas")
    func caseInsensitiveExtension() {
        #expect(Self.isCapture("CAPTURA.PNG", age: 0.2))
    }

    @Test("Con la repisa apagada no se guarda ninguna captura")
    func capturesNeedTheShelf() {
        // La pestaña de la repisa ni aparece: anunciar una captura que no se
        // puede ir a buscar es peor que no anunciarla.
        #expect(!ScreenshotWatcher.wantsCapture(shelfEnabled: false, captureShelf: true))
        #expect(!ScreenshotWatcher.wantsCapture(shelfEnabled: true, captureShelf: false))
        #expect(ScreenshotWatcher.wantsCapture(shelfEnabled: true, captureShelf: true))
    }

    @Test("Solo se miran los archivos que aparecieron")
    func onlyNewNames() {
        let antes: Set<String> = ["a.png", "b.png"]
        let ahora: Set<String> = ["a.png", "c.png"]
        // `c` es nuevo; que `b` ya no esté no interesa, y `a` no se reprocesa:
        // si no, cada cambio en la carpeta reanunciaría todo lo que hay dentro.
        #expect(ScreenshotWatcher.appeared(before: antes, now: ahora) == ["c.png"])
    }
}

/// La bandeja de salida: capturas que entran solas y se van solas.
struct CaptureShelfTests {

    /// Carpeta temporal con archivos de verdad, que se borra sola al terminar.
    private struct Sandbox: ~Copyable {
        let dir: URL

        init() throws {
            dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("captura-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        func file(_ name: String) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try Data("png de mentira".utf8).write(to: url)
            return url
        }

        deinit { try? FileManager.default.removeItem(at: dir) }
    }

    private static func scratchStore() -> ShelfStore {
        let suite = "captura-tests-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return ShelfStore(defaults: UserDefaults(suiteName: suite)!)
    }

    private static let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Caducidad

    @Test("Lo que soltaste tú no caduca nunca")
    func permanentItemsSurvive() {
        let item = ShelfItem(url: URL(fileURLWithPath: "/tmp/mio.txt"))
        #expect(!item.isTemporary)
        #expect(ShelfStore.alive([item], now: Self.now.addingTimeInterval(86_400 * 365)).count == 1)
        #expect(ShelfStore.remaining(item, now: Self.now) == nil)
    }

    @Test("Una captura caducada desaparece")
    func expiredCapturesLeave() {
        let captura = ShelfItem(url: URL(fileURLWithPath: "/tmp/c.png"),
                                expiresAt: Self.now.addingTimeInterval(300))
        #expect(ShelfStore.alive([captura], now: Self.now).count == 1)
        #expect(ShelfStore.alive([captura], now: Self.now.addingTimeInterval(301)).isEmpty)
    }

    @Test("Caduca aunque la isla lleve horas cerrada")
    func expiryDoesNotNeedTheIslandOpen() {
        // El barrido corre con un temporizador, pero el que manda es el reloj:
        // si la máquina durmió, al despertar la captura ya no está.
        let captura = ShelfItem(url: URL(fileURLWithPath: "/tmp/c.png"),
                                expiresAt: Self.now.addingTimeInterval(60))
        #expect(ShelfStore.alive([captura], now: Self.now.addingTimeInterval(86_400)).isEmpty)
    }

    @Test("La cuenta atrás no baja de cero")
    func countdownHasAFloor() {
        // Se dibuja sobre la miniatura durante el segundo que va entre que
        // caduca y que el barrido la retira: un negativo saldría en pantalla.
        let captura = ShelfItem(url: URL(fileURLWithPath: "/tmp/c.png"),
                                expiresAt: Self.now.addingTimeInterval(10))
        #expect(ShelfStore.remaining(captura, now: Self.now) == 10)
        #expect(ShelfStore.remaining(captura, now: Self.now.addingTimeInterval(99)) == 0)
    }

    // MARK: - Qué llega al disco

    @Test("Las capturas no sobreviven al reinicio")
    func capturesAreNotPersisted() {
        // Una captura de ayer no es algo que estés a punto de usar; si vuelve al
        // arrancar, la bandeja se convierte en el Escritorio que venía a evitar.
        let mio = ShelfItem(url: URL(fileURLWithPath: "/tmp/mio.txt"))
        let captura = ShelfItem(url: URL(fileURLWithPath: "/tmp/c.png"),
                                expiresAt: Self.now.addingTimeInterval(300))
        #expect(ShelfStore.persistable([mio, captura]).map(\.url) == [mio.url])
    }

    // MARK: - Entradas

    @Test("Una captura entra arriba y con cuenta atrás")
    func captureGoesOnTop() throws {
        let box = try Sandbox()
        let store = Self.scratchStore()
        store.add(urls: [try box.file("viejo.txt")])
        store.addCapture(url: try box.file("captura.png"), ttl: 300, now: Self.now)

        #expect(store.items.first?.name == "captura.png")
        #expect(store.items.first?.expiresAt == Self.now.addingTimeInterval(300))
        #expect(store.items.last?.isTemporary == false)
    }

    @Test("La misma captura no entra dos veces")
    func noDuplicates() throws {
        let box = try Sandbox()
        let store = Self.scratchStore()
        let url = try box.file("captura.png")
        store.addCapture(url: url, ttl: 300, now: Self.now)
        store.addCapture(url: url, ttl: 300, now: Self.now)
        #expect(store.items.count == 1)
    }

    @Test("Una captura que ya no está en disco no entra")
    func missingFileIsIgnored() throws {
        let box = try Sandbox()
        let store = Self.scratchStore()
        let url = try box.file("captura.png")
        try FileManager.default.removeItem(at: url)
        store.addCapture(url: url, ttl: 300, now: Self.now)
        #expect(store.items.isEmpty)
    }

    // MARK: - Salidas

    @Test("Usar una captura la despide, sin que desaparezca de golpe")
    func usingACaptureShortensIt() throws {
        let box = try Sandbox()
        let store = Self.scratchStore()
        store.addCapture(url: try box.file("captura.png"), ttl: 300, now: Self.now)

        let item = try #require(store.items.first)
        store.markUsed(item, grace: 1.5, now: Self.now)

        // Sigue ahí un momento: verla evaporarse haría dudar de si el arrastre
        // llegó a alguna parte.
        #expect(store.items.count == 1)
        #expect(store.items.first?.expiresAt == Self.now.addingTimeInterval(1.5))
    }

    @Test("Usarla dos veces no la resucita")
    func markUsedNeverExtends() throws {
        let box = try Sandbox()
        let store = Self.scratchStore()
        store.addCapture(url: try box.file("captura.png"), ttl: 1, now: Self.now)

        let item = try #require(store.items.first)
        store.markUsed(item, grace: 60, now: Self.now)
        // Le quedaba 1 segundo: una gracia de 60 la alargaría, y arrastrar algo
        // a punto de irse no es motivo para que se quede un minuto más.
        #expect(store.items.first?.expiresAt == Self.now.addingTimeInterval(1))
    }

    @Test("Usar un archivo del cajón no le pone fecha de caducidad")
    func markUsedIgnoresPermanentItems() throws {
        let box = try Sandbox()
        let store = Self.scratchStore()
        store.add(urls: [try box.file("mio.txt")])

        let item = try #require(store.items.first)
        store.markUsed(item, now: Self.now)
        #expect(store.items.first?.expiresAt == nil)
    }

    @Test("Soltar una captura a mano la asciende al cajón")
    func droppingACapturePromotesIt() throws {
        // Es el "esta me la quedo": la arrastras de vuelta al notch y deja de
        // tener cuenta atrás.
        let box = try Sandbox()
        let store = Self.scratchStore()
        let url = try box.file("captura.png")
        store.addCapture(url: url, ttl: 300, now: Self.now)
        store.add(urls: [url])

        #expect(store.items.count == 1)
        #expect(store.items.first?.isTemporary == false)
    }

    @Test("El barrido se lleva lo caducado y deja lo demás")
    func purgeKeepsTheDrawer() throws {
        let box = try Sandbox()
        let store = Self.scratchStore()
        store.add(urls: [try box.file("mio.txt")])
        store.addCapture(url: try box.file("captura.png"), ttl: 60, now: Self.now)

        store.purgeExpired(now: Self.now.addingTimeInterval(61))
        #expect(store.items.map(\.name) == ["mio.txt"])
    }
}
