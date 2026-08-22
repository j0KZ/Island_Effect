import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var hoveredID: UUID?

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
                                          compact: compact)
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
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text("Arrastra archivos al notch")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("Quedan acá listos para arrastrarlos a donde quieras")
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
            Text("\(shelf.items.count) \(shelf.items.count == 1 ? "archivo" : "archivos")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Button("Copiar todo") { shelf.copyFiles() }
                .buttonStyle(PillButtonStyle())
            Button("Vaciar") { withAnimation(.islandFast) { shelf.clear() } }
                .buttonStyle(PillButtonStyle(destructive: true))
        }
    }
}

struct ShelfTile: View {
    let item: ShelfItem
    var hovered: Bool
    var compact: Bool = false
    @ObservedObject private var shelf = ShelfStore.shared

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: compact ? 30 : 42, height: compact ? 30 : 42)
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
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .onTapGesture(count: 2) { shelf.open(item) }
        .contextMenu {
            Button("Abrir") { shelf.open(item) }
            Button("Mostrar en Finder") { shelf.reveal(item) }
            Button("Copiar ruta") { shelf.copyPath(item) }
            Divider()
            Button("Quitar de la repisa", role: .destructive) { shelf.remove(item) }
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
