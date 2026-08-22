import AppKit
import SwiftUI
import Combine

enum NotchTab: String, CaseIterable, Identifiable {
    case music, shelf, widgets
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .shelf: return "tray.full"
        case .widgets: return "square.grid.2x2"
        }
    }
    var title: String {
        switch self {
        case .music: return "Música"
        case .shelf: return "Repisa"
        case .widgets: return "Widgets"
        }
    }
}

enum LiveActivity: Equatable {
    case music(title: String, subtitle: String, playing: Bool)
    case volume(Float, muted: Bool)
    case brightness(Float)
    case battery(percent: Int, plugged: Bool, charging: Bool)
    case timer(remaining: Int)
    case message(text: String, symbol: String, tint: LiveTint)

    enum LiveTint: Equatable { case accent, green, orange, red }
}

/// Estado de la isla: cerrada, en hover, o abierta.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var isHovering = false
    @Published var isPinned = false
    @Published var tab: NotchTab = IslandDebug.initialTab { didSet { IslandDebug.log("tab -> \(tab.rawValue)") } }
    @Published var activity: LiveActivity?
    @Published var isDropTarget = false
    @Published var metrics: ScreenMetrics

    // Temporizador (widget)
    @Published var timerRemaining: Int = 0
    @Published var timerRunning = false
    private var countdown: Timer?

    private var activityDismiss: Timer?
    let prefs = Prefs.shared

    init(metrics: ScreenMetrics) {
        self.metrics = metrics
    }

    // MARK: - Tamaños

    var notchSize: CGSize { metrics.notchSize }

    var closedSize: CGSize {
        let base = metrics.notchSize
        if let activity, !isOpen {
            let sides = sideWidth(for: activity)
            let height = metrics.hasNotch ? base.height : 30
            return CGSize(width: base.width + sides.0 + sides.1, height: height)
        }
        let idleHeight = metrics.hasNotch ? base.height : 10
        let hoverBump: CGFloat = (isHovering && !isOpen) ? 4 : 0
        return CGSize(width: base.width + prefs.extraClosedWidth, height: idleHeight + hoverBump)
    }

    var openSize: CGSize {
        CGSize(width: prefs.expandedWidth,
               height: prefs.expandedHeight + metrics.notchSize.height)
    }

    var currentSize: CGSize { isOpen ? openSize : closedSize }

    /// Ancho del contenido a cada lado del notch para una live activity.
    static func sideWidths(for activity: LiveActivity) -> (CGFloat, CGFloat) {
        switch activity {
        case .music: return (52, 44)
        case .volume, .brightness: return (34, 78)
        case .battery: return (38, 56)
        case .timer: return (34, 60)
        case .message: return (38, 104)
        }
    }

    private func sideWidth(for activity: LiveActivity) -> (CGFloat, CGFloat) {
        let sides = Self.sideWidths(for: activity)
        // 10pt de padding horizontal a cada lado (ver ClosedView).
        return (sides.0 + 10, sides.1 + 10)
    }

    // MARK: - Apertura

    func open() {
        guard !isOpen else { return }
        isOpen = true
        IslandDebug.log("open (tab: \(tab.rawValue))")
        hideActivityImmediately()
        haptic()
    }

    func close(force: Bool = false) {
        guard isOpen else { return }
        if isPinned && !force { return }
        isOpen = false
        isPinned = false
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

    // MARK: - Temporizador

    func startTimer(seconds: Int) {
        timerRemaining = seconds
        timerRunning = true
        countdown?.invalidate()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickTimer() }
        }
    }

    func toggleTimer() {
        guard timerRemaining > 0 else { return }
        timerRunning.toggle()
    }

    func stopTimer() {
        timerRunning = false
        timerRemaining = 0
        countdown?.invalidate()
        countdown = nil
    }

    private func tickTimer() {
        guard timerRunning, timerRemaining > 0 else { return }
        timerRemaining -= 1
        if timerRemaining == 0 {
            timerRunning = false
            countdown?.invalidate()
            NSSound(named: "Glass")?.play()
            show(.message(text: "Tiempo cumplido", symbol: "timer", tint: .orange), duration: 5)
        }
    }
}

extension Animation {
    /// Resorte tipo Dynamic Island.
    static var island: Animation { .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.2) }
    static var islandFast: Animation { .spring(response: 0.3, dampingFraction: 0.82) }
}
