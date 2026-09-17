import SwiftUI
import AppKit
import Combine

struct ShelfView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var hoveredID: UUID?

    /// El reloj de las cuentas atrás. Vive aquí y no en cada miniatura: con un
    /// temporizador por tarjeta, diez capturas eran diez despertares por segundo
    /// para dibujar lo mismo.
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 110
            VStack(spacing: 6) {
                if shelf.items.isEmpty {
                    empty
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items) { item in
                                ShelfTile(item: item,
                                          hovered: hoveredID == item.id,
                                          compact: compact,
                                          tick: tick)
                                    .onHover { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                        .frame(maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                    if !compact { footer }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(ticker) { now in
                // Sin capturas de paso no hay nada que refrescar.
                guard shelf.items.contains(where: \.isTemporary) else { return }
                tick = now
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text("Drag files onto the notch")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("They stay here, ready to drag wherever you want")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                .foregroundStyle(.white.opacity(0.15))
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(shelf.items.count == 1 ? "\(shelf.items.count) file" : "\(shelf.items.count) files")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Button("Copy all") { shelf.copyFiles() }
                .buttonStyle(PillButtonStyle())
            Button("Empty") { withAnimation(.islandFast) { shelf.clear() } }
                .buttonStyle(PillButtonStyle(destructive: true))
        }
    }
}

struct ShelfTile: View {
    let item: ShelfItem
    var hovered: Bool
    var compact: Bool = false
    /// El ahora, para la cuenta atrás. Lo manda la repisa, que tiene el único
    /// temporizador.
    var tick: Date = Date()
    @ObservedObject private var shelf = ShelfStore.shared

    var body: some View {
        VStack(spacing: 4) {
            if item.isTemporary {
                ScreenshotThumb(url: item.url, side: compact ? 30 : 42)
                    // La cuenta atrás va sobre la miniatura y no bajo la
                    // tarjeta: ahí tapaba el nombre del archivo, que en una
                    // captura es justo la fecha y la hora que la distinguen.
                    .overlay(alignment: .bottom) {
                        if let left = ShelfStore.remaining(item, now: tick) {
                            CountdownBadge(seconds: left)
                                .padding(.bottom, 2)
                        }
                    }
            } else {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: compact ? 30 : 42, height: compact ? 30 : 42)
            }
            Text(item.name)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(compact ? 1 : 2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 74, height: compact ? 56 : 78)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.12 : 0.06))
        )
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button {
                    withAnimation(.islandFast) { shelf.remove(item) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85), Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
                .transition(.opacity)
            }
        }
        .onDrag {
            shelf.markUsed(item)
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .onTapGesture(count: 2) { shelf.open(item); shelf.markUsed(item) }
        .contextMenu {
            Button("Open") { shelf.open(item); shelf.markUsed(item) }
            Button("Show in Finder") { shelf.reveal(item) }
            Button("Copy path") { shelf.copyPath(item); shelf.markUsed(item) }
            if item.isTemporary {
                Button("Keep on the shelf") { shelf.add(urls: [item.url]) }
            }
            Divider()
            Button("Remove from shelf", role: .destructive) { shelf.remove(item) }
        }
        .help("\(item.name) · \(item.sizeLabel)")
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

struct PillButtonStyle: ButtonStyle {
    var destructive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
            .foregroundStyle(destructive ? Color.red.opacity(0.9) : .white.opacity(0.85))
    }
}


/// Cuánto le queda a una captura antes de irse sola, sobre su miniatura.
///
/// Es un número y no solo un aro: al ver "4:12" sabes que puedes ir a buscar la
/// ventana de destino con calma, y un aro a medio llenar no dice eso.
struct CountdownBadge: View {
    let seconds: TimeInterval

    var body: some View {
        Text(TimeFormat.clock(seconds))
            .font(.system(size: 8.5, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            .accessibilityLabel(Text("Leaves the shelf soon"))
    }
}
