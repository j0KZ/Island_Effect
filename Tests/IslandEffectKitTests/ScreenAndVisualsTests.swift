import AppKit
import Testing
@testable import IslandEffectKit

/// Pruebas de la medición del notch. No se puede fabricar una `NSScreen`, así que
/// se prueba la función que interpreta lo que la pantalla reporta.
struct ScreenMetricsTests {

    /// Lo que reporta un MacBook Pro de 14": barra de menús de 32 pt y dos áreas
    /// auxiliares que dejan el recorte en medio.
    @Test("Un MacBook con notch se mide bien")
    func realNotch() {
        let found = ScreenMetrics.notch(frameWidth: 1512, topInset: 32,
                                        left: CGRect(x: 0, y: 0, width: 663, height: 32),
                                        right: CGRect(x: 849, y: 0, width: 663, height: 32))
        #expect(found.hasNotch)
        // El ancho se escribe ya resuelto y con tipo: dentro de #expect, una
        // resta de enteros se compara como entero y nunca casa con un CGFloat.
        #expect(found.size.width == CGFloat(186))
        #expect(found.size.height == CGFloat(32))
    }

    @Test("Un monitor externo no tiene notch")
    func externalDisplay() {
        // Sin barra de menús empotrada, `topInset` es 0 y no hay áreas auxiliares.
        let found = ScreenMetrics.notch(frameWidth: 2560, topInset: 0, left: nil, right: nil)
        #expect(!found.hasNotch)
        #expect(found.size == ScreenMetrics.handleSize)
    }

    @Test("Un hueco ridículo no se toma por un notch")
    func tinyGapIsNotANotch() {
        // Un par de puntos entre las dos áreas no es un recorte: sería una isla
        // de 4 pt de ancho pegada arriba.
        let found = ScreenMetrics.notch(frameWidth: 1000, topInset: 32,
                                        left: CGRect(x: 0, y: 0, width: 498, height: 32),
                                        right: CGRect(x: 502, y: 0, width: 498, height: 32))
        #expect(!found.hasNotch)
        #expect(found.size == ScreenMetrics.handleSize)
    }

    @Test("Con áreas auxiliares pero sin barra empotrada, tampoco")
    func insetIsRequired() {
        let found = ScreenMetrics.notch(frameWidth: 1512, topInset: 0,
                                        left: CGRect(x: 0, y: 0, width: 600, height: 32),
                                        right: CGRect(x: 900, y: 0, width: 600, height: 32))
        #expect(!found.hasNotch)
    }

    @Test("Si falta una de las dos áreas, se usa el asa")
    func halfInformationIsNotEnough() {
        let found = ScreenMetrics.notch(frameWidth: 1512, topInset: 32,
                                        left: CGRect(x: 0, y: 0, width: 600, height: 32),
                                        right: nil)
        #expect(!found.hasNotch)
        #expect(found.size == ScreenMetrics.handleSize)
    }
}

/// Pruebas de los cálculos de apariencia que estaban dentro de las vistas.
struct IslandVisualsTests {

    @Test("El contorno se aviva al pasar el mouse y se apaga en reposo")
    func rimStrength() {
        let reposo = IslandVisuals.rimStrength(base: 0.8, isOpen: false, isHovering: false)
        let hover = IslandVisuals.rimStrength(base: 0.8, isOpen: false, isHovering: true)
        let abierta = IslandVisuals.rimStrength(base: 0.8, isOpen: true, isHovering: true)
        #expect(reposo < abierta)
        #expect(hover > abierta)
        #expect(abierta == 0.8)
    }

    @Test("El contorno nunca se pasa de 1 ni baja de 0")
    func rimStrengthIsClamped() {
        #expect(IslandVisuals.rimStrength(base: 1, isOpen: false, isHovering: true) == 1)
        #expect(IslandVisuals.rimStrength(base: 5, isOpen: true, isHovering: false) == 1)
        #expect(IslandVisuals.rimStrength(base: -1, isOpen: false, isHovering: false) == 0)
    }
}

/// Pruebas del slider: el de volumen y el de la posición de la canción.
struct SliderMathTests {

    @Test("El relleno del slider corresponde al valor")
    func fraction() {
        #expect(SliderMath.fraction(of: 0, in: 0...1) == 0)
        #expect(SliderMath.fraction(of: 0.5, in: 0...1) == 0.5)
        #expect(SliderMath.fraction(of: 150, in: 100...200) == 0.5)
    }

    @Test("Un rango degenerado no divide por cero")
    func degenerateRange() {
        #expect(SliderMath.fraction(of: 5, in: 5...5) == 0)
        #expect(SliderMath.value(atX: 50, width: 0, in: 0...1) == 0)
    }

    @Test("Arrastrar fuera del slider se queda en los extremos")
    func draggingIsClamped() {
        #expect(SliderMath.value(atX: -40, width: 200, in: 0...1) == 0)
        #expect(SliderMath.value(atX: 999, width: 200, in: 0...1) == 1)
    }

    @Test("Arrastrar hasta la mitad da el valor de la mitad")
    func draggingMapsToValue() {
        #expect(SliderMath.value(atX: 100, width: 200, in: 0...240) == 120)
    }

    @Test("Ir y volver da el mismo valor")
    func roundTrip() {
        let range = 0.0...240.0
        let f = SliderMath.fraction(of: 90, in: range)
        #expect(SliderMath.value(atX: CGFloat(f) * 200, width: 200, in: range) == 90)
    }
}

/// Pruebas de qué pestañas se muestran en la isla abierta.
struct NotchTabTests {

    @Test("Solo se ofrecen los módulos activados")
    func availableTabs() {
        #expect(NotchTab.available(music: true, shelf: true) == [.music, .shelf])
        #expect(NotchTab.available(music: true, shelf: false) == [.music])
        #expect(NotchTab.available(music: false, shelf: true) == [.shelf])
    }

    @Test("Si se desactiva el módulo que estaba abierto, se cae en el otro")
    func resolveFallsBack() {
        #expect(NotchTab.resolve(.music, available: [.shelf]) == .shelf)
        #expect(NotchTab.resolve(.shelf, available: [.music]) == .music)
    }

    @Test("Si el módulo sigue activo, no se cambia de pestaña")
    func resolveKeepsCurrent() {
        #expect(NotchTab.resolve(.shelf, available: [.music, .shelf]) == .shelf)
    }

    @Test("Sin ningún módulo se queda la pestaña que había")
    func resolveWithNothingAvailable() {
        // Preferencias no deja apagar los dos; esto solo evita inventarse una
        // pestaña que el usuario no pidió si algún día llegara ese estado.
        #expect(NotchTab.resolve(.shelf, available: []) == .shelf)
    }
}

/// La píldora se dimensiona midiendo su propio texto: si el texto que dibuja la
/// vista fuera otro, el ancho dejaría de cuadrar.
struct ActivityLabelTests {

    @Test("Cada estado de la batería tiene su texto")
    func batteryLabels() {
        #expect(LiveActivity.batteryLabel(plugged: true, charging: true) == "Charging")
        #expect(LiveActivity.batteryLabel(plugged: true, charging: false) == "Plugged in")
        #expect(LiveActivity.batteryLabel(plugged: false, charging: false) == "On battery")
    }

    @Test("Cargando manda sobre enchufado")
    func chargingWins() {
        #expect(LiveActivity.batteryLabel(plugged: false, charging: true) == "Charging")
    }
}
