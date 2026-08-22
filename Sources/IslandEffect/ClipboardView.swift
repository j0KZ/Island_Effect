import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Historial del portapapeles dentro de la isla, al estilo del Win+V de Windows.
struct ClipboardView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var store = ClipboardStore.shared
    @ObservedObject private var prefs = Prefs.shared
    @FocusState private var searchFocused: Bool
    @State private var monitor: Any?
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            searchBar
            if store.visibleItems.isEmpty {
                empty
            } else {
                list
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            NotchController.shared.prepareClipboard()
            store.clampSelection()
            installMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
        }
        .onDisappear {
            removeMonitor()
            store.query = ""
            store.selection = 0
            NotchController.shared.releaseKeyboard()
        }
        .onChange(of: store.query) { _, _ in store.selection = 0 }
    }

    // MARK: - Buscador

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            TextField("Buscar en el historial", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit { pasteSelected() }
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            Text("\(store.visibleItems.count)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    // MARK: - Lista

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                        ClipRow(item: item,
                                index: index,
                                selected: index == store.selection,
                                hovered: hoveredID == item.id)
                            .id(item.id)
                            .onHover { inside in
                                if inside {
                                    hoveredID = item.id
                                    store.selection = index
                                } else if hoveredID == item.id {
                                    hoveredID = nil
                                }
                            }
                            .onTapGesture { store.use(item) }
                    }
                }
                .padding(.vertical, 1)
            }
            .onChange(of: store.selection) { _, _ in
                guard let id = store.selectedItem?.id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: store.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text(store.query.isEmpty ? "Todavía no copiaste nada" : "Nada coincide con la búsqueda")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            if store.query.isEmpty {
                Text("Copia texto, imágenes o archivos y van a aparecer acá")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                .foregroundStyle(.white.opacity(0.15))
        )
    }

    // MARK: - Pie

    @ViewBuilder
    private var footer: some View {
        if prefs.clipboardAutoPaste && !Paster.isTrusted {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("Falta permiso de Accesibilidad para pegar solo. Por ahora se copia y pegas con ⌘V.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Conceder") { Paster.requestPermission() }
                    .buttonStyle(PillButtonStyle())
            }
        } else {
            HStack(spacing: 10) {
                Text("↑↓ elegir · ⏎ pegar · ⌘1-9 directo · ⌘P fijar · ⌘⌫ borrar · ⎋ cerrar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !store.items.isEmpty {
                    Button("Vaciar") { withAnimation(.islandFast) { store.clear() } }
                        .buttonStyle(PillButtonStyle(destructive: true))
                }
            }
        }
    }

    // MARK: - Teclado

    private func pasteSelected() {
        guard let item = store.selectedItem else { return }
        store.use(item)
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let consumed = MainActor.assumeIsolated { ClipboardKeys.handle(event) }
            return consumed ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Atajos de teclado mientras la pestaña del portapapeles está abierta.
@MainActor
enum ClipboardKeys {
    /// Devuelve true si consumió la tecla; false para que siga su camino (por ejemplo, al buscador).
    static func handle(_ event: NSEvent) -> Bool {
        let store = ClipboardStore.shared
        guard NotchController.shared.viewModel.isOpen,
              NotchController.shared.viewModel.tab == .clipboard else { return false }

        let command = event.modifierFlags.contains(.command)
        let code = Int(event.keyCode)

        switch code {
        case kVK_DownArrow:
            store.move(by: 1); return true
        case kVK_UpArrow:
            store.move(by: -1); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = store.selectedItem { store.use(item) }
            return true
        case kVK_Escape:
            if !store.query.isEmpty { store.query = "" } else { NotchController.shared.dismissClipboard(pasting: false) }
            return true
        case kVK_Delete where command:
            if let item = store.selectedItem { withAnimation(.islandFast) { store.remove(item) } }
            return true
        case kVK_ANSI_P where command:
            if let item = store.selectedItem { withAnimation(.islandFast) { store.togglePin(item) } }
            return true
        default:
            break
        }

        // ⌘1…⌘9 pega directo el enésimo de la lista.
        if command, let digit = digitKeys[code] {
            let list = store.visibleItems
            let index = digit - 1
            if list.indices.contains(index) {
                store.selection = index
                store.use(list[index])
            }
            return true
        }

        return false
    }

    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9
    ]
}

// MARK: - Fila

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let hovered: Bool
    @ObservedObject private var store = ClipboardStore.shared

    var body: some View {
        HStack(spacing: 9) {
            badge
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white.opacity(0.92))
                Text(item.subtitle)
                    .font(.system(size: 9.5))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.42))
            }
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.9))
            }
            if hovered || selected {
                HStack(spacing: 2) {
                    iconButton(item.pinned ? "pin.slash" : "pin", help: item.pinned ? "Soltar" : "Fijar") {
                        withAnimation(.islandFast) { store.togglePin(item) }
                    }
                    iconButton("xmark", help: "Quitar") {
                        withAnimation(.islandFast) { store.remove(item) }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.16 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(selected ? 0.14 : 0), lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contextMenu {
            Button("Pegar") { store.use(item) }
            Button("Solo copiar") { store.writeToPasteboard(item) }
            if item.isLink, let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Button("Abrir enlace") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button(item.pinned ? "Soltar" : "Fijar arriba") { store.togglePin(item) }
            Button("Quitar del historial", role: .destructive) { store.remove(item) }
        }
        .help(item.preview)
    }

    private var badge: some View {
        Text(index < 9 ? "\(index + 1)" : "·")
            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(selected ? 0.75 : 0.3))
            .frame(width: 14)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.kind == .image, let image = store.image(for: item) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else if item.kind == .files, let first = item.urls.first {
            Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                .resizable()
                .frame(width: 22, height: 22)
                .frame(width: 26, height: 26)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 26, height: 26)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.7))
        .help(help)
    }
}
