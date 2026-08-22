import Foundation
import Combine

/// Preferencias persistentes de la app. Todo se guarda en UserDefaults.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    // Apariencia
    @Published var expandedWidth: Double { didSet { d.set(expandedWidth, forKey: K.expandedWidth) } }
    @Published var expandedHeight: Double { didSet { d.set(expandedHeight, forKey: K.expandedHeight) } }
    @Published var cornerRadius: Double { didSet { d.set(cornerRadius, forKey: K.cornerRadius) } }
    @Published var extraClosedWidth: Double { didSet { d.set(extraClosedWidth, forKey: K.extraClosedWidth) } }
    @Published var tintedBackground: Bool { didSet { d.set(tintedBackground, forKey: K.tintedBackground) } }
    @Published var rimOpacity: Double { didSet { d.set(rimOpacity, forKey: K.rimOpacity) } }
    @Published var rimGlow: Bool { didSet { d.set(rimGlow, forKey: K.rimGlow) } }
    @Published var glassBackground: Bool { didSet { d.set(glassBackground, forKey: K.glassBackground) } }

    // Comportamiento
    @Published var openOnHover: Bool { didSet { d.set(openOnHover, forKey: K.openOnHover) } }
    @Published var hoverOpenDelay: Double { didSet { d.set(hoverOpenDelay, forKey: K.hoverOpenDelay) } }
    @Published var hoverCloseDelay: Double { didSet { d.set(hoverCloseDelay, forKey: K.hoverCloseDelay) } }
    @Published var followMouseScreen: Bool { didSet { d.set(followMouseScreen, forKey: K.followMouseScreen) } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: K.haptics) } }
    @Published var showMenuBarIcon: Bool { didSet { d.set(showMenuBarIcon, forKey: K.showMenuBarIcon) } }

    // Gestos
    @Published var scrollVolume: Bool { didSet { d.set(scrollVolume, forKey: K.scrollVolume) } }
    @Published var scrollTrack: Bool { didSet { d.set(scrollTrack, forKey: K.scrollTrack) } }

    // Live activities
    @Published var liveMusic: Bool { didSet { d.set(liveMusic, forKey: K.liveMusic) } }
    @Published var liveVolume: Bool { didSet { d.set(liveVolume, forKey: K.liveVolume) } }
    @Published var liveBrightness: Bool { didSet { d.set(liveBrightness, forKey: K.liveBrightness) } }
    @Published var liveBattery: Bool { didSet { d.set(liveBattery, forKey: K.liveBattery) } }
    @Published var activityDuration: Double { didSet { d.set(activityDuration, forKey: K.activityDuration) } }

    // Módulos
    @Published var enableMusic: Bool { didSet { d.set(enableMusic, forKey: K.enableMusic) } }
    @Published var enableShelf: Bool { didSet { d.set(enableShelf, forKey: K.enableShelf) } }
    @Published var shelfPersists: Bool { didSet { d.set(shelfPersists, forKey: K.shelfPersists) } }
    @Published var use24hClock: Bool { didSet { d.set(use24hClock, forKey: K.use24hClock) } }

    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: K.launchAtLogin) } }

    private enum K {
        static let expandedWidth = "expandedWidth"
        static let expandedHeight = "expandedHeight"
        static let cornerRadius = "cornerRadius"
        static let extraClosedWidth = "extraClosedWidth"
        static let tintedBackground = "tintedBackground"
        static let rimOpacity = "rimOpacity"
        static let rimGlow = "rimGlow"
        static let glassBackground = "glassBackground"
        static let openOnHover = "openOnHover"
        static let hoverOpenDelay = "hoverOpenDelay"
        static let hoverCloseDelay = "hoverCloseDelay"
        static let followMouseScreen = "followMouseScreen"
        static let haptics = "haptics"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let scrollVolume = "scrollVolume"
        static let scrollTrack = "scrollTrack"
        static let liveMusic = "liveMusic"
        static let liveVolume = "liveVolume"
        static let liveBrightness = "liveBrightness"
        static let liveBattery = "liveBattery"
        static let activityDuration = "activityDuration"
        static let enableMusic = "enableMusic"
        static let enableShelf = "enableShelf"
        static let shelfPersists = "shelfPersists"
        static let use24hClock = "use24hClock"
        static let launchAtLogin = "launchAtLogin"
    }

    private init() {
        d.register(defaults: [
            K.expandedWidth: 620.0,
            K.expandedHeight: 200.0,
            K.cornerRadius: 22.0,
            K.extraClosedWidth: 0.0,
            K.tintedBackground: true,
            K.rimOpacity: 0.85,
            K.rimGlow: true,
            K.glassBackground: true,
            K.openOnHover: true,
            K.hoverOpenDelay: 0.18,
            K.hoverCloseDelay: 0.25,
            K.followMouseScreen: true,
            K.haptics: true,
            K.showMenuBarIcon: true,
            K.scrollVolume: true,
            K.scrollTrack: true,
            K.liveMusic: true,
            K.liveVolume: true,
            K.liveBrightness: true,
            K.liveBattery: true,
            K.activityDuration: 2.2,
            K.enableMusic: true,
            K.enableShelf: true,
            K.shelfPersists: true,
            K.use24hClock: true,
            K.launchAtLogin: false
        ])
        expandedWidth = d.double(forKey: K.expandedWidth)
        expandedHeight = d.double(forKey: K.expandedHeight)
        cornerRadius = d.double(forKey: K.cornerRadius)
        extraClosedWidth = d.double(forKey: K.extraClosedWidth)
        tintedBackground = d.bool(forKey: K.tintedBackground)
        rimOpacity = d.double(forKey: K.rimOpacity)
        rimGlow = d.bool(forKey: K.rimGlow)
        glassBackground = d.bool(forKey: K.glassBackground)
        openOnHover = d.bool(forKey: K.openOnHover)
        hoverOpenDelay = d.double(forKey: K.hoverOpenDelay)
        hoverCloseDelay = d.double(forKey: K.hoverCloseDelay)
        followMouseScreen = d.bool(forKey: K.followMouseScreen)
        haptics = d.bool(forKey: K.haptics)
        showMenuBarIcon = d.bool(forKey: K.showMenuBarIcon)
        scrollVolume = d.bool(forKey: K.scrollVolume)
        scrollTrack = d.bool(forKey: K.scrollTrack)
        liveMusic = d.bool(forKey: K.liveMusic)
        liveVolume = d.bool(forKey: K.liveVolume)
        liveBrightness = d.bool(forKey: K.liveBrightness)
        liveBattery = d.bool(forKey: K.liveBattery)
        activityDuration = d.double(forKey: K.activityDuration)
        enableMusic = d.bool(forKey: K.enableMusic)
        enableShelf = d.bool(forKey: K.enableShelf)
        shelfPersists = d.bool(forKey: K.shelfPersists)
        use24hClock = d.bool(forKey: K.use24hClock)
        launchAtLogin = d.bool(forKey: K.launchAtLogin)
    }

    func resetToDefaults() {
        for key in [K.expandedWidth, K.expandedHeight, K.cornerRadius, K.extraClosedWidth,
                    K.tintedBackground, K.rimOpacity, K.rimGlow, K.glassBackground, K.openOnHover, K.hoverOpenDelay, K.hoverCloseDelay,
                    K.followMouseScreen, K.haptics, K.showMenuBarIcon, K.scrollVolume, K.scrollTrack,
                    K.liveMusic, K.liveVolume, K.liveBrightness, K.liveBattery,
                    K.activityDuration, K.enableMusic, K.enableShelf,
                    K.shelfPersists, K.use24hClock] {
            d.removeObject(forKey: key)
        }
        expandedWidth = d.double(forKey: K.expandedWidth)
        expandedHeight = d.double(forKey: K.expandedHeight)
        cornerRadius = d.double(forKey: K.cornerRadius)
        extraClosedWidth = d.double(forKey: K.extraClosedWidth)
        tintedBackground = d.bool(forKey: K.tintedBackground)
        rimOpacity = d.double(forKey: K.rimOpacity)
        rimGlow = d.bool(forKey: K.rimGlow)
        glassBackground = d.bool(forKey: K.glassBackground)
        openOnHover = d.bool(forKey: K.openOnHover)
        hoverOpenDelay = d.double(forKey: K.hoverOpenDelay)
        hoverCloseDelay = d.double(forKey: K.hoverCloseDelay)
        followMouseScreen = d.bool(forKey: K.followMouseScreen)
        haptics = d.bool(forKey: K.haptics)
        showMenuBarIcon = d.bool(forKey: K.showMenuBarIcon)
        scrollVolume = d.bool(forKey: K.scrollVolume)
        scrollTrack = d.bool(forKey: K.scrollTrack)
        liveMusic = d.bool(forKey: K.liveMusic)
        liveVolume = d.bool(forKey: K.liveVolume)
        liveBrightness = d.bool(forKey: K.liveBrightness)
        liveBattery = d.bool(forKey: K.liveBattery)
        activityDuration = d.double(forKey: K.activityDuration)
        enableMusic = d.bool(forKey: K.enableMusic)
        enableShelf = d.bool(forKey: K.enableShelf)
        shelfPersists = d.bool(forKey: K.shelfPersists)
        use24hClock = d.bool(forKey: K.use24hClock)
    }
}
