import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        VolumeMonitor.shared.start()
        BrightnessMonitor.shared.start()
        BatteryMonitor.shared.start()
        MediaManager.shared.start()

        NotchController.shared.start()
        setupStatusItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
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
        let widgets = NSMenuItem(title: "Widgets", action: #selector(openWidgets), keyEquivalent: "")
        widgets.target = self
        menu.addItem(widgets)
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

    @objc private func openWidgets() {
        Task { @MainActor in NotchController.shared.openTab(.widgets) }
    }

    @objc private func showSettingsAction() { showSettings() }

    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.show()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
