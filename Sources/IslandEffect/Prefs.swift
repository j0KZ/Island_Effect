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

    // Comportamiento
    @Published var openOnHover: Bool { didSet { d.set(openOnHover, forKey: K.openOnHover) } }
    @Published var hoverOpenDelay: Double { didSet { d.set(hoverOpenDelay, forKey: K.hoverOpenDelay) } }
    @Published var hoverCloseDelay: Double { didSet { d.set(hoverCloseDelay, forKey: K.hoverCloseDelay) } }
    @Published var followMouseScreen: Bool { didSet { d.set(followMouseScreen, forKey: K.followMouseScreen) } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: K.haptics) } }

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
    @Published var enableWidgets: Bool { didSet { d.set(enableWidgets, forKey: K.enableWidgets) } }

    // Portapapeles
    @Published var enableClipboard: Bool { didSet { d.set(enableClipboard, forKey: K.enableClipboard) } }
    @Published var clipboardHotKeyEnabled: Bool { didSet { d.set(clipboardHotKeyEnabled, forKey: K.clipboardHotKeyEnabled) } }
    @Published var clipboardHotKeyCode: Int { didSet { d.set(clipboardHotKeyCode, forKey: K.clipboardHotKeyCode) } }
    @Published var clipboardHotKeyMods: Int { didSet { d.set(clipboardHotKeyMods, forKey: K.clipboardHotKeyMods) } }
    @Published var clipboardMaxItems: Double { didSet { d.set(clipboardMaxItems, forKey: K.clipboardMaxItems) } }
    @Published var clipboardPersists: Bool { didSet { d.set(clipboardPersists, forKey: K.clipboardPersists) } }
    @Published var clipboardKeepImages: Bool { didSet { d.set(clipboardKeepImages, forKey: K.clipboardKeepImages) } }
    @Published var clipboardIgnoreConfidential: Bool { didSet { d.set(clipboardIgnoreConfidential, forKey: K.clipboardIgnoreConfidential) } }
    @Published var clipboardAutoPaste: Bool { didSet { d.set(clipboardAutoPaste, forKey: K.clipboardAutoPaste) } }

    var clipboardHotKey: HotKeySpec {
        HotKeySpec(keyCode: clipboardHotKeyCode, modifiers: clipboardHotKeyMods)
    }
    @Published var shelfPersists: Bool { didSet { d.set(shelfPersists, forKey: K.shelfPersists) } }
    @Published var use24hClock: Bool { didSet { d.set(use24hClock, forKey: K.use24hClock) } }

    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: K.launchAtLogin) } }

    private enum K {
        static let expandedWidth = "expandedWidth"
        static let expandedHeight = "expandedHeight"
        static let cornerRadius = "cornerRadius"
        static let extraClosedWidth = "extraClosedWidth"
        static let tintedBackground = "tintedBackground"
        static let openOnHover = "openOnHover"
        static let hoverOpenDelay = "hoverOpenDelay"
        static let hoverCloseDelay = "hoverCloseDelay"
        static let followMouseScreen = "followMouseScreen"
        static let haptics = "haptics"
        static let scrollVolume = "scrollVolume"
        static let scrollTrack = "scrollTrack"
        static let liveMusic = "liveMusic"
        static let liveVolume = "liveVolume"
        static let liveBrightness = "liveBrightness"
        static let liveBattery = "liveBattery"
        static let activityDuration = "activityDuration"
        static let enableMusic = "enableMusic"
        static let enableShelf = "enableShelf"
        static let enableWidgets = "enableWidgets"
        static let enableClipboard = "enableClipboard"
        static let clipboardHotKeyEnabled = "clipboardHotKeyEnabled"
        static let clipboardHotKeyCode = "clipboardHotKeyCode"
        static let clipboardHotKeyMods = "clipboardHotKeyMods"
        static let clipboardMaxItems = "clipboardMaxItems"
        static let clipboardPersists = "clipboardPersists"
        static let clipboardKeepImages = "clipboardKeepImages"
        static let clipboardIgnoreConfidential = "clipboardIgnoreConfidential"
        static let clipboardAutoPaste = "clipboardAutoPaste"
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
            K.openOnHover: true,
            K.hoverOpenDelay: 0.18,
            K.hoverCloseDelay: 0.25,
            K.followMouseScreen: true,
            K.haptics: true,
            K.scrollVolume: true,
            K.scrollTrack: true,
            K.liveMusic: true,
            K.liveVolume: true,
            K.liveBrightness: true,
            K.liveBattery: true,
            K.activityDuration: 2.2,
            K.enableMusic: true,
            K.enableShelf: true,
            K.enableWidgets: true,
            K.enableClipboard: true,
            K.clipboardHotKeyEnabled: true,
            K.clipboardHotKeyCode: HotKeySpec.defaultClipboard.keyCode,
            K.clipboardHotKeyMods: HotKeySpec.defaultClipboard.modifiers,
            K.clipboardMaxItems: 60.0,
            K.clipboardPersists: true,
            K.clipboardKeepImages: true,
            K.clipboardIgnoreConfidential: true,
            K.clipboardAutoPaste: true,
            K.shelfPersists: true,
            K.use24hClock: true,
            K.launchAtLogin: false
        ])
        expandedWidth = d.double(forKey: K.expandedWidth)
        expandedHeight = d.double(forKey: K.expandedHeight)
        cornerRadius = d.double(forKey: K.cornerRadius)
        extraClosedWidth = d.double(forKey: K.extraClosedWidth)
        tintedBackground = d.bool(forKey: K.tintedBackground)
        openOnHover = d.bool(forKey: K.openOnHover)
        hoverOpenDelay = d.double(forKey: K.hoverOpenDelay)
        hoverCloseDelay = d.double(forKey: K.hoverCloseDelay)
        followMouseScreen = d.bool(forKey: K.followMouseScreen)
        haptics = d.bool(forKey: K.haptics)
        scrollVolume = d.bool(forKey: K.scrollVolume)
        scrollTrack = d.bool(forKey: K.scrollTrack)
        liveMusic = d.bool(forKey: K.liveMusic)
        liveVolume = d.bool(forKey: K.liveVolume)
        liveBrightness = d.bool(forKey: K.liveBrightness)
        liveBattery = d.bool(forKey: K.liveBattery)
        activityDuration = d.double(forKey: K.activityDuration)
        enableMusic = d.bool(forKey: K.enableMusic)
        enableShelf = d.bool(forKey: K.enableShelf)
        enableWidgets = d.bool(forKey: K.enableWidgets)
        enableClipboard = d.bool(forKey: K.enableClipboard)
        clipboardHotKeyEnabled = d.bool(forKey: K.clipboardHotKeyEnabled)
        clipboardHotKeyCode = d.integer(forKey: K.clipboardHotKeyCode)
        clipboardHotKeyMods = d.integer(forKey: K.clipboardHotKeyMods)
        clipboardMaxItems = d.double(forKey: K.clipboardMaxItems)
        clipboardPersists = d.bool(forKey: K.clipboardPersists)
        clipboardKeepImages = d.bool(forKey: K.clipboardKeepImages)
        clipboardIgnoreConfidential = d.bool(forKey: K.clipboardIgnoreConfidential)
        clipboardAutoPaste = d.bool(forKey: K.clipboardAutoPaste)
        shelfPersists = d.bool(forKey: K.shelfPersists)
        use24hClock = d.bool(forKey: K.use24hClock)
        launchAtLogin = d.bool(forKey: K.launchAtLogin)
    }

    func resetToDefaults() {
        for key in [K.expandedWidth, K.expandedHeight, K.cornerRadius, K.extraClosedWidth,
                    K.tintedBackground, K.openOnHover, K.hoverOpenDelay, K.hoverCloseDelay,
                    K.followMouseScreen, K.haptics, K.scrollVolume, K.scrollTrack,
                    K.liveMusic, K.liveVolume, K.liveBrightness, K.liveBattery,
                    K.activityDuration, K.enableMusic, K.enableShelf, K.enableWidgets,
                    K.enableClipboard, K.clipboardHotKeyEnabled, K.clipboardHotKeyCode,
                    K.clipboardHotKeyMods, K.clipboardMaxItems, K.clipboardPersists,
                    K.clipboardKeepImages, K.clipboardIgnoreConfidential, K.clipboardAutoPaste,
                    K.shelfPersists, K.use24hClock] {
            d.removeObject(forKey: key)
        }
        expandedWidth = d.double(forKey: K.expandedWidth)
        expandedHeight = d.double(forKey: K.expandedHeight)
        cornerRadius = d.double(forKey: K.cornerRadius)
        extraClosedWidth = d.double(forKey: K.extraClosedWidth)
        tintedBackground = d.bool(forKey: K.tintedBackground)
        openOnHover = d.bool(forKey: K.openOnHover)
        hoverOpenDelay = d.double(forKey: K.hoverOpenDelay)
        hoverCloseDelay = d.double(forKey: K.hoverCloseDelay)
        followMouseScreen = d.bool(forKey: K.followMouseScreen)
        haptics = d.bool(forKey: K.haptics)
        scrollVolume = d.bool(forKey: K.scrollVolume)
        scrollTrack = d.bool(forKey: K.scrollTrack)
        liveMusic = d.bool(forKey: K.liveMusic)
        liveVolume = d.bool(forKey: K.liveVolume)
        liveBrightness = d.bool(forKey: K.liveBrightness)
        liveBattery = d.bool(forKey: K.liveBattery)
        activityDuration = d.double(forKey: K.activityDuration)
        enableMusic = d.bool(forKey: K.enableMusic)
        enableShelf = d.bool(forKey: K.enableShelf)
        enableWidgets = d.bool(forKey: K.enableWidgets)
        enableClipboard = d.bool(forKey: K.enableClipboard)
        clipboardHotKeyEnabled = d.bool(forKey: K.clipboardHotKeyEnabled)
        clipboardHotKeyCode = d.integer(forKey: K.clipboardHotKeyCode)
        clipboardHotKeyMods = d.integer(forKey: K.clipboardHotKeyMods)
        clipboardMaxItems = d.double(forKey: K.clipboardMaxItems)
        clipboardPersists = d.bool(forKey: K.clipboardPersists)
        clipboardKeepImages = d.bool(forKey: K.clipboardKeepImages)
        clipboardIgnoreConfidential = d.bool(forKey: K.clipboardIgnoreConfidential)
        clipboardAutoPaste = d.bool(forKey: K.clipboardAutoPaste)
        shelfPersists = d.bool(forKey: K.shelfPersists)
        use24hClock = d.bool(forKey: K.use24hClock)
    }
}
