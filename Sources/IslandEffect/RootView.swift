import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var prefs = Prefs.shared
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
        .animation(.island, value: vm.activity)
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
        IslandShape(notchWidth: vm.isOpen ? vm.notchSize.width : size.width,
                    notchHeight: vm.isOpen ? vm.notchSize.height : size.height,
                    boardHeight: vm.isOpen ? prefs.expandedHeight : 0,
                    topRadius: 8,
                    notchBottomRadius: vm.activity != nil ? 14 : (vm.metrics.hasNotch ? 10 : 6),
                    boardRadius: prefs.cornerRadius,
                    fillet: 16)
    }

    private var background: some View {
        let shape = self.shape
        return ZStack {
            if useGlass {
                // Vidrio real: desenfoca lo que hay detrás, como una isla de verdad.
                GlassBackground(material: .hudWindow)
                    .clipShape(shape)
                shape.fill(Color.black.opacity(0.18))
            } else {
                shape.fill(Color.black)
            }

            if prefs.tintedBackground {
                shape.fill(
                    LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }

            // Halo exterior difuso: lo que hace que la isla se ubique de un vistazo.
            shape.stroke(rimGradient, lineWidth: 3.4)
                .blur(radius: 3.2)
                .opacity(prefs.rimGlow ? rimStrength * 0.6 : 0)

            // Borde especular nítido, todo el contorno.
            shape.stroke(rimGradient, lineWidth: 1.4)
                .opacity(rimStrength)

            // Grosor del vidrio: brillo interior pegado al canto inferior.
            shape.stroke(Color.white.opacity(0.6), lineWidth: 2.2)
                .blur(radius: 2)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom))
                .opacity(rimStrength * 0.8)

            // Refracción cromática apenas insinuada en los extremos.
            shape.stroke(rimTint, lineWidth: 1.4)
                .opacity(rimStrength * 0.32)
                .blendMode(.plusLighter)
        }
        .shadow(color: .black.opacity(vm.isOpen ? 0.6 : (vm.activity != nil ? 0.25 : 0)),
                radius: vm.isOpen ? 22 : 6, x: 0, y: vm.isOpen ? 10 : 3)
        .animation(.easeOut(duration: 0.18), value: rimStrength)
    }

    /// El vidrio solo al abrir: en reposo la isla debe fundirse con el notch.
    private var useGlass: Bool { prefs.glassBackground && vm.isOpen }

    /// Intensidad del contorno según el estado: siempre visible, un poco más al pasar el mouse.
    private var rimStrength: Double {
        let base = max(0, min(1, prefs.rimOpacity))
        if vm.isOpen { return base }
        if vm.isHovering { return min(1, base * 1.25) }
        return base * 0.9
    }

    /// Blanco especular: tenue arriba, intenso en el borde inferior (luz cenital).
    private var rimGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(0.45), location: 0.00),
            .init(color: .white.opacity(0.28), location: 0.28),
            .init(color: .white.opacity(0.70), location: 0.72),
            .init(color: .white.opacity(1.00), location: 1.00)
        ], startPoint: .top, endPoint: .bottom)
    }

    private var rimTint: LinearGradient {
        LinearGradient(colors: [
            Color(red: 0.40, green: 0.78, blue: 1.00),
            .clear,
            .clear,
            Color(red: 0.78, green: 0.55, blue: 1.00)
        ], startPoint: .leading, endPoint: .trailing)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isOpen {
            VStack(spacing: 0) {
                // La fila de la barra de menús queda libre: solo el notch.
                Color.clear.frame(height: vm.notchSize.height)
                OpenView(vm: vm)
                    .frame(height: prefs.expandedHeight)
            }
            .transition(.opacity)
        } else {
            ClosedView(vm: vm)
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

// MARK: - Estado cerrado (live activities)

struct ClosedView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: sideWidths.0, alignment: .leading)
            if vm.metrics.hasNotch {
                Color.clear.frame(width: vm.notchSize.width)
            }
            trailing
                .frame(width: sideWidths.1, alignment: .trailing)
        }
        .frame(height: vm.closedSize.height)
        .padding(.horizontal, vm.activity == nil ? 0 : 10)
        .foregroundStyle(.white)
    }

    private var sideWidths: (CGFloat, CGFloat) {
        guard let activity = vm.activity else { return (0, 0) }
        return NotchViewModel.sideWidths(for: activity)
    }

    @ViewBuilder
    private var leading: some View {
        switch vm.activity {
        case .music:
            ArtworkView(size: 22, corner: 6)
                .padding(.leading, 4)
        case .volume(_, let muted):
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.leading, 6)
        case .brightness:
            Image(systemName: "sun.max.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.leading, 6)
        case .battery(_, let plugged, let charging):
            Image(systemName: charging ? "battery.100.bolt" : (plugged ? "powerplug.fill" : "battery.50"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(charging ? Color.green : .white)
                .padding(.leading, 6)
        case .message(_, let symbol, let tint):
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color(for: tint))
                .padding(.leading, 6)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch vm.activity {
        case .music(_, _, let playing):
            EqualizerBars(active: playing)
                .frame(width: 20, height: 14)
                .padding(.trailing, 6)
        case .volume(let value, let muted):
            MiniBar(value: muted ? 0 : Double(value))
                .padding(.trailing, 6)
        case .brightness(let value):
            MiniBar(value: Double(value))
                .padding(.trailing, 6)
        case .battery(let percent, _, _):
            Text("\(percent)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.trailing, 6)
        case .message(let text, _, _):
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.trailing, 6)
        case .none:
            EmptyView()
        }
    }

    private func color(for tint: LiveActivity.LiveTint) -> Color {
        switch tint {
        case .accent: return .accentColor
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        }
    }
}

// MARK: - Estado abierto

struct OpenView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 30)
            Divider().overlay(Color.white.opacity(0.08))
            body(for: vm.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .foregroundStyle(.white)
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
                ForEach(availableTabs) { tab in
                    TabButton(tab: tab, selected: vm.tab == tab) {
                        withAnimation(.islandFast) { vm.tab = tab }
                    }
                }
                Button {
                    withAnimation(.islandFast) { vm.isPinned.toggle() }
                } label: {
                    Image(systemName: vm.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(vm.isPinned ? 0.85 : 0))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(vm.isPinned ? .white : .white.opacity(0.45))
                .help(vm.isPinned ? "Fijada: no se cierra al alejar el mouse" : "Fijar abierta")

                Button {
                    AppDelegate.shared?.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.45))
                .help("Preferencias")
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
