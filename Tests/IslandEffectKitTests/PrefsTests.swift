import Foundation
import Testing
@testable import IslandEffectKit

/// Pruebas de las preferencias: valores de fábrica, persistencia y el botón de
/// restablecer. Cada prueba usa un dominio desechable, nunca las del usuario.
struct PrefsTests {

    private static func scratchDefaults() -> UserDefaults {
        let suite = "prefs-tests-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test("Una instalación nueva trae los valores de fábrica")
    func factoryDefaults() {
        let prefs = Prefs(defaults: Self.scratchDefaults())
        #expect(prefs.expandedWidth == 620)
        #expect(prefs.expandedHeight == 200)
        #expect(prefs.cornerRadius == 22)
        #expect(prefs.extraClosedWidth == 0)
        #expect(prefs.rimOpacity == 0.85)
        #expect(prefs.openOnHover)
        #expect(prefs.hoverOpenDelay == 0.4)
        #expect(prefs.activityDuration == 2.2)
        #expect(prefs.followMouseScreen)
        #expect(prefs.haptics)
        #expect(prefs.showMenuBarIcon)
        #expect(prefs.liveMusic)
        #expect(prefs.liveBattery)
        #expect(prefs.liveScreenshot)
        #expect(prefs.enableMusic)
        #expect(prefs.enableShelf)
        #expect(prefs.captureShelf)
        #expect(prefs.captureMinutes == 5)
        // Cinco segundos: lo mismo que duraba la miniatura de macOS, que es lo
        // que este aviso vino a reemplazar.
        #expect(prefs.captureNoticeSeconds == 5)
        #expect(prefs.useAppleMusic)
        #expect(prefs.useSpotify)
        // Lo único que viene apagado: la app no se mete sola en el arranque.
        #expect(!prefs.launchAtLogin)
    }

    @Test("Lo que se cambia sigue ahí al reabrir la app")
    func changesPersist() {
        let defaults = Self.scratchDefaults()
        let antes = Prefs(defaults: defaults)
        antes.expandedWidth = 700
        antes.hoverOpenDelay = 0.6
        antes.haptics = false
        antes.useSpotify = false

        let despues = Prefs(defaults: defaults)
        #expect(despues.expandedWidth == 700)
        #expect(despues.hoverOpenDelay == 0.6)
        #expect(!despues.haptics)
        #expect(!despues.useSpotify)
    }

    @Test("Un valor imposible guardado se acota al leerlo")
    func storedValuesAreClamped() {
        // Una versión anterior, un `defaults write` a mano o un archivo corrupto
        // podían dejar una isla de ancho 0: invisible, y sin forma de arreglarla
        // desde Preferencias porque el slider tampoco alcanzaba.
        let defaults = Self.scratchDefaults()
        defaults.set(0.0, forKey: "expandedWidth")
        defaults.set(99_999.0, forKey: "expandedHeight")
        defaults.set(-3.0, forKey: "rimOpacity")
        defaults.set(50.0, forKey: "hoverOpenDelay")
        defaults.set(0.0, forKey: "activityDuration")
        defaults.set(0.0, forKey: "captureMinutes")
        defaults.set(0.0, forKey: "captureNoticeSeconds")

        let prefs = Prefs(defaults: defaults)
        #expect(prefs.expandedWidth == Prefs.Limits.expandedWidth.lowerBound)
        #expect(prefs.expandedHeight == Prefs.Limits.expandedHeight.upperBound)
        #expect(prefs.rimOpacity == Prefs.Limits.rimOpacity.lowerBound)
        #expect(prefs.hoverOpenDelay == Prefs.Limits.hoverOpenDelay.upperBound)
        #expect(prefs.activityDuration == Prefs.Limits.activityDuration.lowerBound)
        // Con 0 minutos la captura caducaría antes de llegar a verse.
        #expect(prefs.captureMinutes == Prefs.Limits.captureMinutes.lowerBound)
        #expect(prefs.captureNoticeSeconds == Prefs.Limits.captureNoticeSeconds.lowerBound)
    }

    @Test("Los valores de fábrica están dentro de los rangos que ofrece Preferencias")
    func defaultsAreInsideTheirRanges() {
        let prefs = Prefs(defaults: Self.scratchDefaults())
        #expect(Prefs.Limits.expandedWidth.contains(prefs.expandedWidth))
        #expect(Prefs.Limits.expandedHeight.contains(prefs.expandedHeight))
        #expect(Prefs.Limits.cornerRadius.contains(prefs.cornerRadius))
        #expect(Prefs.Limits.extraClosedWidth.contains(prefs.extraClosedWidth))
        #expect(Prefs.Limits.rimOpacity.contains(prefs.rimOpacity))
        #expect(Prefs.Limits.hoverOpenDelay.contains(prefs.hoverOpenDelay))
        #expect(Prefs.Limits.activityDuration.contains(prefs.activityDuration))
        #expect(Prefs.Limits.captureMinutes.contains(prefs.captureMinutes))
        #expect(Prefs.Limits.captureNoticeSeconds.contains(prefs.captureNoticeSeconds))
        // El aviso de la captura tiene que poder durar más que los otros: es lo
        // único que dice que existe, desde que no está la miniatura de macOS.
        #expect(Prefs.Limits.captureNoticeSeconds.upperBound
                > Prefs.Limits.activityDuration.upperBound)
    }

    @Test("Restablecer deja todo como recién instalado")
    func resetRestoresEverything() {
        let defaults = Self.scratchDefaults()
        let prefs = Prefs(defaults: defaults)
        prefs.expandedWidth = 999
        prefs.rimOpacity = 0.1
        prefs.openOnHover = false
        prefs.liveBattery = false
        prefs.enableShelf = false

        prefs.resetToDefaults()

        // Se compara contra una instalación nueva, así si alguna preferencia se
        // agrega y se olvida en `resetToDefaults`, esta prueba lo caza.
        let nueva = Prefs(defaults: Self.scratchDefaults())
        #expect(prefs.expandedWidth == nueva.expandedWidth)
        #expect(prefs.expandedHeight == nueva.expandedHeight)
        #expect(prefs.cornerRadius == nueva.cornerRadius)
        #expect(prefs.extraClosedWidth == nueva.extraClosedWidth)
        #expect(prefs.rimOpacity == nueva.rimOpacity)
        #expect(prefs.openOnHover == nueva.openOnHover)
        #expect(prefs.hoverOpenDelay == nueva.hoverOpenDelay)
        #expect(prefs.followMouseScreen == nueva.followMouseScreen)
        #expect(prefs.haptics == nueva.haptics)
        #expect(prefs.showMenuBarIcon == nueva.showMenuBarIcon)
        #expect(prefs.liveMusic == nueva.liveMusic)
        #expect(prefs.liveBattery == nueva.liveBattery)
        #expect(prefs.activityDuration == nueva.activityDuration)
        #expect(prefs.enableMusic == nueva.enableMusic)
        #expect(prefs.enableShelf == nueva.enableShelf)
        #expect(prefs.useAppleMusic == nueva.useAppleMusic)
        #expect(prefs.useSpotify == nueva.useSpotify)
    }

    @Test("Restablecer no toca el arranque automático")
    func resetKeepsLaunchAtLogin() {
        // Abrir al iniciar sesión es un ajuste del sistema, no de la app: se
        // registra aparte y restablecer la apariencia no debería apagarlo.
        let prefs = Prefs(defaults: Self.scratchDefaults())
        prefs.launchAtLogin = true

        prefs.resetToDefaults()

        #expect(prefs.launchAtLogin)
    }
}
