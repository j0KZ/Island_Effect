import AppKit
import SwiftUI
import Combine

enum NotchTab: String, CaseIterable, Identifiable {
    case music, shelf
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .shelf: return "tray.full"
        }
    }
    var title: String {
        switch self {
        case .music: return String(localized: "Music")
        case .shelf: return String(localized: "Shelf")
        }
    }
}

enum LiveActivity: Equatable {
    case music(title: String, subtitle: String, playing: Bool)
    case battery(percent: Int, plugged: Bool, charging: Bool)

}

/// Estado de la isla: cerrada, en hover, o abierta.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var isHovering = false
    @Published var isPinned = false
    @Published var tab: NotchTab = IslandDebug.initialTab { didSet { IslandDebug.log("tab -> \(tab.rawValue)") } }
    @Published var activity: LiveActivity?
    @Published var metrics: ScreenMetrics

    private var activityDismiss: Timer?
    let prefs = Prefs.shared

    init(metrics: ScreenMetrics) {
        self.metrics = metrics
    }

    // MARK: - Tamaños

    /// Radio de las esquinas superiores invertidas.
    static let topRadius: CGFloat = 8

    /// Tamaño físico del notch (recorte de la pantalla, sin píxeles dentro).
    var notchSize: CGSize { metrics.notchSize }

    /// Tamaño con el que se DIBUJA la columna del notch. Va un poco más ancha
    /// que el recorte: los lados de la forma quedan hundidos `topRadius` hacia
    /// dentro, y si no la ensanchamos el contorno cae dentro del recorte, donde
    /// no hay píxeles y no se ve nada.
    var notchDrawnSize: CGSize {
        let bump: CGFloat = (isHovering && !isOpen && activity == nil) ? 4 : 0
        let height = metrics.hasNotch ? notchSize.height : 10
        return CGSize(width: notchSize.width + 2 * (Self.topRadius + 1) + prefs.extraClosedWidth,
                      height: height + bump)
    }

    /// Panel que cuelga bajo la barra de menús: grande al abrir, mínimo para
    /// una live activity, inexistente en reposo.
    var boardSize: CGSize? {
        if isOpen {
            return CGSize(width: prefs.expandedWidth, height: prefs.expandedHeight)
        }
        if let activity {
            return Self.activitySize(for: activity)
        }
        return nil
    }

    /// Píldora discreta bajo el notch. El ancho se ajusta al texto: con un
    /// ancho fijo los títulos largos quedaban cortados a media palabra.
    static func activitySize(for activity: LiveActivity) -> CGSize {
        switch activity {
        case .music(let title, let subtitle, _):
            let text = max(textWidth(title, size: 11, weight: .semibold),
                           textWidth(subtitle, size: 9.5, weight: .regular))
            // 20 de márgenes + 24 carátula + 40 (ecualizador y tiempo) + huecos
            return CGSize(width: clampWidth(122 + text), height: 48)
        case .battery(let percent, let plugged, let charging):
            let label = charging ? "Charging" : (plugged ? "Plugged in" : "On battery")
            let text = textWidth(label, size: 11, weight: .medium)
                + textWidth(" \(percent) %", size: 11, weight: .semibold)
            return CGSize(width: clampWidth(86 + text), height: 30)
        }
    }

    /// Ancho de un texto con la fuente del sistema, para dimensionar la píldora.
    private static func textWidth(_ string: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Nunca más angosta que la columna del notch (el filete se invertiría) ni
    /// tan ancha que invada media pantalla.
    private static func clampWidth(_ width: CGFloat) -> CGFloat {
        min(460, max(264, width))
    }

    var currentSize: CGSize {
        let notch = notchDrawnSize
        let board = boardSize
        return CGSize(width: max(notch.width, board?.width ?? 0),
                      height: notch.height + (board?.height ?? 0))
    }

    var openSize: CGSize {
        CGSize(width: prefs.expandedWidth,
               height: prefs.expandedHeight + notchSize.height)
    }

    // MARK: - Apertura

    func open() {
        guard !isOpen else { return }
        isOpen = true
        MediaManager.shared.setNeedsProgress(true)
        IslandDebug.log("open (tab: \(tab.rawValue))")
        hideActivityImmediately()
        haptic()
    }

    func close(force: Bool = false) {
        guard isOpen else { return }
        if isPinned && !force { return }
        isOpen = false
        isPinned = false
        MediaManager.shared.setNeedsProgress(false)
        IslandDebug.log("close")
        haptic()
    }

    func toggle() {
        if isOpen { isPinned = false; close(force: true) } else { open(); isPinned = true }
    }

    private func haptic() {
        guard prefs.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: - Live activities

    func show(_ activity: LiveActivity, duration: Double? = nil) {
        guard !isOpen else { return }
        IslandDebug.log("activity: \(activity)")
        self.activity = activity
        activityDismiss?.invalidate()
        let seconds = duration ?? prefs.activityDuration
        activityDismiss = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismissActivity(activity) }
        }
    }

    private func dismissActivity(_ which: LiveActivity) {
        guard activity == which else { return }
        withAnimation(.island) { activity = nil }
    }

    func hideActivityImmediately() {
        activityDismiss?.invalidate()
        activity = nil
    }
}

extension Animation {
    /// Resorte tipo Dynamic Island.
    static var island: Animation { .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.2) }
    static var islandFast: Animation { .spring(response: 0.3, dampingFraction: 0.82) }
}
