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
    @Published var activityDuration: Double { didSet { d.set(activityDuration, forKey: K.activityDuration) } }

    // Módulos
    @Published var enableMusic: Bool { didSet { d.set(enableMusic, forKey: K.enableMusic) } }
    @Published var enableShelf: Bool { didSet { d.set(enableShelf, forKey: K.enableShelf) } }
    @Published var useAppleMusic: Bool { didSet { d.set(useAppleMusic, forKey: K.useAppleMusic) } }
    @Published var useSpotify: Bool { didSet { d.set(useSpotify, forKey: K.useSpotify) } }

    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: K.launchAtLogin) } }

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
        static let activityDuration = "activityDuration"
        static let enableMusic = "enableMusic"
        static let enableShelf = "enableShelf"
        static let useAppleMusic = "useAppleMusic"
        static let useSpotify = "useSpotify"
        static let launchAtLogin = "launchAtLogin"
    }

    private init() {
        d.register(defaults: [
            K.expandedWidth: 620.0,
            K.expandedHeight: 200.0,
            K.cornerRadius: 22.0,
            K.extraClosedWidth: 0.0,
            K.rimOpacity: 0.85,
            K.openOnHover: true,
            K.hoverOpenDelay: 0.12,
            K.followMouseScreen: true,
            K.haptics: true,
            K.showMenuBarIcon: true,
            K.liveMusic: true,
            K.liveBattery: true,
            K.activityDuration: 2.2,
            K.enableMusic: true,
            K.enableShelf: true,
            K.useAppleMusic: true,
            K.useSpotify: true,
            K.launchAtLogin: false
        ])
        expandedWidth = d.double(forKey: K.expandedWidth)
        expandedHeight = d.double(forKey: K.expandedHeight)
        cornerRadius = d.double(forKey: K.cornerRadius)
        extraClosedWidth = d.double(forKey: K.extraClosedWidth)
        rimOpacity = d.double(forKey: K.rimOpacity)
        openOnHover = d.bool(forKey: K.openOnHover)
        hoverOpenDelay = d.double(forKey: K.hoverOpenDelay)
        followMouseScreen = d.bool(forKey: K.followMouseScreen)
        haptics = d.bool(forKey: K.haptics)
        showMenuBarIcon = d.bool(forKey: K.showMenuBarIcon)
        liveMusic = d.bool(forKey: K.liveMusic)
        liveBattery = d.bool(forKey: K.liveBattery)
        activityDuration = d.double(forKey: K.activityDuration)
        enableMusic = d.bool(forKey: K.enableMusic)
        enableShelf = d.bool(forKey: K.enableShelf)
        useAppleMusic = d.bool(forKey: K.useAppleMusic)
        useSpotify = d.bool(forKey: K.useSpotify)
        launchAtLogin = d.bool(forKey: K.launchAtLogin)
    }

    func resetToDefaults() {
        for key in [K.expandedWidth, K.expandedHeight, K.cornerRadius, K.extraClosedWidth,
                    K.rimOpacity, K.openOnHover, K.hoverOpenDelay,
                    K.followMouseScreen, K.haptics, K.showMenuBarIcon,
                    K.liveMusic, K.liveBattery, K.activityDuration,
                    K.enableMusic, K.enableShelf, K.useAppleMusic, K.useSpotify] {
            d.removeObject(forKey: key)
        }
        expandedWidth = d.double(forKey: K.expandedWidth)
        expandedHeight = d.double(forKey: K.expandedHeight)
        cornerRadius = d.double(forKey: K.cornerRadius)
        extraClosedWidth = d.double(forKey: K.extraClosedWidth)
        rimOpacity = d.double(forKey: K.rimOpacity)
        openOnHover = d.bool(forKey: K.openOnHover)
        hoverOpenDelay = d.double(forKey: K.hoverOpenDelay)
        followMouseScreen = d.bool(forKey: K.followMouseScreen)
        haptics = d.bool(forKey: K.haptics)
        showMenuBarIcon = d.bool(forKey: K.showMenuBarIcon)
        liveMusic = d.bool(forKey: K.liveMusic)
        liveBattery = d.bool(forKey: K.liveBattery)
        activityDuration = d.double(forKey: K.activityDuration)
        enableMusic = d.bool(forKey: K.enableMusic)
        enableShelf = d.bool(forKey: K.enableShelf)
        useAppleMusic = d.bool(forKey: K.useAppleMusic)
        useSpotify = d.bool(forKey: K.useSpotify)
    }
}
