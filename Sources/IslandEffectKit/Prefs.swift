import Foundation
import Combine

/// Preferencias persistentes de la app. Todo se guarda en UserDefaults.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d: UserDefaults

    // Apariencia
    @Published var expandedWidth: Double { didSet { d.set(expandedWidth, forKey: K.expandedWidth) } }
    @Published var expandedHeight: Double { didSet { d.set(expandedHeight, forKey: K.expandedHeight) } }
    @Published var cornerRadius: Double { didSet { d.set(cornerRadius, forKey: K.cornerRadius) } }
    @Published var extraClosedWidth: Double { didSet { d.set(extraClosedWidth, forKey: K.extraClosedWidth) } }
    @Published var rimOpacity: Double { didSet { d.set(rimOpacity, forKey: K.rimOpacity) } }

    // Comportamiento
    @Published var openOnHover: Bool { didSet { d.set(openOnHover, forKey: K.openOnHover) } }
    @Published var hoverOpenDelay: Double { didSet { d.set(hoverOpenDelay, forKey: K.hoverOpenDelay) } }
    @Published var followMouseScreen: Bool { didSet { d.set(followMouseScreen, forKey: K.followMouseScreen) } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: K.haptics) } }
    @Published var showMenuBarIcon: Bool { didSet { d.set(showMenuBarIcon, forKey: K.showMenuBarIcon) } }

    // Live activities
    @Published var liveMusic: Bool { didSet { d.set(liveMusic, forKey: K.liveMusic) } }
    @Published var liveBattery: Bool { didSet { d.set(liveBattery, forKey: K.liveBattery) } }
    @Published var liveScreenshot: Bool { didSet { d.set(liveScreenshot, forKey: K.liveScreenshot) } }
    @Published var activityDuration: Double { didSet { d.set(activityDuration, forKey: K.activityDuration) } }

    // Módulos
    @Published var enableMusic: Bool { didSet { d.set(enableMusic, forKey: K.enableMusic) } }
    @Published var enableShelf: Bool { didSet { d.set(enableShelf, forKey: K.enableShelf) } }
    @Published var captureShelf: Bool { didSet { d.set(captureShelf, forKey: K.captureShelf) } }
    @Published var captureMinutes: Double { didSet { d.set(captureMinutes, forKey: K.captureMinutes) } }
    @Published var useAppleMusic: Bool { didSet { d.set(useAppleMusic, forKey: K.useAppleMusic) } }
    @Published var useSpotify: Bool { didSet { d.set(useSpotify, forKey: K.useSpotify) } }

    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: K.launchAtLogin) } }


    /// Los rangos que ofrecen los sliders de Preferencias. Se aplican también al
    /// leer: un valor corrupto o heredado de otra versión (un ancho de 0, por
    /// ejemplo) dejaría la isla invisible, y desde la interfaz no habría cómo
    /// recuperarla.
    enum Limits {
        static let expandedWidth: ClosedRange<Double> = 420...900
        static let expandedHeight: ClosedRange<Double> = 96...340
        static let cornerRadius: ClosedRange<Double> = 8...40
        static let extraClosedWidth: ClosedRange<Double> = 0...260
        static let rimOpacity: ClosedRange<Double> = 0...1
        static let hoverOpenDelay: ClosedRange<Double> = 0...0.8
        static let activityDuration: ClosedRange<Double> = 1...6
        /// Cuánto se queda una captura en la repisa antes de irse sola. Menos de
        /// un minuto no alcanza ni a verla; más de media hora deja de ser una
        /// bandeja de paso y vuelve a ser el Escritorio lleno de capturas.
        static let captureMinutes: ClosedRange<Double> = 1...30
    }

    /// Estática porque el `init` la necesita antes de que el objeto exista del todo.
    private static func clamped(_ defaults: UserDefaults, _ key: String,
                                _ range: ClosedRange<Double>) -> Double {
        min(max(defaults.double(forKey: key), range.lowerBound), range.upperBound)
    }

    private enum K {
        static let expandedWidth = "expandedWidth"
        static let expandedHeight = "expandedHeight"
        static let cornerRadius = "cornerRadius"
        static let extraClosedWidth = "extraClosedWidth"
        static let rimOpacity = "rimOpacity"
        static let openOnHover = "openOnHover"
        static let hoverOpenDelay = "hoverOpenDelay"
        static let followMouseScreen = "followMouseScreen"
        static let haptics = "haptics"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let liveMusic = "liveMusic"
        static let liveBattery = "liveBattery"
        static let liveScreenshot = "liveScreenshot"
        static let activityDuration = "activityDuration"
        static let enableMusic = "enableMusic"
        static let enableShelf = "enableShelf"
        static let captureShelf = "captureShelf"
        static let captureMinutes = "captureMinutes"
        static let useAppleMusic = "useAppleMusic"
        static let useSpotify = "useSpotify"
        static let launchAtLogin = "launchAtLogin"
    }

    /// Dónde se guardan las preferencias. Se recibe para que las pruebas usen un
    /// dominio aparte y no toquen las del usuario.
    init(defaults: UserDefaults = .standard) {
        d = defaults
        d.register(defaults: [
            K.expandedWidth: 620.0,
            K.expandedHeight: 200.0,
            K.cornerRadius: 22.0,
            K.extraClosedWidth: 0.0,
            K.rimOpacity: 0.85,
            K.openOnHover: true,
            K.hoverOpenDelay: 0.4,
            K.followMouseScreen: true,
            K.haptics: true,
            K.showMenuBarIcon: true,
            K.liveMusic: true,
            K.liveBattery: true,
            K.liveScreenshot: true,
            K.activityDuration: 2.2,
            K.enableMusic: true,
            K.enableShelf: true,
            K.captureShelf: true,
            K.captureMinutes: 5.0,
            K.useAppleMusic: true,
            K.useSpotify: true,
            K.launchAtLogin: false
        ])
        expandedWidth = Self.clamped(d, K.expandedWidth, Limits.expandedWidth)
        expandedHeight = Self.clamped(d, K.expandedHeight, Limits.expandedHeight)
        cornerRadius = Self.clamped(d, K.cornerRadius, Limits.cornerRadius)
        extraClosedWidth = Self.clamped(d, K.extraClosedWidth, Limits.extraClosedWidth)
        rimOpacity = Self.clamped(d, K.rimOpacity, Limits.rimOpacity)
        openOnHover = d.bool(forKey: K.openOnHover)
        hoverOpenDelay = Self.clamped(d, K.hoverOpenDelay, Limits.hoverOpenDelay)
        followMouseScreen = d.bool(forKey: K.followMouseScreen)
        haptics = d.bool(forKey: K.haptics)
        showMenuBarIcon = d.bool(forKey: K.showMenuBarIcon)
        liveMusic = d.bool(forKey: K.liveMusic)
        liveBattery = d.bool(forKey: K.liveBattery)
        liveScreenshot = d.bool(forKey: K.liveScreenshot)
        activityDuration = Self.clamped(d, K.activityDuration, Limits.activityDuration)
        enableMusic = d.bool(forKey: K.enableMusic)
        enableShelf = d.bool(forKey: K.enableShelf)
        captureShelf = d.bool(forKey: K.captureShelf)
        captureMinutes = Self.clamped(d, K.captureMinutes, Limits.captureMinutes)
        useAppleMusic = d.bool(forKey: K.useAppleMusic)
        useSpotify = d.bool(forKey: K.useSpotify)
        launchAtLogin = d.bool(forKey: K.launchAtLogin)
    }

    func resetToDefaults() {
        for key in [K.expandedWidth, K.expandedHeight, K.cornerRadius, K.extraClosedWidth,
                    K.rimOpacity, K.openOnHover, K.hoverOpenDelay,
                    K.followMouseScreen, K.haptics, K.showMenuBarIcon,
                    K.liveMusic, K.liveBattery, K.liveScreenshot, K.activityDuration,
                    K.enableMusic, K.enableShelf, K.captureShelf, K.captureMinutes,
                    K.useAppleMusic, K.useSpotify] {
            d.removeObject(forKey: key)
        }
        expandedWidth = Self.clamped(d, K.expandedWidth, Limits.expandedWidth)
        expandedHeight = Self.clamped(d, K.expandedHeight, Limits.expandedHeight)
        cornerRadius = Self.clamped(d, K.cornerRadius, Limits.cornerRadius)
        extraClosedWidth = Self.clamped(d, K.extraClosedWidth, Limits.extraClosedWidth)
        rimOpacity = Self.clamped(d, K.rimOpacity, Limits.rimOpacity)
        openOnHover = d.bool(forKey: K.openOnHover)
        hoverOpenDelay = Self.clamped(d, K.hoverOpenDelay, Limits.hoverOpenDelay)
        followMouseScreen = d.bool(forKey: K.followMouseScreen)
        haptics = d.bool(forKey: K.haptics)
        showMenuBarIcon = d.bool(forKey: K.showMenuBarIcon)
        liveMusic = d.bool(forKey: K.liveMusic)
        liveBattery = d.bool(forKey: K.liveBattery)
        liveScreenshot = d.bool(forKey: K.liveScreenshot)
        activityDuration = Self.clamped(d, K.activityDuration, Limits.activityDuration)
        enableMusic = d.bool(forKey: K.enableMusic)
        enableShelf = d.bool(forKey: K.enableShelf)
        captureShelf = d.bool(forKey: K.captureShelf)
        captureMinutes = Self.clamped(d, K.captureMinutes, Limits.captureMinutes)
        useAppleMusic = d.bool(forKey: K.useAppleMusic)
        useSpotify = d.bool(forKey: K.useSpotify)
    }
}
