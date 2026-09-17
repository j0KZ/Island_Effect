import AppKit
import Testing
@testable import IslandEffectKit

/// Pruebas de la detección del puntero: qué zonas de la pantalla responden y
/// cuánto tiempo hay que quedarse encima para que la isla se abra.
@MainActor
struct NotchControllerTests {

    /// Una pantalla de 1800 × 1130 con el origen en (0, 0), como la del portátil.
    private static let screen = CGRect(x: 0, y: 0, width: 1800, height: 1130)
    private static let notchWidth: CGFloat = 185
    private static let notchHeight: CGFloat = 32

    private static func rects(board: CGSize? = nil, padding: CGFloat = 0) -> [CGRect] {
        NotchController.islandRects(screenFrame: screen, notchWidth: notchWidth,
                                    notchHeight: notchHeight, board: board, padding: padding)
    }

    // MARK: - Zonas sensibles

    @Test("Cerrada, la única zona sensible es la columna del notch")
    func closedHasOneRect() {
        let r = try! #require(Self.rects().first)
        #expect(Self.rects().count == 1)
        #expect(r.width == Self.notchWidth)
        #expect(r.midX == Self.screen.midX)
        #expect(r.maxY == Self.screen.maxY)
    }

    @Test("La zona nunca sube por encima del borde de la pantalla")
    func neverAboveTheScreen() {
        // Si se pasara, se comería los clics de los iconos de la barra de menús.
        // Se prueban las holguras que usa la app: 2 para quién se come el clic,
        // 12 y 14 para detectar el hover.
        for padding in [CGFloat(0), 2, 12, 14] {
            for rect in Self.rects(board: CGSize(width: 620, height: 200), padding: padding) {
                #expect(rect.maxY <= Self.screen.maxY)
            }
        }
    }

    @Test("Abierta, el panel añade su propia zona justo debajo")
    func openAddsBoardRect() {
        let r = Self.rects(board: CGSize(width: 620, height: 200))
        #expect(r.count == 2)
        #expect(r[1].width == 620)
        #expect(r[1].maxY == Self.screen.maxY - Self.notchHeight)
        #expect(r[1].midX == Self.screen.midX)
    }

    @Test("La holgura ensancha la zona sin despegarla del borde")
    func paddingWidensButStaysPinned() {
        let sin = try! #require(Self.rects().first)
        let con = try! #require(Self.rects(padding: 12).first)
        #expect(con.width == sin.width + 24)
        #expect(con.minY == sin.minY - 12)
        #expect(con.maxY == sin.maxY)
    }

    @Test("Un punto en la barra de menús, al costado del notch, no cuenta")
    func menuBarSideIsNotTheIsland() {
        let rect = try! #require(Self.rects(padding: 12).first)
        // A 300 pt del centro está el reloj o el icono de la app: territorio ajeno.
        #expect(!rect.contains(CGPoint(x: Self.screen.midX + 300, y: Self.screen.maxY - 5)))
        #expect(rect.contains(CGPoint(x: Self.screen.midX, y: Self.screen.maxY - 5)))
    }

    // MARK: - Paso rápido del puntero

    private static let box = CGRect(x: 100, y: 100, width: 100, height: 100)

    @Test("Un tramo que cruza el notch de lado a lado se detecta")
    func crossingIsDetected() {
        // Moviendo rápido, el sistema entrega saltos de cientos de puntos: si solo
        // se miraran los extremos, la pasada no se vería nunca.
        #expect(NotchController.segment(CGPoint(x: 0, y: 150), CGPoint(x: 500, y: 150),
                                        intersects: Self.box))
    }

    @Test("Un tramo en diagonal que atraviesa la esquina también")
    func diagonalCrossing() {
        #expect(NotchController.segment(CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 300),
                                        intersects: Self.box))
    }

    @Test("Un tramo que pasa de largo no cuenta")
    func missingSegment() {
        #expect(!NotchController.segment(CGPoint(x: 0, y: 500), CGPoint(x: 500, y: 500),
                                         intersects: Self.box))
        #expect(!NotchController.segment(CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50),
                                         intersects: Self.box))
    }

    @Test("Un tramo que empieza o termina dentro cuenta")
    func partialSegments() {
        #expect(NotchController.segment(CGPoint(x: 150, y: 150), CGPoint(x: 900, y: 900),
                                        intersects: Self.box))
        #expect(NotchController.segment(CGPoint(x: 900, y: 900), CGPoint(x: 150, y: 150),
                                        intersects: Self.box))
    }

    @Test("Un tramo pegado al borde roza y cuenta")
    func tangentSegment() {
        #expect(NotchController.segment(CGPoint(x: 0, y: 100), CGPoint(x: 500, y: 100),
                                        intersects: Self.box))
    }

    @Test("Un punto quieto cuenta solo si está dentro")
    func degenerateSegment() {
        #expect(NotchController.segment(CGPoint(x: 150, y: 150), CGPoint(x: 150, y: 150),
                                        intersects: Self.box))
        #expect(!NotchController.segment(CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5),
                                         intersects: Self.box))
    }

    // MARK: - Tiempo sobre la isla

    /// Los segundos se comparan con holgura: `Date` los guarda en coma flotante.
    private static func isAbout(_ value: TimeInterval?, _ expected: TimeInterval) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.001
    }

    @Test("El tiempo encima se acumula")
    func hoverAccumulates() {
        var hover = HoverTracker(grace: 0.25)
        let t0 = Date()
        #expect(Self.isAbout(hover.update(inside: true, now: t0), 0))
        #expect(Self.isAbout(hover.update(inside: true, now: t0 + 0.3), 0.3))
    }

    @Test("Salirse un instante no borra lo acumulado")
    func briefExitKeepsTime() {
        // El temblor de la mano saca el puntero unas décimas: si eso reiniciara
        // la cuenta, la isla no abriría nunca con la espera larga.
        var hover = HoverTracker(grace: 0.25)
        let t0 = Date()
        hover.update(inside: true, now: t0)
        hover.update(inside: false, now: t0 + 0.3)        // se sale
        #expect(Self.isAbout(hover.update(inside: true, now: t0 + 0.4), 0.4))   // sigue contando desde t0
    }

    @Test("Irse de verdad reinicia la cuenta")
    func longExitResets() {
        var hover = HoverTracker(grace: 0.25)
        let t0 = Date()
        hover.update(inside: true, now: t0)
        hover.update(inside: false, now: t0 + 0.3)
        hover.update(inside: false, now: t0 + 0.6)        // pasada la gracia
        #expect(Self.isAbout(hover.update(inside: true, now: t0 + 0.7), 0))
    }

    @Test("Estando fuera no hay tiempo que devolver")
    func outsideReturnsNil() {
        var hover = HoverTracker(grace: 0.25)
        #expect(hover.update(inside: false) == nil)
    }

    @Test("Cerrar la isla a la fuerza olvida el hover")
    func resetForgets() {
        var hover = HoverTracker(grace: 0.25)
        let t0 = Date()
        hover.update(inside: true, now: t0)
        hover.reset()
        #expect(Self.isAbout(hover.update(inside: true, now: t0 + 0.5), 0))
    }
}
