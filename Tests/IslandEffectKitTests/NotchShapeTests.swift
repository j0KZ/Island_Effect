import SwiftUI
import Testing
@testable import IslandEffectKit

/// Pruebas de la silueta de la isla. No se compara pixel a pixel: se comprueba
/// que el trazo ocupe lo que debe, quede centrado y no se desborde del marco,
/// que es lo que se rompe al tocar los radios.
@MainActor
struct NotchShapeTests {

    private static let marco = CGRect(x: 0, y: 0, width: 600, height: 260)

    private static func bounds(_ shape: some Shape, in rect: CGRect = marco) -> CGRect {
        shape.path(in: rect).boundingRect
    }

    // MARK: - El notch en reposo

    @Test("El notch ocupa todo el marco que se le da")
    func notchFillsItsRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 32)
        let b = Self.bounds(NotchShape(), in: rect)
        #expect(abs(b.width - rect.width) < 0.5)
        #expect(abs(b.height - rect.height) < 0.5)
    }

    @Test("Un radio exagerado se recorta en vez de deformar la figura")
    func notchClampsHugeRadii() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 32)
        let b = Self.bounds(NotchShape(topRadius: 9_999, bottomRadius: 9_999), in: rect)
        // Sin el recorte, las curvas se cruzarían y el trazo se saldría del marco.
        #expect(b.minX >= rect.minX - 0.5)
        #expect(b.maxX <= rect.maxX + 0.5)
        #expect(b.maxY <= rect.maxY + 0.5)
    }

    @Test("El notch es simétrico")
    func notchIsSymmetric() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 32)
        let b = Self.bounds(NotchShape(), in: rect)
        #expect(abs(b.midX - rect.midX) < 0.5)
    }

    // MARK: - La isla cerrada

    @Test("Cerrada, la isla es solo la columna del notch")
    func closedIslandIsJustTheNotch() {
        let shape = IslandShape(notchWidth: 185, notchHeight: 32, boardHeight: 0)
        let b = Self.bounds(shape)
        #expect(abs(b.width - 185) < 0.5)
        #expect(abs(b.midX - Self.marco.midX) < 0.5)   // centrada en la pantalla
    }

    @Test("Un alto de panel negativo o ínfimo cuenta como cerrada")
    func tinyBoardCountsAsClosed() {
        let negativa = Self.bounds(IslandShape(notchWidth: 185, notchHeight: 32, boardHeight: -50))
        let casiCero = Self.bounds(IslandShape(notchWidth: 185, notchHeight: 32, boardHeight: 0.5))
        #expect(abs(negativa.width - 185) < 0.5)
        #expect(abs(casiCero.width - 185) < 0.5)
    }

    // MARK: - La isla abierta

    @Test("Abierta, el panel ocupa el ancho completo y la altura se suma")
    func openIslandSpansTheBoard() {
        let shape = IslandShape(notchWidth: 185, notchHeight: 32, boardHeight: 200)
        let b = Self.bounds(shape)
        #expect(abs(b.width - Self.marco.width) < 0.5)
        #expect(abs(b.height - (32 + 200)) < 0.5)
        #expect(abs(b.midX - Self.marco.midX) < 0.5)
    }

    @Test("La isla arranca pegada al borde de arriba")
    func islandStartsAtTheTop() {
        // El notch tiene que tocar el borde de la pantalla: si bajara aunque sea
        // un punto, se vería una franja entre el recorte y la isla.
        let b = Self.bounds(IslandShape(notchWidth: 185, notchHeight: 32, boardHeight: 200))
        #expect(abs(b.minY - Self.marco.minY) < 0.5)
    }

    @Test("Un notch más ancho que la pantalla se recorta")
    func notchWiderThanBoardIsClamped() {
        let shape = IslandShape(notchWidth: 5_000, notchHeight: 32, boardHeight: 0)
        let b = Self.bounds(shape)
        #expect(b.width <= Self.marco.width + 0.5)
    }

    @Test("El panel crece con su altura")
    func openingGrowsWithBoardHeight() {
        let chica = Self.bounds(IslandShape(notchWidth: 185, notchHeight: 32, boardHeight: 100))
        let grande = Self.bounds(IslandShape(notchWidth: 185, notchHeight: 32, boardHeight: 200))
        #expect(grande.height > chica.height)
    }
}
