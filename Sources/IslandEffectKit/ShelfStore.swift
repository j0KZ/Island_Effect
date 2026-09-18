import AppKit
import Combine
import SwiftUI

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    /// Cuándo se va sola. `nil` es lo que sueltas tú a mano: se queda hasta que
    /// la saques. Las capturas llegan con fecha de caducidad.
    var expiresAt: Date?
    var isTemporary: Bool { expiresAt != nil }

    var name: String { url.lastPathComponent }
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    var sizeLabel: String {
        if isDirectory { return "Carpeta" }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    init(url: URL, expiresAt: Date? = nil) {
        self.id = UUID()
        self.url = url.standardizedFileURL
        self.expiresAt = expiresAt
    }
}

/// Repisa de archivos: arrastra archivos al notch y quedan disponibles para volver a arrastrarlos.
///
/// Guarda dos cosas distintas con la misma pinta. Lo que sueltas tú es un
/// **cajón**: se queda hasta que lo saques, y sobrevive a cerrar la app. Las
/// capturas de pantalla son una **bandeja de salida**: entran solas, las
/// arrastras a donde iban y se borran. Al reiniciar no vuelven, porque una
/// captura de ayer ya no es algo que estés a punto de usar.
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    private let key = "shelfBookmarks"
    private let defaults: UserDefaults

    @Published private(set) var items: [ShelfItem] = []

    private var reaper: Timer?

    /// Dónde se guarda la repisa. Se recibe para que las pruebas usen un dominio
    /// aparte y no toquen la repisa de verdad.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    deinit { reaper?.invalidate() }

    // MARK: - Decisiones (puras, y por eso comprobables)

    /// Lo que sigue vivo a esta hora. Una captura caducada desaparece aunque la
    /// isla lleve horas cerrada y nadie haya mirado el reloj.
    nonisolated static func alive(_ items: [ShelfItem], now: Date) -> [ShelfItem] {
        items.filter { item in
            guard let expires = item.expiresAt else { return true }
            return expires > now
        }
    }

    /// Qué llega al disco: solo el cajón. Persistir una captura temporal sería
    /// contradecir para qué existe.
    nonisolated static func persistable(_ items: [ShelfItem]) -> [ShelfItem] {
        items.filter { !$0.isTemporary }
    }

    /// Cuánto le queda, para la cuenta atrás de la miniatura. `nil` si no caduca.
    nonisolated static func remaining(_ item: ShelfItem, now: Date) -> TimeInterval? {
        guard let expires = item.expiresAt else { return nil }
        return max(0, expires.timeIntervalSince(now))
    }

    // MARK: - Entradas

    func add(urls: [URL]) {
        var added = false
        for url in urls {
            let std = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: std.path) else { continue }
            // Si la captura ya estaba de paso y la vuelves a soltar a mano, deja
            // de ser temporal: la soltaste tú, ahora es del cajón.
            if let i = items.firstIndex(where: { $0.url == std }) {
                guard items[i].isTemporary else { continue }
                items[i].expiresAt = nil
                added = true
                continue
            }
            items.insert(ShelfItem(url: std), at: 0)
            added = true
        }
        if added { save() }
    }

    /// Una captura recién hecha. Entra arriba y con la cuenta atrás corriendo.
    func addCapture(url: URL, ttl: TimeInterval, now: Date = Date()) {
        let std = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: std.path) else { return }
        guard !items.contains(where: { $0.url == std }) else { return }
        items.insert(ShelfItem(url: std, expiresAt: now.addingTimeInterval(ttl)), at: 0)
        startReaping()
    }

    /// Ya la usaste: la arrastraste fuera, la abriste o copiaste su ruta. Se va
    /// enseguida, pero no al instante, porque verla desaparecer de golpe hace
    /// dudar de si el arrastre llegó a alguna parte.
    ///
    /// Si el arrastre se cancela a medio camino la miniatura se va igual. Es a
    /// propósito: el archivo sigue en su carpeta y la repisa no era dónde se
    /// guardaba, solo dónde estaba a mano.
    func markUsed(_ item: ShelfItem, grace: TimeInterval = 1.5, now: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == item.id }), items[i].isTemporary else { return }
        let soon = now.addingTimeInterval(grace)
        guard let current = items[i].expiresAt, current > soon else { return }
        items[i].expiresAt = soon
        startReaping()
    }

    // MARK: - Salidas

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func copyPath(_ item: ShelfItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.url.path, forType: .string)
    }

    func copyFiles() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
    }

    // MARK: - Caducidad

    /// El barrido solo corre mientras haya algo con cuenta atrás: sin capturas
    /// de paso, la app no despierta cada segundo para no hacer nada.
    private func startReaping() {
        guard reaper == nil else { return }
        reaper = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.purgeExpired()
        }
    }

    func purgeExpired(now: Date = Date()) {
        let vivos = Self.alive(items, now: now)
        if vivos.count != items.count {
            withAnimation(.islandFast) { items = vivos }
        }
        if !items.contains(where: { $0.isTemporary }) {
            reaper?.invalidate()
            reaper = nil
        }
    }

    // MARK: - Persistencia

    private func save() {
        let paths = Self.persistable(items).map { $0.url.path }
        defaults.set(paths, forKey: key)
    }

    private func load() {
        guard let paths = defaults.stringArray(forKey: key) else { return }
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { ShelfItem(url: URL(fileURLWithPath: $0)) }
    }
}

/// Sacar la ruta de lo que entrega un arrastre.
///
/// Existe porque la forma corta no servía. `NSItemProvider.loadObject(ofClass:
/// URL.self)` devolvía `nil` con archivos arrastrados desde el Finder: el
/// arrastre no lleva un objeto `URL`, lleva los **bytes** del tipo
/// `public.file-url`. El archivo llegaba, se leían cero rutas y no pasaba nada,
/// sin ningún error a la vista.
///
/// Los cuatro formatos son reales: `Data` es lo que manda el Finder, `URL` lo
/// que mandan algunas apps de Cocoa, y el texto aparece cuando el origen
/// escribió la ruta en vez de la URL.
enum DroppedFile {

    nonisolated static func url(from item: Any?) -> URL? {
        switch item {
        case let url as URL:
            return usable(url)
        case let data as Data:
            // Primero como URL codificada; si no, como texto, que es lo que
            // mandan los editores y algunos gestores de archivos.
            if let url = URL(dataRepresentation: data, relativeTo: nil), let ok = usable(url) { return ok }
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return url(fromText: text)
        case let text as String:
            return url(fromText: text)
        default:
            return nil
        }
    }

    /// Una ruta escrita a mano puede venir como `file:///…` o como `/Users/…`,
    /// y con espacios sobrantes si salió de un campo de texto.
    nonisolated static func url(fromText raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("file://") {
            guard let url = URL(string: text) else { return nil }
            return usable(url)
        }
        guard text.hasPrefix("/") || text.hasPrefix("~") else { return nil }
        return usable(URL(fileURLWithPath: (text as NSString).expandingTildeInPath))
    }

    /// Solo archivos locales. Una URL de web arrastrada desde el navegador no es
    /// algo que la repisa pueda guardar, y meterla dejaría una tarjeta muerta.
    private nonisolated static func usable(_ url: URL) -> URL? {
        guard url.isFileURL, !url.path.isEmpty else { return nil }
        return url.standardizedFileURL
    }
}
