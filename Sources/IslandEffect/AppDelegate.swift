import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()
    /// Con Preferencias abierto la isla no debe desplegarse: taparía la ventana.
    var settingsVisible: Bool { settingsWindow?.window?.isVisible ?? false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        VolumeMonitor.shared.start()
        BatteryMonitor.shared.start()
        MediaManager.shared.start()

        NotchController.shared.start()
        syncStatusItem()

        // Si la app se movió de sitio (por ejemplo de build/ a /Applications),
        // el ítem de inicio seguiría apuntando a la ruta vieja: se vuelve a
        // registrar el bundle actual.
        if Prefs.shared.launchAtLogin { LoginItem.set(enabled: true) }
        IslandDebug.log(String(format: "isla lista en %.0f ms", Date().timeIntervalSince(launchStart) * 1000))

        // El ícono de la barra empuja los demás: que se pueda quitar.
        Prefs.shared.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncStatusItem() }
            .store(in: &cancellables)

        if ProcessInfo.processInfo.environment["ISLAND_DEMO"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Task { @MainActor in
                    NotchController.shared.viewModel.show(
                        .music(title: "Me & Nas Bring It To Your Hardest",
                               subtitle: "Slick Rick", playing: true), duration: 90)
                }
            }
        }

        if ProcessInfo.processInfo.environment["ISLAND_OPEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                Task { @MainActor in NotchController.shared.openTab(.music) }
            }
        }

        if ProcessInfo.processInfo.environment["ISLAND_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showSettings() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - Menu bar

    private func syncStatusItem() {
        guard Prefs.shared.showMenuBarIcon else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "Island Effect")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Open the island"), action: #selector(toggleIsland), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let music = NSMenuItem(title: String(localized: "Music"), action: #selector(openMusic), keyEquivalent: "")
        music.target = self
        menu.addItem(music)
        let shelf = NSMenuItem(title: String(localized: "Shelf"), action: #selector(openShelf), keyEquivalent: "")
        shelf.target = self
        menu.addItem(shelf)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: String(localized: "Preferences…"), action: #selector(showSettingsAction), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit Island Effect"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleIsland() {
        Task { @MainActor in NotchController.shared.toggleOpen() }
    }

    @objc private func openMusic() {
        Task { @MainActor in NotchController.shared.openTab(.music) }
    }

    @objc private func openShelf() {
        Task { @MainActor in NotchController.shared.openTab(.shelf) }
    }

    @objc private func showSettingsAction() { showSettings() }

    func showSettings() {
        // La isla vive por encima de todas las ventanas: si queda abierta, tapa
        // las preferencias y no hay forma de tocarlas.
        Task { @MainActor in NotchController.shared.closeForModalWindow() }
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.show()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
