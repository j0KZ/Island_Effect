import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject private var media = MediaManager.shared
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.all)
    }

    private var size: CGSize { vm.currentSize }

    private var island: some View {
        ZStack(alignment: .top) {
            background
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(dropTargeted && !vm.isOpen ? 1.04 : 1, anchor: .top)
        .animation(.island, value: vm.isOpen)
        // Los avisos entran con un resorte más corto: cada fotograma de esa
        // transición vuelve a renderizar el vidrio, y es lo más caro que hace
        // la app. Menos rebote, menos fotogramas.
        .animation(.islandFast, value: vm.activity)
        .animation(.islandFast, value: vm.isHovering)
        .animation(.islandFast, value: dropTargeted)
        .contentShape(shape)
        // Solo el estado cerrado responde al clic: cuando está abierta, los clics
        // pertenecen a los controles de adentro.
        .onTapGesture {
            IslandDebug.log("tap on island (open: \(vm.isOpen))")
            guard !vm.isOpen else { return }
            NotchController.shared.toggleOpen()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .onChange(of: dropTargeted) { _, targeted in
            guard prefs.enableShelf else { return }
            if targeted {
                vm.tab = .shelf
                withAnimation(.island) { vm.open() }
            }
        }
    }

    /// Una sola forma para los dos estados: cerrada es el notch; abierta, el
    /// notch más el panel que cuelga bajo la barra de menús.
    private var shape: IslandShape {
        IslandShape(notchWidth: vm.notchDrawnSize.width,
                    notchHeight: vm.notchDrawnSize.height,
                    boardHeight: vm.boardSize?.height ?? 0,
                    topRadius: NotchViewModel.topRadius,
                    notchBottomRadius: vm.metrics.hasNotch ? 10 : 6,
                    boardRadius: vm.isOpen ? prefs.cornerRadius : 14,
                    fillet: vm.isOpen ? 16 : 10)
    }

    private var background: some View {
        let shape = self.shape
        return ZStack {
            if useGlass {
                if #available(macOS 26.0, *) {
                    // Liquid Glass del sistema: lente en los bordes, reflejo
                    // especular y tinte, en vez de imitarlo a mano.
                    Color.clear
                        .glassEffect(.regular.tint(glassTint), in: shape)
                    shape.fill(Color.black.opacity(0.10))
                } else {
                    GlassBackground(material: .hudWindow)
                        .clipShape(shape)
                    shape.fill(Color.black.opacity(0.18))
                }
            } else {
                shape.fill(Color.black)
            }

            // Lavado de color con la portada: el panel se mimetiza con lo que
            // suena en vez de quedar gris.
            if useGlass, let backdrop = media.artworkBackdrop {
                // Con marco explícito: un `aspectRatio(.fill)` suelto dentro del
                // ZStack lo hace crecer sin límite y se lleva por delante todo
                // el render de la isla.
                Image(nsImage: backdrop)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .saturation(1.9)
                    .opacity(0.68)
                    .clipShape(shape)
                shape.fill(Color.black.opacity(0.32))
            }

            shape.fill(
                LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
            )

            // Los desenfoques del contorno se rasterizan en una sola textura:
            // recalcularlos en cada fotograma disparaba la CPU al animar.
            // (El vidrio queda fuera del drawingGroup: no sobrevive a él.)
            rim(shape: shape)
                .drawingGroup()
        }
        .shadow(color: .black.opacity(vm.isOpen ? 0.6 : (vm.activity != nil ? 0.25 : 0)),
                radius: vm.isOpen ? 22 : 6, x: 0, y: vm.isOpen ? 10 : 3)
        .animation(.easeOut(duration: 0.18), value: rimStrength)
    }

    private func rim(shape: IslandShape) -> some View {
        ZStack {
            // Halo exterior difuso: lo que hace que la isla se ubique de un vistazo.
            shape.stroke(rimGradient, lineWidth: 3.4)
                .blur(radius: 3.2)
                .opacity(rimStrength * 0.6)

            // Borde especular nítido, todo el contorno.
            shape.stroke(rimGradient, lineWidth: 1.4)
                .opacity(rimStrength)

            // Grosor del vidrio: un realce discreto en el canto inferior.
            shape.stroke(Color.white.opacity(0.5), lineWidth: 2.0)
                .blur(radius: 2)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom))
                .opacity(rimStrength * 0.45)

            // Refracción cromática apenas insinuada en los extremos.
            shape.stroke(rimTint, lineWidth: 1.4)
                .opacity(rimStrength * 0.32)
                .blendMode(.plusLighter)
        }
    }

    /// Vidrio al abrir y en los avisos; en reposo la isla debe fundirse con
    /// el notch, así que ahí va negra.
    private var useGlass: Bool { vm.isOpen || vm.activity != nil }

    /// Tinte tomado de la carátula: es lo que hace que se lea como
    /// "Liquid Glass tinted" y no como un panel oscuro cualquiera.
    private var glassTint: Color {
        (media.artworkTint ?? Color.white).opacity(0.26)
    }

    /// Intensidad del contorno según el estado: siempre visible, un poco más al pasar el mouse.
    private var rimStrength: Double {
        let base = max(0, min(1, prefs.rimOpacity))
        if vm.isOpen { return base }
        if vm.isHovering { return min(1, base * 1.25) }
        return base * 0.9
    }

    /// Blanco especular: tenue arriba, intenso en el borde inferior (luz cenital).
    /// Blanco especular. Antes caía casi a cero arriba y solo se veía el canto
    /// inferior; ahora recorre todo el contorno —incluido el del notch, que es
    /// lo que separa visualmente la cámara del panel— con un realce abajo.
    private var rimGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(0.72), location: 0.00),
            .init(color: .white.opacity(0.62), location: 0.30),
            .init(color: .white.opacity(0.70), location: 0.62),
            .init(color: .white.opacity(0.88), location: 0.88),
            .init(color: .white.opacity(1.00), location: 1.00)
        ], startPoint: .top, endPoint: .bottom)
    }

    private var rimTint: LinearGradient {
        let accent = media.artworkTint
        return LinearGradient(colors: [
            accent ?? Color(red: 0.40, green: 0.78, blue: 1.00),
            .clear,
            .clear,
            accent ?? Color(red: 0.78, green: 0.55, blue: 1.00)
        ], startPoint: .leading, endPoint: .trailing)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            // La fila de la barra de menús queda libre: solo el notch.
            Color.clear.frame(height: vm.notchDrawnSize.height)
            if vm.isOpen {
                OpenView(vm: vm)
                    .frame(height: prefs.expandedHeight)
                    .transition(.opacity)
            } else if let activity = vm.activity {
                ActivityBar(activity: activity, size: NotchViewModel.activitySize(for: activity))
                    .transition(.opacity)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard prefs.enableShelf else { return false }
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            ShelfStore.shared.add(urls: urls)
            vm.tab = .shelf
            withAnimation(.island) {
                vm.open()
                vm.isPinned = true
            }
        }
        return true
    }
}

// MARK: - Live activity: píldora discreta bajo el notch

/// Aviso pequeño colgando debajo del notch. Antes se dibujaba a los lados,
/// donde tapaba los íconos de la barra de menús.
struct ActivityBar: View {
    let activity: LiveActivity
    let size: CGSize
    @ObservedObject private var media = MediaManager.shared
    @State private var elapsed: Double = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isMusic: Bool { if case .music = activity { return true }; return false }
    private var duration: Double { media.info.duration }

    var body: some View {
        HStack(spacing: 8) {
            leading
            text
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(width: size.width, height: size.height)
        .foregroundStyle(.white)
        .overlay(alignment: .bottom) {
            // Cuánto lleva la canción, como la línea de la Dynamic Island.
            if isMusic, duration > 1 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(Color.white.opacity(0.7))
                            .frame(width: geo.size.width * min(1, max(0, elapsed / duration)))
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            }
        }
        .onAppear { elapsed = media.estimatedElapsed }
        .onReceive(ticker) { _ in
            guard isMusic else { return }
            elapsed = media.estimatedElapsed
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch activity {
        case .music:
            ArtworkView(size: 24, corner: 6)
        case .battery(_, let plugged, let charging):
            symbol(charging ? "battery.100.bolt" : (plugged ? "powerplug.fill" : "battery.50"),
                   tint: charging ? .green : .white)
        }
    }

    @ViewBuilder
    private var text: some View {
        switch activity {
        case .music(let title, let subtitle, _):
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        case .battery(let percent, let plugged, let charging):
            Text(charging ? "Charging" : (plugged ? "Plugged in" : "On battery"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .accessibilityValue("\(percent) %")
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity {
        case .music(_, _, let playing):
            VStack(alignment: .trailing, spacing: 2) {
                EqualizerBars(active: playing)
                    .frame(width: 18, height: 11)
                Text(TimeFormat.clock(elapsed))
                    .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .battery(let percent, _, _):
            Text("\(percent) %")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }

    private func symbol(_ name: String, tint: Color = .white) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 16)
    }

}

// MARK: - Estado abierto

struct OpenView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: compact ? 24 : 30)
            Divider().overlay(Color.white.opacity(0.08))
            body(for: currentTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, compact ? 10 : 14)
                .padding(.vertical, compact ? 7 : 12)
        }
        .foregroundStyle(.white)
    }

    /// Con el panel bajo, cabecera y márgenes se encogen para dejarle sitio
    /// al contenido.
    private var compact: Bool { prefs.expandedHeight < 150 }

    /// Si la pestaña activa se desactivó en Preferencias, caemos en la primera
    /// disponible en vez de mostrar algo que ya no existe.
    private var currentTab: NotchTab {
        availableTabs.contains(vm.tab) ? vm.tab : (availableTabs.first ?? .music)
    }

    private var availableTabs: [NotchTab] {
        NotchTab.allCases.filter {
            switch $0 {
            case .music: return prefs.enableMusic
            case .shelf: return prefs.enableShelf
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if availableTabs.count > 1 {
                    ForEach(availableTabs) { tab in
                        TabButton(tab: tab, selected: currentTab == tab) {
                            withAnimation(.islandFast) { vm.tab = tab }
                        }
                    }
                }
                Button {
                    AppDelegate.shared?.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.45))
                .help("Preferences")
            }
            .padding(.trailing, 12)
        }
    }

    @ViewBuilder
    private func body(for tab: NotchTab) -> some View {
        switch tab {
        case .music: MusicView(vm: vm)
        case .shelf: ShelfView(vm: vm)
        }
    }
}

struct TabButton: View {
    let tab: NotchTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.16 : (hovering ? 0.08 : 0)))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : .white.opacity(0.5))
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}
