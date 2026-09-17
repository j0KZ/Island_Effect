import AppKit
import Foundation

/// Vigila la carpeta donde macOS deja las capturas de pantalla y avisa de cada
/// una nueva.
///
/// macOS ya muestra su miniatura flotante abajo a la derecha, pero dura cinco
/// segundos, solo enseña la última y desaparece sin dejar rastro. Esto es lo
/// contrario: la captura cae en la repisa, se queda el rato que haga falta y se
/// borra sola cuando ya no la usaste.
///
/// No usa Spotlight. `kMDItemIsScreenCapture` identificaría la captura sin
/// margen de error, pero el índice tarda en enterarse y el sentido de esto es
/// que la miniatura esté ahí *antes* de que vayas a buscarla. Se mira la carpeta
/// directamente y se decide por nombre y fecha.
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    /// Qué extensiones escribe `screencapture`. `mov` es la grabación de
    /// pantalla, que sale de la misma tecla (⇧⌘5) y a la misma carpeta.
    nonisolated static let captureTypes: Set<String> =
        ["png", "jpg", "jpeg", "heic", "tiff", "pdf", "gif", "mov"]

    /// Cuánto puede tardar el archivo en aparecer desde que se creó. Sirve para
    /// no confundir una captura recién hecha con los mil archivos que ya viven
    /// en el Escritorio, que es la carpeta de fábrica.
    nonisolated static let freshness: TimeInterval = 10

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var known: Set<String> = []
    private var folder: URL?

    /// Qué hacer con cada captura nueva. Lo pone `AppDelegate`; las pruebas no
    /// arrancan el vigilante, así que trabajan sobre las funciones puras.
    var onCapture: ((URL) -> Void)?

    // MARK: - Decisiones (puras, y por eso comprobables)

    /// Dónde deja macOS las capturas. La preferencia es la que cambia con
    /// `defaults write com.apple.screencapture location`; sin ella, el
    /// Escritorio.
    ///
    /// El valor viene tal cual lo escribió quien lo configuró: puede traer `~`,
    /// una barra final o un `file://` si lo puso Onyx o similar.
    nonisolated static func captureFolder(location: String?, home: URL) -> URL {
        let desktop = home.appendingPathComponent("Desktop")
        guard var raw = location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return desktop }
        if raw.hasPrefix("file://") {
            guard let url = URL(string: raw) else { return desktop }
            raw = url.path
        }
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return desktop }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    /// ¿Este archivo recién aparecido es una captura?
    ///
    /// Se mira la extensión y la edad, no el nombre: el nombre está traducido
    /// («Screenshot…», «Captura de pantalla…», y otros veinte idiomas) y quien
    /// cambió el prefijo con `defaults write … name` rompería la comparación.
    nonisolated static func isCapture(name: String, created: Date?, now: Date,
                                      window: TimeInterval = freshness) -> Bool {
        // Los archivos ocultos y los `.sb-…` a medio escribir que deja el propio
        // `screencapture` mientras guarda.
        guard !name.hasPrefix(".") else { return false }
        guard captureTypes.contains((name as NSString).pathExtension.lowercased()) else { return false }
        guard let created else { return false }
        let age = now.timeIntervalSince(created)
        return age >= -window && age <= window
    }

    /// Los nombres que no estaban la vez anterior. Se compara por nombre y no
    /// por fecha de la carpeta: renombrar un archivo también toca la carpeta, y
    /// así ese no se cuela como captura nueva.
    nonisolated static func appeared(before: Set<String>, now: Set<String>) -> Set<String> {
        now.subtracting(before)
    }

    // MARK: - Vigilancia

    /// La carpeta se resuelve cada vez que hay motivo para dudar de ella, no una
    /// sola vez al arrancar: cambiarla es un `defaults write` en otro proceso,
    /// que no notifica a nadie. Los motivos son que la carpeta vigilada
    /// desaparezca o se renombre, y volver de suspensión.
    func start(defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.screencapture"),
               home: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        resolve = { Self.captureFolder(location: defaults?.string(forKey: "location"), home: home) }
        watch(resolve())

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rewatchIfMoved()
        }
    }

    private var resolve: () -> URL = { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop") }

    private func rewatchIfMoved() {
        let target = resolve()
        guard target != folder else { return }
        watch(target)
    }

    func stop() {
        source?.cancel()
        source = nil
        folder = nil
    }

    private func watch(_ directory: URL) {
        stop()
        folder = directory
        known = Self.contents(of: directory)

        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            IslandDebug.log("capturas: no se pudo abrir \(directory.path)")
            return
        }
        descriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            // Si la carpeta se fue (la movieron, la renombraron, la cambiaron en
            // Ajustes), el descriptor sigue apuntando a un sitio que ya no existe
            // y no llegaría ninguna captura más.
            guard FileManager.default.fileExists(atPath: self.folder?.path ?? "") else {
                self.rewatchIfMoved()
                return
            }
            self.scan()
        }
        src.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        src.resume()
        source = src
        IslandDebug.log("capturas: vigilando \(directory.path)")
    }

    private func scan() {
        guard let folder else { return }
        let current = Self.contents(of: folder)
        let nuevos = Self.appeared(before: known, now: current)
        known = current
        let now = Date()

        for name in nuevos.sorted() {
            let url = folder.appendingPathComponent(name)
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            guard Self.isCapture(name: name, created: created, now: now) else { continue }
            IslandDebug.log("captura: \(name)")
            onCapture?(url)
        }
    }

    private static func contents(of directory: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names)
    }
}
