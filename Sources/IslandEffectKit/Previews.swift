#if DEBUG
import SwiftUI
import AppKit

// Vistas previas para revisar la isla sin lanzar la app ni tener un notch.
// Van sobre fondo negro porque la isla se dibuja siempre sobre el notch.

@MainActor
private func previewModel(open: Bool, tab: NotchTab = .music, activity: LiveActivity? = nil,
                          height: Double? = nil) -> NotchViewModel {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    // Preferencias desechables: una vista previa que toque `Prefs.shared` le
    // cambiaría los ajustes a quien esté usando la app.
    let suite = "island-previews-\(UUID().uuidString)"
    let prefs = Prefs(defaults: UserDefaults(suiteName: suite) ?? .standard)
    if let height { prefs.expandedHeight = height }
    let vm = NotchViewModel(metrics: ScreenMetrics(screen: screen, hasNotch: true,
                                                   notchSize: CGSize(width: 185, height: 32)),
                            prefs: prefs,
                            setNeedsProgress: { _ in })
    vm.isOpen = open
    vm.tab = tab
    vm.activity = activity
    return vm
}

#Preview("Componentes") {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            ArtworkView(size: 48, corner: 10)
            EqualizerBars(active: true).frame(width: 18, height: 16)
            CircleButton(symbol: "backward.fill") {}
            CircleButton(symbol: "play.fill", size: 38, iconSize: 15, filled: true) {}
            CircleButton(symbol: "forward.fill") {}
        }
        IslandSlider(value: .constant(0.4)).frame(width: 220, height: 16)
        Text(TimeFormat.clock(3725)).foregroundStyle(.white)
    }
    .padding(24)
    .background(.black)
}

#Preview("Isla cerrada con música") {
    RootView(vm: previewModel(open: false,
                              activity: .music(title: "Song", subtitle: "Artist", playing: true)))
        .frame(width: 600, height: 120)
        .background(.black)
}

#Preview("Isla abierta · Música") {
    RootView(vm: previewModel(open: true, tab: .music))
        .frame(width: 600, height: 260)
        .background(.black)
}

#Preview("Isla abierta · Estante") {
    RootView(vm: previewModel(open: true, tab: .shelf))
        .frame(width: 600, height: 260)
        .background(.black)
}

/// Preferencias desechables para las vistas previas de la ventana de ajustes.
@MainActor
private func previewPrefs(_ setup: (Prefs) -> Void = { _ in }) -> Prefs {
    let suite = "island-previews-\(UUID().uuidString)"
    let prefs = Prefs(defaults: UserDefaults(suiteName: suite) ?? .standard)
    setup(prefs)
    return prefs
}

#Preview("Preferencias · Apariencia") {
    // Los sliders van sin `step:` a propósito: con él, macOS dibuja una marca
    // por paso y el control queda hecho un peine.
    SettingsView(prefs: previewPrefs(), tab: .appearance)
}

#Preview("Preferencias · Módulos") {
    SettingsView(prefs: previewPrefs { $0.enableShelf = true }, tab: .modules)
}

#Preview("Isla abierta · Sin música, panel bajo") {
    // El alto mínimo que deja Preferencias. Es donde se veía el corte: los
    // botones de Música y Spotify quedaban fuera de la isla.
    RootView(vm: previewModel(open: true, tab: .music, height: 100))
        .frame(width: 600, height: 180)
        .background(.black)
}

#Preview("Isla abierta · Repisa vacía, panel bajo") {
    // El otro sitio donde el contenido se salía por abajo: la explicación de
    // la repisa vacía, que se lee justo mientras arrastras algo hacia ella.
    RootView(vm: previewModel(open: true, tab: .shelf, height: 100))
        .frame(width: 600, height: 180)
        .background(.black)
}

/// Una captura de mentira en disco, para que la miniatura tenga algo que
/// enseñar. Sin archivo, la vista previa saldría con el hueco gris.
private func sampleCapture() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("island-preview-capture.png")
    guard !FileManager.default.fileExists(atPath: url.path) else { return url }
    let size = NSSize(width: 320, height: 200)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGradient(colors: [.systemTeal, .systemIndigo, .systemPink])?
        .draw(in: NSRect(origin: .zero, size: size), angle: 35)
    image.unlockFocus()
    if let tiff = image.tiffRepresentation,
       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
    }
    return url
}

#Preview("Isla cerrada · Captura lista") {
    RootView(vm: previewModel(open: false,
                              activity: .screenshot(url: sampleCapture(), sizeLabel: "1,2 MB")))
        .frame(width: 600, height: 120)
        .background(.black)
}

#Preview("Isla cerrada · El notch se traga la captura") {
    let vm = previewModel(open: false)
    vm.pulsing = true
    return RootView(vm: vm)
        .frame(width: 600, height: 120)
        .background(.black)
}

#Preview("Captura subiendo · el recorrido") {
    // Los fotogramas de la subida, uno al lado del otro: una animación no se
    // puede revisar en una vista previa, pero su trayectoria sí.
    let notch: CGFloat = 38
    return HStack(spacing: 34) {
        ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { t in
            let f = CaptureToss.frame(at: t, notchHeight: notch)
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.06)).frame(width: 70, height: 150)
                    Rectangle().fill(.white.opacity(0.14)).frame(width: 70, height: notch)
                    ScreenshotThumb(url: sampleCapture(), side: CaptureToss.side)
                        .scaleEffect(f.scale)
                        .opacity(f.opacity)
                        .offset(y: f.offsetY)
                }
                .frame(width: 70, height: 150, alignment: .top)
                .clipped()
                Text(String(format: "%.2f", t))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
    .padding(24)
    .background(.black)
}

#Preview("Repisa · Captura de paso") {
    HStack(spacing: 10) {
        ShelfTile(item: ShelfItem(url: sampleCapture(),
                                  expiresAt: Date().addingTimeInterval(252)),
                  hovered: false)
        ShelfTile(item: ShelfItem(url: sampleCapture(),
                                  expiresAt: Date().addingTimeInterval(9)),
                  hovered: true)
        ShelfTile(item: ShelfItem(url: URL(fileURLWithPath: "/etc/hosts")), hovered: false)
    }
    .padding(24)
    .background(.black)
}
#endif
