import Foundation
import Testing
@testable import IslandEffectKit

/// Pruebas de la repisa: qué entra, qué se descarta y qué sobrevive al reinicio.
///
/// Cada prueba usa archivos de verdad en una carpeta temporal y un dominio de
/// preferencias propio, así que nunca toca la repisa real.
struct ShelfStoreTests {

    /// Carpeta temporal con archivos de mentira, que se borra sola al terminar.
    private struct Sandbox: ~Copyable {
        let dir: URL

        init() throws {
            dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("shelf-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        @discardableResult
        func file(_ name: String) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try Data("hola".utf8).write(to: url)
            return url
        }

        deinit { try? FileManager.default.removeItem(at: dir) }
    }

    /// Preferencias desechables, para no escribir en las del usuario.
    private static func scratchDefaults() -> UserDefaults {
        let suite = "shelf-tests-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test("Lo último arrastrado queda arriba")
    func addPutsNewestFirst() throws {
        let box = try Sandbox()
        let store = ShelfStore(defaults: Self.scratchDefaults())

        store.add(urls: [try box.file("uno.txt")])
        store.add(urls: [try box.file("dos.txt")])

        #expect(store.items.map(\.name) == ["dos.txt", "uno.txt"])
    }

    @Test("Un archivo que ya está en la repisa no se repite")
    func addIgnoresDuplicates() throws {
        let box = try Sandbox()
        let store = ShelfStore(defaults: Self.scratchDefaults())
        let archivo = try box.file("uno.txt")

        store.add(urls: [archivo, archivo])
        store.add(urls: [archivo])

        #expect(store.items.count == 1)
    }

    @Test("La misma ruta escrita con rodeos cuenta como el mismo archivo")
    func addNormalizesPaths() throws {
        let box = try Sandbox()
        let store = ShelfStore(defaults: Self.scratchDefaults())
        let archivo = try box.file("uno.txt")
        let rodeo = box.dir.appendingPathComponent("sub/../uno.txt")

        store.add(urls: [archivo])
        store.add(urls: [rodeo])

        #expect(store.items.count == 1)
    }

    @Test("Un archivo que ya no existe no entra")
    func addSkipsMissingFiles() throws {
        let box = try Sandbox()
        let store = ShelfStore(defaults: Self.scratchDefaults())

        store.add(urls: [box.dir.appendingPathComponent("fantasma.txt")])

        #expect(store.items.isEmpty)
    }

    @Test("Quitar y vaciar dejan la repisa como corresponde")
    func removeAndClear() throws {
        let box = try Sandbox()
        let store = ShelfStore(defaults: Self.scratchDefaults())
        store.add(urls: [try box.file("uno.txt"), try box.file("dos.txt")])

        store.remove(try #require(store.items.first))
        #expect(store.items.count == 1)

        store.clear()
        #expect(store.items.isEmpty)
    }

    @Test("La repisa sigue ahí al volver a abrir la app")
    func survivesRelaunch() throws {
        let box = try Sandbox()
        let defaults = Self.scratchDefaults()

        let antes = ShelfStore(defaults: defaults)
        antes.add(urls: [try box.file("uno.txt"), try box.file("dos.txt")])

        let despues = ShelfStore(defaults: defaults)
        #expect(despues.items.map(\.name) == ["dos.txt", "uno.txt"])
    }

    @Test("Lo que se borró del disco mientras tanto no reaparece")
    func droppedFilesDoNotComeBack() throws {
        let box = try Sandbox()
        let defaults = Self.scratchDefaults()
        let efimero = try box.file("efimero.txt")

        let antes = ShelfStore(defaults: defaults)
        antes.add(urls: [try box.file("queda.txt"), efimero])
        try FileManager.default.removeItem(at: efimero)

        let despues = ShelfStore(defaults: defaults)
        #expect(despues.items.map(\.name) == ["queda.txt"])
    }
}
