import AppKit
import Combine

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var name: String { url.lastPathComponent }
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    var sizeLabel: String {
        if isDirectory { return "Carpeta" }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    init(url: URL) {
        self.id = UUID()
        self.url = url.standardizedFileURL
    }
}

/// Repisa de archivos: arrastra archivos al notch y quedan disponibles para volver a arrastrarlos.
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    private let key = "shelfBookmarks"

    @Published private(set) var items: [ShelfItem] = []

    private init() { load() }

    func add(urls: [URL]) {
        var added = false
        for url in urls {
            let std = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: std.path) else { continue }
            guard !items.contains(where: { $0.url == std }) else { continue }
            items.insert(ShelfItem(url: std), at: 0)
            added = true
        }
        if added { save() }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func copyPath(_ item: ShelfItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.url.path, forType: .string)
    }

    func copyFiles() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
    }

    // MARK: - Persistencia

    private func save() {
        let paths = items.map { $0.url.path }
        UserDefaults.standard.set(paths, forKey: key)
    }

    private func load() {
        guard let paths = UserDefaults.standard.stringArray(forKey: key) else { return }
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { ShelfItem(url: URL(fileURLWithPath: $0)) }
    }
}
