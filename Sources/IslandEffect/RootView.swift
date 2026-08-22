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
                .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(dropTargeted && !vm.isOpen ? 1.04 : 1, anchor: .top)
        .animation(.island, value: vm.isOpen)
        .animation(.island, value: vm.activity)
        .animation(.islandFast, value: vm.isHovering)
        .animation(.islandFast, value: dropTargeted)
        .contentShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
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

    private var topRadius: CGFloat { vm.isOpen ? 12 : 8 }
    private var strokeOpacity: Double {
        if vm.isOpen { return 0.10 }
        return vm.activity != nil ? 0.06 : 0
    }
    private var bottomRadius: CGFloat {
        if vm.isOpen { return prefs.cornerRadius }
        return vm.activity != nil ? 14 : (vm.metrics.hasNotch ? 10 : 6)
    }

    private var background: some View {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            .fill(Color.black)
            .overlay(
                NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                    .fill(
                        LinearGradient(colors: [Color.white.opacity(prefs.tintedBackground ? 0.07 : 0),
                                                Color.white.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            )
            .overlay(
                NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.8)
            )
            // En reposo la isla debe ser indistinguible del notch: sin borde ni sombra.
            .shadow(color: .black.opacity(vm.isOpen ? 0.6 : (vm.activity != nil ? 0.25 : 0)),
                    radius: vm.isOpen ? 22 : 6, x: 0, y: vm.isOpen ? 10 : 3)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isOpen {
            OpenView(vm: vm)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
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
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .semibold))
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
        case .timer(let remaining):
            Text(TimeFormat.clock(remaining))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
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
                .frame(height: vm.metrics.hasNotch ? vm.notchSize.height : 26)
            Divider().overlay(Color.white.opacity(0.08))
            body(for: vm.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
        }
        .foregroundStyle(.white)
    }

    private var availableTabs: [NotchTab] {
        NotchTab.allCases.filter {
            switch $0 {
            case .music: return prefs.enableMusic
            case .clipboard: return prefs.enableClipboard
            case .shelf: return prefs.enableShelf
            case .widgets: return prefs.enableWidgets
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(Host.current().localizedName ?? "Mac")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 14)
                .lineLimit(1)
            Spacer(minLength: 0)
            if vm.metrics.hasNotch {
                Color.clear.frame(width: vm.notchSize.width - 40)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(availableTabs) { tab in
                    TabButton(tab: tab, selected: vm.tab == tab) {
                        withAnimation(.islandFast) { vm.tab = tab }
                    }
                }
                Button {
                    vm.isPinned.toggle()
                } label: {
                    Image(systemName: vm.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(vm.isPinned ? Color.accentColor : .white.opacity(0.45))
                .help("Mantener abierto")

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
        case .clipboard: ClipboardView(vm: vm)
        case .shelf: ShelfView(vm: vm)
        case .widgets: WidgetsView(vm: vm)
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
