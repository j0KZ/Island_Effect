import Foundation

/// Registro opcional para depurar: exporta ISLAND_DEBUG=1 antes de lanzar la app.
enum IslandDebug {
    static let enabled = ProcessInfo.processInfo.environment["ISLAND_DEBUG"] == "1"
    /// Pestaña inicial forzada con ISLAND_TAB=music|shelf|widgets (solo para pruebas).
    static var initialTab: NotchTab {
        guard let raw = ProcessInfo.processInfo.environment["ISLAND_TAB"],
              let tab = NotchTab(rawValue: raw) else { return .music }
        return tab
    }

    /// Ruta opcional de archivo de log (ISLAND_LOG=/ruta/al/archivo).
    private static let logPath = ProcessInfo.processInfo.environment["ISLAND_LOG"]

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "[island] " + message() + "\n"
        if let logPath {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(toFile: logPath, atomically: false, encoding: .utf8)
            }
        }
        FileHandle.standardError.write(Data(line.utf8))
    }
}
