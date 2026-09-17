import AppKit
import Testing
@testable import IslandEffectKit

/// Pruebas de la lógica de tamaños y de apertura de la isla.
///
/// `Prefs` y `MediaManager` son singletons que leen el entorno real, así que
/// cada modelo se crea con `makeViewModel()`, que fija las preferencias que
/// intervienen en los cálculos y desactiva lo que tocaría el sistema
/// (háptica y consultas por AppleScript a los reproductores).
/// Se ejecutan en serie porque `Prefs.shared` es compartido.
@Suite(.serialized)
@MainActor
struct NotchViewModelTests {

    // MARK: - Ayudantes

    static let notch = CGSize(width: 185, height: 32)

    private static func makeViewModel(hasNotch: Bool = true) -> NotchViewModel {
        let prefs = Prefs.shared
        prefs.expandedWidth = 620
        prefs.expandedHeight = 200
        prefs.extraClosedWidth = 0
        // Nada de hardware ni de procesos externos durante las pruebas.
        prefs.haptics = false
        prefs.useAppleMusic = false
        prefs.useSpotify = false

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let metrics = ScreenMetrics(screen: screen, hasNotch: hasNotch, notchSize: notch)
        return NotchViewModel(metrics: metrics)
    }

    /// Ancho de la columna del notch en reposo, tal como lo define el modelo.
    private static var restingWidth: CGFloat {
        notch.width + 2 * (NotchViewModel.topRadius + 1)
    }

    // MARK: - Columna del notch

    @Test("En reposo la columna se dibuja más ancha que el recorte")
    func drawnSizeAtRest() {
        let vm = Self.makeViewModel()
        #expect(vm.notchDrawnSize.width == Self.restingWidth)
        #expect(vm.notchDrawnSize.width > vm.notchSize.width)
        #expect(vm.notchDrawnSize.height == Self.notch.height)
    }

    @Test("El ancho extra de las preferencias se suma a la columna")
    func drawnSizeUsesExtraWidth() {
        let vm = Self.makeViewModel()
        vm.prefs.extraClosedWidth = 24
        #expect(vm.notchDrawnSize.width == Self.restingWidth + 24)
    }

    @Test("El hover engorda la columna 4 puntos, pero solo en reposo")
    func hoverBump() {
        let vm = Self.makeViewModel()
        vm.isHovering = true
        #expect(vm.notchDrawnSize.height == Self.notch.height + 4)

        // Abierta no hay engorde: la columna ya forma parte del panel.
        vm.open()
        #expect(vm.notchDrawnSize.height == Self.notch.height)

        // Con una live activity tampoco, porque la píldora ocupa ese lugar.
        vm.close()
        vm.show(.battery(percent: 80, plugged: true, charging: true))
        #expect(vm.notchDrawnSize.height == Self.notch.height)
    }

    @Test("Sin notch físico la columna es un asa de 10 puntos")
    func drawnSizeWithoutNotch() {
        let vm = Self.makeViewModel(hasNotch: false)
        #expect(vm.notchDrawnSize.height == 10)
    }

    // MARK: - Panel

    @Test("El panel solo existe si la isla está abierta o hay actividad")
    func boardSize() {
        let vm = Self.makeViewModel()
        #expect(vm.boardSize == nil)

        vm.show(.music(title: "Song", subtitle: "Artist", playing: true))
        #expect(vm.boardSize?.height == 48)

        vm.open()
        #expect(vm.boardSize == CGSize(width: 620, height: 200))
    }

    @Test("El tamaño total combina la columna y el panel")
    func currentSize() {
        let vm = Self.makeViewModel()
        #expect(vm.currentSize == CGSize(width: Self.restingWidth, height: Self.notch.height))

        vm.open()
        // El panel es más ancho que la columna, y las alturas se suman.
        #expect(vm.currentSize == CGSize(width: 620, height: 200 + Self.notch.height))
        #expect(vm.currentSize == vm.openSize)
    }

    // MARK: - Píldora de live activity

    @Test("La píldora nunca baja del mínimo ni pasa del máximo")
    func activitySizeIsClamped() {
        let corta = NotchViewModel.activitySize(for: .music(title: "A", subtitle: "B", playing: true))
        #expect(corta.width == 264)

        let larga = NotchViewModel.activitySize(
            for: .music(title: String(repeating: "Canción larguísima ", count: 20),
                        subtitle: "Artista", playing: true))
        #expect(larga.width == 460)
    }

    @Test("Un título largo ensancha la píldora")
    func activitySizeGrowsWithText() {
        let corta = NotchViewModel.activitySize(for: .music(title: "A", subtitle: "B", playing: true))
        let media = NotchViewModel.activitySize(
            for: .music(title: "Un título bastante más largo que el anterior",
                        subtitle: "Artista", playing: true))
        #expect(media.width > corta.width)
        #expect(media.width < 460)
    }

    @Test("Música y batería tienen alturas distintas")
    func activityHeights() {
        let musica = NotchViewModel.activitySize(for: .music(title: "Song", subtitle: "Artist", playing: true))
        let bateria = NotchViewModel.activitySize(for: .battery(percent: 80, plugged: false, charging: false))
        #expect(musica.height == 48)
        #expect(bateria.height == 30)
    }

    // MARK: - Apertura y cierre

    @Test("Abrir descarta la live activity que estuviera visible")
    func openHidesActivity() {
        let vm = Self.makeViewModel()
        vm.show(.music(title: "Song", subtitle: "Artist", playing: true))
        #expect(vm.activity != nil)

        vm.open()
        #expect(vm.isOpen)
        #expect(vm.activity == nil)
    }

    @Test("Con la isla abierta no aparecen live activities")
    func activityIgnoredWhileOpen() {
        let vm = Self.makeViewModel()
        vm.open()
        vm.show(.battery(percent: 20, plugged: false, charging: false))
        #expect(vm.activity == nil)
    }

    @Test("Estando fijada, cerrar no hace nada salvo que se fuerce")
    func pinnedStaysOpen() {
        let vm = Self.makeViewModel()
        vm.open()
        vm.isPinned = true

        vm.close()
        #expect(vm.isOpen)

        vm.close(force: true)
        #expect(!vm.isOpen)
        #expect(!vm.isPinned)
    }

    @Test("El clic fija la isla al abrirla y la suelta al cerrarla")
    func toggle() {
        let vm = Self.makeViewModel()
        vm.toggle()
        #expect(vm.isOpen)
        #expect(vm.isPinned)

        vm.toggle()
        #expect(!vm.isOpen)
        #expect(!vm.isPinned)
    }

    @Test("Abrir dos veces seguidas no cambia nada")
    func openIsIdempotent() {
        let vm = Self.makeViewModel()
        vm.open()
        vm.isPinned = true
        vm.open()
        #expect(vm.isOpen)
        #expect(vm.isPinned)
    }
}
