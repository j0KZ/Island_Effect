import AppKit
import SwiftUI
import Combine

/// Coordina la ventana de la isla: posición, hover, gestos y "live activities".
@MainActor
final class NotchController {
    static let shared = NotchController()

    private(set) var panel: NotchPanel?
    private var hostingView: PassthroughHostingView<RootView>?
    let viewModel: NotchViewModel
    private let prefs = Prefs.shared

    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var lastMouseLocation = CGPoint(x: -1, y: -1)
    private var lastScrollAt = Date.distantPast
    private var scrollAccumulator: CGFloat = 0

    /// App que tenía el foco antes de abrir el portapapeles, para devolvérselo al pegar.
    private var previousApp: NSRunningApplication?
    private var clipboardHotKey: GlobalHotKey?

    /// Margen transparente alrededor del contenido (para sombras y para tener área de hover).
    private let margin: CGFloat = 60

    private init() {
        let screen = ScreenMetrics.targetScreen(followMouse: Prefs.shared.followMouseScreen)
        viewModel = NotchViewModel(metrics: ScreenMetrics.metrics(for: screen))
    }

    // MARK: - Ciclo de vida

    func start() {
        buildPanel()
        installMonitors()
        observeSystem()
        registerClipboardHotKey()
        relayout()
    }

    private func buildPanel() {
        let root = RootView(vm: viewModel)
        let hosting = PassthroughHostingView(rootView: root)
        hosting.activeRect = { [weak self] in self?.activeRectInView() ?? .zero }
        let panel = NotchPanel(contentRect: windowFrame())
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hosting
    }

    private var currentScreen: NSScreen {
        viewModel.metrics.screen
    }

    private func windowSize() -> CGSize {
        let open = viewModel.openSize
        let closed = viewModel.closedSize
        return CGSize(width: max(open.width, closed.width, viewModel.notchSize.width) + margin * 2,
                      height: open.height + margin)
    }

    private func windowFrame() -> NSRect {
        let size = windowSize()
        let screen = currentScreen
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Área interactiva (en coordenadas de la vista) según el estado actual.
    private func activeRectInView() -> CGRect {
        guard let panel else { return .zero }
        let size = viewModel.currentSize
        let bounds = panel.contentView?.bounds ?? .zero
        let padding: CGFloat = viewModel.isOpen ? 10 : 2
        return CGRect(x: (bounds.width - size.width) / 2 - padding,
                      y: bounds.height - size.height - padding,
                      width: size.width + padding * 2,
                      height: size.height + padding)
    }

    /// Área de la isla en coordenadas de pantalla.
    private func activeRectOnScreen(expandBy: CGFloat = 0) -> CGRect {
        let size = viewModel.currentSize
        let screen = currentScreen
        return CGRect(x: screen.frame.midX - size.width / 2 - expandBy,
                      y: screen.frame.maxY - size.height - expandBy,
                      width: size.width + expandBy * 2,
                      height: size.height + expandBy)
    }

    /// Zona sensible al hover cuando la isla está cerrada (un poco más generosa que el notch).
    private func hoverRectOnScreen() -> CGRect {
        if viewModel.isOpen { return activeRectOnScreen(expandBy: 18) }
        let size = viewModel.closedSize
        let screen = currentScreen
        let extra: CGFloat = 6
        return CGRect(x: screen.frame.midX - size.width / 2 - extra,
                      y: screen.frame.maxY - max(size.height, 12) - extra,
                      width: size.width + extra * 2,
                      height: max(size.height, 12) + extra)
    }

    func relayout() {
        guard let panel else { return }
        let screen = ScreenMetrics.targetScreen(followMouse: prefs.followMouseScreen)
        if screen != viewModel.metrics.screen {
            viewModel.metrics = ScreenMetrics.metrics(for: screen)
        }
        let frame = windowFrame()
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
        }
        panel.orderFrontRegardless()
    }

    // MARK: - Observadores del sistema

    private func observeSystem() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in
                let screen = ScreenMetrics.targetScreen(followMouse: Prefs.shared.followMouseScreen)
                NotchController.shared.viewModel.metrics = ScreenMetrics.metrics(for: screen)
                NotchController.shared.relayout()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in NotchController.shared.relayout() }
        }

        prefs.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)

        // Live activities
        VolumeMonitor.shared.onChange = { [weak self] value, muted in
            guard let self, self.prefs.liveVolume else { return }
            self.viewModel.show(.volume(value, muted: muted), duration: 1.6)
        }
        BrightnessMonitor.shared.onChange = { [weak self] value in
            guard let self, self.prefs.liveBrightness else { return }
            self.viewModel.show(.brightness(value), duration: 1.6)
        }
        BatteryMonitor.shared.onChange = { [weak self] state, plugChanged in
            guard let self, self.prefs.liveBattery, plugChanged else { return }
            self.viewModel.show(.battery(percent: state.percent, plugged: state.plugged, charging: state.charging),
                                duration: 3)
        }
        MediaManager.shared.onTrackChange = { [weak self] np in
            guard let self, self.prefs.liveMusic, np.isActive else { return }
            self.viewModel.show(.music(title: np.title,
                                       subtitle: np.artist.isEmpty ? np.album : np.artist,
                                       playing: np.isPlaying),
                                duration: np.isPlaying ? 3 : 2)
        }
    }

    // MARK: - Monitores de mouse

    private func installMonitors() {
        // Sondeo de la posición del puntero: es lo único fiable cuando hay apps
        // en pantalla completa o que capturan los eventos globales.
        let poll = Timer(timeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        poll.tolerance = 0.01
        RunLoop.main.add(poll, forMode: .common)
        hoverTimer = poll

        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] event in
            Task { @MainActor in self?.handleScroll(event) }
        }) { monitors.append(g) }

        // Cierra al hacer clic fuera de la isla abierta.
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.viewModel.isOpen else { return }
                if !self.hoverRectOnScreen().contains(NSEvent.mouseLocation) {
                    IslandDebug.log("close: clic fuera en \(NSEvent.mouseLocation) rect \(self.hoverRectOnScreen())")
                    if self.viewModel.tab == .clipboard {
                        self.dismissClipboard(pasting: false)
                    } else {
                        withAnimation(.island) { self.viewModel.close(force: true) }
                    }
                } else {
                    IslandDebug.log("clic dentro en \(NSEvent.mouseLocation)")
                }
            }
        }) { monitors.append(g) }
    }

    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation
        if location == lastMouseLocation, !viewModel.isOpen, !viewModel.isHovering { return }
        lastMouseLocation = location
        // Cambia de pantalla si el mouse se fue a otro monitor y la isla está cerrada.
        if prefs.followMouseScreen, !viewModel.isOpen,
           let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }),
           screen != viewModel.metrics.screen {
            viewModel.metrics = ScreenMetrics.metrics(for: screen)
            relayout()
        }

        let inside = hoverRectOnScreen().contains(location)
        if inside {
            if !viewModel.isHovering {
                withAnimation(.islandFast) { viewModel.isHovering = true }
            }
            closeWork?.cancel()
            guard prefs.openOnHover, !viewModel.isOpen, openWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.openWork = nil
                guard self.hoverRectOnScreen().contains(NSEvent.mouseLocation) else { return }
                withAnimation(.island) { self.viewModel.open() }
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + prefs.hoverOpenDelay, execute: work)
        } else {
            openWork?.cancel()
            openWork = nil
            if viewModel.isHovering {
                withAnimation(.islandFast) { viewModel.isHovering = false }
            }
            guard viewModel.isOpen, !viewModel.isPinned, closeWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.closeWork = nil
                guard !self.hoverRectOnScreen().contains(NSEvent.mouseLocation) else { return }
                IslandDebug.log("close: hover fuera en \(NSEvent.mouseLocation) rect \(self.hoverRectOnScreen())")
                withAnimation(.island) { self.viewModel.close() }
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + prefs.hoverCloseDelay, execute: work)
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard !viewModel.isOpen else { return }
        guard hoverRectOnScreen().contains(NSEvent.mouseLocation) else { return }

        let dy = event.scrollingDeltaY
        let dx = event.scrollingDeltaX

        if prefs.scrollVolume, abs(dy) > abs(dx), abs(dy) > 0.05 {
            let step = Float(dy) * (event.hasPreciseScrollingDeltas ? 0.004 : 0.03)
            let target = VolumeMonitor.shared.readVolume() + step
            VolumeMonitor.shared.setVolume(target)
            viewModel.show(.volume(VolumeMonitor.shared.readVolume(),
                                   muted: VolumeMonitor.shared.readMuted()), duration: 1.4)
            return
        }

        if prefs.scrollTrack, abs(dx) > abs(dy), abs(dx) > 0.5 {
            scrollAccumulator += dx
            guard Date().timeIntervalSince(lastScrollAt) > 0.6, abs(scrollAccumulator) > 28 else { return }
            lastScrollAt = Date()
            let forward = scrollAccumulator < 0
            scrollAccumulator = 0
            guard MediaManager.shared.info.isActive else { return }
            if forward { MediaManager.shared.next() } else { MediaManager.shared.previous() }
        }
    }

    // MARK: - Acciones públicas

    func toggleOpen() {
        withAnimation(.island) { viewModel.toggle() }
    }

    func openTab(_ tab: NotchTab) {
        viewModel.tab = tab
        withAnimation(.island) {
            viewModel.open()
            viewModel.isPinned = true
        }
    }

    // MARK: - Portapapeles

    /// Registra (o vuelve a registrar) el atajo global que abre el historial.
    func registerClipboardHotKey() {
        clipboardHotKey = nil
        let spec = prefs.clipboardHotKey
        guard prefs.enableClipboard, prefs.clipboardHotKeyEnabled, spec.isValid else { return }
        clipboardHotKey = GlobalHotKey(spec: spec) {
            Task { @MainActor in NotchController.shared.toggleClipboard() }
        }
        IslandDebug.log("atajo del portapapeles: \(spec.display)")
    }

    func toggleClipboard() {
        if viewModel.isOpen && viewModel.tab == .clipboard {
            dismissClipboard(pasting: false)
        } else {
            openClipboard()
        }
    }

    func openClipboard() {
        previousApp = NSWorkspace.shared.frontmostApplication
        ClipboardStore.shared.query = ""
        ClipboardStore.shared.selection = 0
        openTab(.clipboard)
        grabKeyboard()
    }

    /// La vista del portapapeles avisa que necesita teclado (por ejemplo si llegaste con el mouse).
    func prepareClipboard() {
        if previousApp == nil {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        }
        grabKeyboard()
    }

    private func grabKeyboard() {
        guard let panel else { return }
        panel.setWantsKeyboard(true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func releaseKeyboard() {
        panel?.setWantsKeyboard(false)
    }

    /// Cierra la isla, devuelve el foco a la app anterior y (si corresponde) manda un ⌘V.
    func dismissClipboard(pasting: Bool) {
        let target = previousApp
        previousApp = nil
        releaseKeyboard()
        withAnimation(.island) {
            viewModel.isPinned = false
            viewModel.close(force: true)
        }
        panel?.resignKey()

        if let target, target.bundleIdentifier != Bundle.main.bundleIdentifier {
            target.activate()
        } else {
            NSApp.deactivate()
        }

        guard pasting, Paster.isTrusted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            Paster.pressCommandV()
        }
    }
}
