#if DEBUG
import SwiftUI
import AppKit

// Vistas previas para revisar la isla sin lanzar la app ni tener un notch.
// Van sobre fondo negro porque la isla se dibuja siempre sobre el notch.

@MainActor
private func previewModel(open: Bool, tab: NotchTab = .music, activity: LiveActivity? = nil) -> NotchViewModel {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let vm = NotchViewModel(metrics: ScreenMetrics(screen: screen, hasNotch: true,
                                                   notchSize: CGSize(width: 185, height: 32)))
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
