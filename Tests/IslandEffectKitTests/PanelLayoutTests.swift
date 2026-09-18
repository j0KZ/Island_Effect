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

/// El recorrido de la captura subiendo al notch.
///
/// De una animación solo se puede comprobar la trayectoria, pero es justo donde
/// se rompen: empezar ya invisible, terminar fuera del notch, o salirse del
/// camino a media subida no se ve en una vista previa, que es un solo fotograma.
struct CaptureTossTests {

    private static let notch: CGFloat = 38

    private static func frame(_ t: Double) -> CaptureToss.Frame {
        CaptureToss.frame(at: t, notchHeight: notch)
    }

    @Test("Arranca abajo, entera y visible")
    func startsBelowAndVisible() {
        let inicio = Self.frame(0)
        #expect(inicio.offsetY == Self.notch + CaptureToss.travel)
        #expect(inicio.scale == 1)
        #expect(inicio.opacity == 1)
    }

    @Test("Termina dentro del notch, chica y ya invisible")
    func endsInsideTheNotch() {
        let fin = Self.frame(1)
        // Lo que cuenta es el CENTRO de la miniatura: `scaleEffect` encoge
        // desde ahí, así que mirar el borde de arriba daba por buena una
        // animación que se apagaba en el aire, debajo del notch.
        let centro = fin.offsetY + CaptureToss.side / 2
        #expect(centro > 0)
        #expect(centro < Self.notch)
        #expect(fin.scale < 0.35)
        #expect(fin.opacity == 0)
    }

    @Test("Sube sin volver atrás")
    func risesMonotonically() {
        var anterior = CGFloat.greatestFiniteMagnitude
        for paso in stride(from: 0.0, through: 1.0, by: 0.05) {
            let y = Self.frame(paso).offsetY
            #expect(y <= anterior, "a \(paso) la miniatura baja en vez de subir")
            anterior = y
        }
    }

    @Test("Se achica sin volver a crecer")
    func shrinksMonotonically() {
        var anterior = CGFloat.greatestFiniteMagnitude
        for paso in stride(from: 0.0, through: 1.0, by: 0.05) {
            let escala = Self.frame(paso).scale
            #expect(escala <= anterior)
            #expect(escala > 0, "a \(paso) la miniatura desaparece del todo")
            anterior = escala
        }
    }

    @Test("Se ve entera la primera mitad del camino")
    func staysVisibleLongEnough() {
        // Si empieza a apagarse enseguida no se alcanza a ver qué subió, que es
        // el único propósito de la animación.
        #expect(Self.frame(0.25).opacity == 1)
        #expect(Self.frame(0.5).opacity == 1)
        #expect(Self.frame(0.8).opacity < 1)
    }

    @Test("Un progreso fuera de rango no la manda a ninguna parte")
    func clampsProgress() {
        // Un resorte con rebote se pasa de 1 antes de asentarse.
        #expect(Self.frame(1.3) == Self.frame(1))
        #expect(Self.frame(-0.2) == Self.frame(0))
    }
}

/// El latido del contorno al tragarse la captura.
struct RimPulseTests {

    @Test("El latido se ve aunque tengas el contorno al mínimo")
    func pulseIsVisibleEvenAtZero() {
        // El contorno en 0 es un ajuste legítimo: si el latido se multiplicara
        // por él, no pasaría nada y el aviso se perdería justo con quien eligió
        // la isla más discreta.
        let apagado = IslandVisuals.rimStrength(base: 0, isOpen: false, isHovering: false,
                                                pulsing: true)
        #expect(apagado >= 0.9)
    }

    @Test("Y es más fuerte que cualquier estado normal")
    func pulseBeatsEveryOtherState() {
        let normal = IslandVisuals.rimStrength(base: 0.85, isOpen: false, isHovering: false)
        let hover = IslandVisuals.rimStrength(base: 0.85, isOpen: false, isHovering: true)
        let latido = IslandVisuals.rimStrength(base: 0.85, isOpen: false, isHovering: false,
                                               pulsing: true)
        #expect(latido > normal)
        #expect(latido >= hover)
    }

    @Test("Nunca se pasa de uno")
    func neverOverblown() {
        #expect(IslandVisuals.rimStrength(base: 1, isOpen: false, isHovering: false,
                                          pulsing: true) <= 1)
    }

    @Test("Sin latido todo sigue igual que antes")
    func noPulseIsUnchanged() {
        #expect(IslandVisuals.rimStrength(base: 0.8, isOpen: true, isHovering: false) == 0.8)
        #expect(IslandVisuals.rimStrength(base: 0.8, isOpen: false, isHovering: false) == 0.8 * 0.9)
    }
}
