import AppKit
import SwiftUI
import Combine

/// Coordina la ventana de la isla: posición, hover, gestos y "live activities".
@MainActor
final class NotchController {
    static let shared = NotchController()

    private(set) var panel: NotchPanel?
    let viewModel: NotchViewModel
    private let prefs = Prefs.shared

    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var currentPollRate: Double = 0
    private var lastMouseLocation = CGPoint(x: -1, y: -1)
    private var suppressUntil = Date.distantPast

    /// Margen transparente alrededor del contenido (para sombras y para tener área de hover).
    private let margin: CGFloat = 60
    /// Holgura del área sensible: mínima en reposo (para no invadir la barra
    /// de menús) y algo mayor con la isla abierta.
    private var hoverPadding: CGFloat { viewModel.isOpen ? 14 : 4 }

    private init() {
        let screen = ScreenMetrics.targetScreen(followMouse: Prefs.shared.followMouseScreen)
        viewModel = NotchViewModel(metrics: ScreenMetrics.metrics(for: screen))
    }

    // MARK: - Ciclo de vida

    func start() {
        buildPanel()
        installMonitors()
        observeSystem()
        relayout()
    }

    private func buildPanel() {
        let root = RootView(vm: viewModel)
        let hosting = PassthroughHostingView(rootView: root)
        hosting.isActive = { [weak self] point in self?.isInsideIslandView(point) ?? false }
        let panel = NotchPanel(contentRect: windowFrame())
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private var currentScreen: NSScreen {
        viewModel.metrics.screen
    }

    private func windowSize() -> CGSize {
        let open = viewModel.openSize
        return CGSize(width: max(open.width, viewModel.notchDrawnSize.width) + margin * 2,
                      height: open.height + margin)
    }

    private func windowFrame() -> NSRect {
        let size = windowSize()
        let screen = currentScreen
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Rectángulos activos en coordenadas de PANTALLA.
    /// Cerrada: solo el notch (las alas de las live activities no deben robar
    /// clics a los íconos de la barra de menús).
    /// Abierta: el notch más el panel que cuelga por debajo.
    private var cachedRects: (key: String, rects: [CGRect])?

    private func rectsCacheKey(_ padding: CGFloat) -> String {
        let board = viewModel.boardSize ?? .zero
        return "\(padding)|\(viewModel.notchDrawnSize)|\(board)|\(currentScreen.frame)"
    }

    private func islandRects(padding: CGFloat = 0) -> [CGRect] {
        let key = rectsCacheKey(padding)
        if let cached = cachedRects, cached.key == key { return cached.rects }
        let rects = computeIslandRects(padding: padding)
        cachedRects = (key, rects)
        return rects
    }

    private func computeIslandRects(padding: CGFloat) -> [CGRect] {
        let screen = currentScreen
        // Para el ratón usamos el notch FÍSICO, no el dibujado: así el par de
        // puntos de más que ocupa el contorno no le roba clics a la barra.
        let notch = viewModel.notchSize
        let notchHeight = viewModel.notchDrawnSize.height
        var rects = [CGRect(x: screen.frame.midX - notch.width / 2 - padding,
                            y: screen.frame.maxY - notchHeight - padding,
                            width: notch.width + padding * 2,
                            height: notchHeight + padding)]
        if let board = viewModel.boardSize {
            rects.append(CGRect(x: screen.frame.midX - board.width / 2 - padding,
                                y: screen.frame.maxY - notchHeight - board.height - padding,
                                width: board.width + padding * 2,
                                height: board.height + padding * 2))
        }
        return rects
    }

    private func isInsideIsland(_ point: CGPoint, padding: CGFloat = 0) -> Bool {
        islandRects(padding: padding).contains { $0.contains(point) }
    }

    /// Lo mismo, pero en coordenadas de la vista (origen abajo-izquierda).
    private func isInsideIslandView(_ point: CGPoint) -> Bool {
        guard let panel else { return false }
        let origin = panel.frame.origin
        let screenPoint = CGPoint(x: origin.x + point.x, y: origin.y + point.y)
        return isInsideIsland(screenPoint, padding: viewModel.isOpen ? 2 : 0)
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
        BatteryMonitor.shared.onChange = { [weak self] state, plugChanged in
            guard let self, self.prefs.liveBattery, plugChanged else { return }
            self.viewModel.show(.battery(percent: state.percent, plugged: state.plugged, charging: state.charging),
                                duration: 3)
        }
        MediaManager.shared.onTrackChange = { [weak self] np in
            guard let self, self.prefs.liveMusic, np.isActive else { return }
            self.announceTrack(np)
        }
    }

    /// La carátula llega después del aviso de pista nueva (hay que pedir la URL
    /// y descargarla), así que mostrar la píldora de inmediato la dejaba medio
    /// segundo sin color. Se espera a la portada, con tope: si tarda, sale igual.
    private func announceTrack(_ np: NowPlaying, waited: Double = 0) {
        let hasArtwork = MediaManager.shared.artworkBackdrop != nil
        let timedOut = waited >= 0.8
        guard hasArtwork || timedOut else {
            let step = 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + step) { [weak self] in
                guard let self, MediaManager.shared.info.trackKey == np.trackKey else { return }
                self.announceTrack(np, waited: waited + step)
            }
            return
        }
        viewModel.show(.music(title: np.title,
                              subtitle: np.artist.isEmpty ? np.album : np.artist,
                              playing: np.isPlaying),
                       duration: np.isPlaying ? 3 : 2)
    }

    // MARK: - Monitores de mouse

    private func installMonitors() {
        // El grueso del trabajo es por eventos: solo cuando el mouse se mueve.
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            Task { @MainActor in self?.handleMouseMoved() }
        }) { monitors.append(g) }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
            return event
        } as Any)

        // Y un sondeo de respaldo, porque los monitores globales no reciben
        // nada bajo apps a pantalla completa. Lento salvo cerca del notch.
        setPollRate(idleRate)

        // Cierra al hacer clic fuera de la isla abierta.
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.viewModel.isOpen else { return }
                if !self.isInsideIsland(NSEvent.mouseLocation, padding: self.hoverPadding) {
                    IslandDebug.log("close: clic fuera en \(NSEvent.mouseLocation)")
                    withAnimation(.island) { self.viewModel.close(force: true) }
                }
            }
        }) { monitors.append(g) }
    }

    private let idleRate: Double = 8
    private let activeRate: Double = 30
    /// Margen para volver a entrar sin que la isla se cierre en la cara.
    /// Sale a unos 3 s de reloj: la cuenta arranca cuando el puntero deja el
    /// panel (que cuelga 200 px bajo el notch, así que apartar el mouse ya se
    /// come unas décimas) y después queda la animación de cierre.
    private let hoverCloseDelay: Double = 2.2

    /// Reprograma el sondeo solo cuando cambia el ritmo, para no despertar la
    /// CPU 60 veces por segundo cuando el puntero está lejos del notch.
    private func setPollRate(_ hz: Double) {
        guard currentPollRate != hz else { return }
        currentPollRate = hz
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / hz, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        timer.tolerance = (1.0 / hz) * 0.3
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation
        // Cerca del borde superior conviene reaccionar rápido; lejos, no.
        let nearTop = location.y > currentScreen.frame.maxY - 220
        setPollRate(nearTop || viewModel.isOpen || viewModel.isHovering ? activeRate : idleRate)

        // Camino rápido: con el puntero lejos y la isla en reposo no hay nada
        // que hacer. Este método corre con cada movimiento del mouse.
        if !nearTop, !viewModel.isOpen, !viewModel.isHovering {
            if panel?.ignoresMouseEvents == false { panel?.ignoresMouseEvents = true }
            lastMouseLocation = location
            return
        }

        if location == lastMouseLocation, !viewModel.isOpen, !viewModel.isHovering,
           panel?.ignoresMouseEvents == true { return }
        lastMouseLocation = location
        // Cambia de pantalla si el mouse se fue a otro monitor y la isla está cerrada.
        if prefs.followMouseScreen, !viewModel.isOpen,
           let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }),
           screen != viewModel.metrics.screen {
            viewModel.metrics = ScreenMetrics.metrics(for: screen)
            relayout()
        }

        let inside = isInsideIsland(location, padding: hoverPadding)

        // Clave: `hitTest` solo decide el enrutado dentro de nuestra app; la
        // ventana igual se come el clic. Para que los íconos de la barra de
        // menús sigan siendo pulsables hay que desactivar los eventos de la
        // ventana mientras el puntero no esté sobre la isla.
        let overIsland = isInsideIsland(location, padding: 2)
        if let panel, panel.ignoresMouseEvents == overIsland {
            panel.ignoresMouseEvents = !overIsland
            IslandDebug.log("eventos de la ventana: \(overIsland ? "activos" : "pasan de largo") en \(location)")
        }

        if inside {
            if !viewModel.isHovering {
                withAnimation(.islandFast) { viewModel.isHovering = true }
            }
            // Hay que anularlo, no solo cancelarlo: si se queda un work item
            // muerto aquí, la guarda `closeWork == nil` de abajo no vuelve a
            // pasar nunca y la isla se queda abierta para siempre.
            closeWork?.cancel()
            closeWork = nil
            guard prefs.openOnHover, !viewModel.isOpen, openWork == nil,
                  Date() >= suppressUntil,
                  !(AppDelegate.shared?.settingsVisible ?? false) else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.openWork = nil
                guard self.isInsideIsland(NSEvent.mouseLocation, padding: hoverPadding) else { return }
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
                guard !self.isInsideIsland(NSEvent.mouseLocation, padding: hoverPadding) else { return }
                IslandDebug.log("close: hover fuera en \(NSEvent.mouseLocation)")
                withAnimation(.island) { self.viewModel.close() }
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverCloseDelay, execute: work)
        }
    }

    // MARK: - Acciones públicas

    func toggleOpen() {
        withAnimation(.island) { viewModel.toggle() }
    }

    /// Cierra y desfija la isla para que no tape una ventana de la app.
    func closeForModalWindow() {
        openWork?.cancel(); openWork = nil
        viewModel.isPinned = false
        withAnimation(.island) { viewModel.close(force: true) }
        suppressUntil = Date().addingTimeInterval(1.0)
    }

    func openTab(_ tab: NotchTab) {
        viewModel.tab = tab
        withAnimation(.island) {
            viewModel.open()
            viewModel.isPinned = true
        }
    }

}
