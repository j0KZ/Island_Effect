import AppKit
import SwiftUI
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
        BrightnessMonitor.shared.start()
        BatteryMonitor.shared.start()
        MediaManager.shared.start()

        NotchController.shared.start()
        syncStatusItem()

        // El ícono de la barra empuja los demás: que se pueda quitar.
        Prefs.shared.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncStatusItem() }
            .store(in: &cancellables)

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
        menu.addItem(withTitle: "Abrir la isla", action: #selector(toggleIsland), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let music = NSMenuItem(title: "Música", action: #selector(openMusic), keyEquivalent: "")
        music.target = self
        menu.addItem(music)
        let shelf = NSMenuItem(title: "Repisa", action: #selector(openShelf), keyEquivalent: "")
        shelf.target = self
        menu.addItem(shelf)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferencias…", action: #selector(showSettingsAction), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir de Island Effect", action: #selector(quit), keyEquivalent: "q")
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
