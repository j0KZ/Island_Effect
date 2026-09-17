import Foundation
import Testing
@testable import IslandEffectKit

/// Qué cabe dentro del panel abierto.
///
/// Esto existe por un fallo real: el estado "no hay nada sonando" y el aviso de
/// permiso no se compactaban, y en el panel más bajo que ofrece Preferencias
/// los botones —lo único accionable de la pantalla— quedaban cortados por el
/// borde de la isla. La ficha del reproductor sí se compactaba, así que el fallo
/// solo aparecía cuando no había música, que es justo cuando no estabas
/// mirando.
struct PanelLayoutTests {

    /// Todos los altos que el slider de Preferencias deja elegir.
    private static var everyAllowedHeight: [CGFloat] {
        stride(from: Prefs.Limits.expandedHeight.lowerBound,
               through: Prefs.Limits.expandedHeight.upperBound,
               by: 1).map { CGFloat($0) }
    }

    @Test("En el panel más bajo todavía queda sitio para el contenido")
    func minimumHeightLeavesRoom() {
        // Si esto diera negativo, el contenido empezaría fuera del panel.
        let minimo = CGFloat(Prefs.Limits.expandedHeight.lowerBound)
        #expect(PanelLayout.contentHeight(panelHeight: minimo) > 0)
    }

    @Test("Ningún alto permitido deja al contenido sin espacio")
    func noAllowedHeightStarvesTheContent() {
        for alto in Self.everyAllowedHeight {
            #expect(PanelLayout.contentHeight(panelHeight: alto) > 0,
                    "el panel de \(alto) puntos no deja sitio")
        }
    }

    @Test("El panel más bajo pide la versión mínima")
    func minimumHeightIsTiny() {
        // Es el caso que fallaba: acá solo caben el título y los botones.
        let minimo = CGFloat(Prefs.Limits.expandedHeight.lowerBound)
        let densidad = PanelLayout.density(contentHeight: PanelLayout.contentHeight(panelHeight: minimo))
        #expect(densidad == .tiny)
        #expect(densidad.isTiny)
        #expect(densidad.isCompact)
    }

    @Test("El alto de fábrica lo muestra todo")
    func defaultHeightShowsEverything() {
        // 200 es lo que trae una instalación nueva: ahí no debe faltar nada.
        let densidad = PanelLayout.density(contentHeight: PanelLayout.contentHeight(panelHeight: 200))
        #expect(densidad == .full)
        #expect(!densidad.isCompact)
    }

    @Test("Cuanto más alto el panel, nunca menos contenido")
    func densityNeverGoesBackwards() {
        // Sin esto, un corte mal puesto podría hacer que subir el slider
        // escondiera cosas.
        func rango(_ d: PanelLayout.Density) -> Int {
            switch d {
            case .tiny: return 0
            case .compact: return 1
            case .full: return 2
            }
        }
        var anterior = 0
        for alto in Self.everyAllowedHeight {
            let actual = rango(PanelLayout.density(contentHeight: PanelLayout.contentHeight(panelHeight: alto)))
            #expect(actual >= anterior, "a \(alto) puntos el panel muestra menos que al alto anterior")
            anterior = actual
        }
    }

    @Test("El panel bajo también encoge la cabecera y los márgenes")
    func chromeShrinksToo() {
        #expect(PanelLayout.chromeIsCompact(panelHeight: 100))
        #expect(!PanelLayout.chromeIsCompact(panelHeight: 200))
        #expect(PanelLayout.headerHeight(panelHeight: 100) < PanelLayout.headerHeight(panelHeight: 200))
        #expect(PanelLayout.contentPadding(panelHeight: 100).vertical
                < PanelLayout.contentPadding(panelHeight: 200).vertical)
    }

    @Test("El alto útil crece con el panel")
    func contentHeightGrowsWithThePanel() {
        #expect(PanelLayout.contentHeight(panelHeight: 340) > PanelLayout.contentHeight(panelHeight: 200))
        #expect(PanelLayout.contentHeight(panelHeight: 200) > PanelLayout.contentHeight(panelHeight: 96))
    }

    @Test("Los tres cortes están donde dicen estar")
    func thresholds() {
        #expect(PanelLayout.density(contentHeight: 87.9) == .tiny)
        #expect(PanelLayout.density(contentHeight: 88) == .compact)
        #expect(PanelLayout.density(contentHeight: 119.9) == .compact)
        #expect(PanelLayout.density(contentHeight: 120) == .full)
    }

    @Test("Un hueco absurdo no rompe la decisión")
    func degenerateHeights() {
        // Durante la animación de apertura el alto pasa por cero.
        #expect(PanelLayout.density(contentHeight: 0) == .tiny)
        #expect(PanelLayout.density(contentHeight: -50) == .tiny)
    }
}
