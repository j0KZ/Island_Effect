import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }
            modules.tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 380)
    }

    // MARK: General

    private var general: some View {
        Form {
            Toggle("Open on hover", isOn: $prefs.openOnHover)
            HStack {
                Text("Open delay")
                Slider(value: $prefs.hoverOpenDelay, in: 0...0.8)
                Text(String(format: "%.2fs", prefs.hoverOpenDelay))
                    .monospacedDigit().frame(width: 46, alignment: .trailing)
            }
            Toggle("Follow the screen the pointer is on", isOn: $prefs.followMouseScreen)
            Toggle("Trackpad haptics", isOn: $prefs.haptics)
            Divider()
            Toggle("Menu bar icon", isOn: $prefs.showMenuBarIcon)
            Toggle("Open at login", isOn: $prefs.launchAtLogin)
                .onChange(of: prefs.launchAtLogin) { _, enabled in
                    LoginItem.set(enabled: enabled)
                }
            HStack {
                Button("Quit Island Effect") { NSApp.terminate(nil) }
                Spacer()
                Button("Restore defaults") { prefs.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Apariencia

    private var appearance: some View {
        Form {
            slider("Open width", value: $prefs.expandedWidth, range: 420...900, step: 10)
            slider("Open height", value: $prefs.expandedHeight, range: 96...340, step: 2)
            slider("Corner radius", value: $prefs.cornerRadius, range: 8...40, step: 1)
            slider("Extra width at rest", value: $prefs.extraClosedWidth, range: 0...260, step: 2)
            HStack {
                Text("Outline")
                Slider(value: $prefs.rimOpacity, in: 0...1, step: 0.02)
                Text("\(Int(prefs.rimOpacity * 100)) %")
                    .monospacedDigit().frame(width: 46, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: step)
            Text("\(Int(value.wrappedValue))")
                .monospacedDigit().frame(width: 46, alignment: .trailing)
        }
    }

    // MARK: Módulos

    private var modules: some View {
        Form {
            Section("Player") {
                Toggle("Music", isOn: $prefs.enableMusic)
                Toggle("Read Spotify", isOn: $prefs.useSpotify)
                    .disabled(!prefs.enableMusic)
                Toggle("Read Apple Music", isOn: $prefs.useAppleMusic)
                    .disabled(!prefs.enableMusic)
                Text("Turn off the one you don't use: each active player means one less query and one less automation prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Shelf") {
                Toggle("File shelf", isOn: $prefs.enableShelf)
                Text("A pocket: drop files onto the notch and drag them back out wherever you need them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Notices under the notch") {
                Text("Volume and brightness are not shown: macOS already shows its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Track change", isOn: $prefs.liveMusic)
                Toggle("Battery charging", isOn: $prefs.liveBattery)
                HStack {
                    Text("Duration")
                    Slider(value: $prefs.activityDuration, in: 1...6, step: 0.2)
                    Text(String(format: "%.1fs", prefs.activityDuration))
                        .monospacedDigit().frame(width: 46, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Acerca de

    private var about: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
            Text("Island Effect")
                .font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("Turns the Mac notch into an interactive island: player, file shelf and discreet notices.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            VStack(alignment: .leading, spacing: 5) {
                Label("Hover the notch to open it", systemImage: "cursorarrow")
                Label("Click it and it stays open; click again to close", systemImage: "cursorarrow.click")
                Label("Drag files onto the notch: they go to the shelf", systemImage: "tray.and.arrow.down")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            Spacer()
            VStack(spacing: 3) {
                Text("Made by j0KZ")
                    .font(.callout.weight(.medium))
                Link("github.com/j0KZ/Island_Effect",
                     destination: URL(string: "https://github.com/j0KZ/Island_Effect")!)
                    .font(.caption)
                Text("MIT License · © 2026 j0KZ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 18)
        }
        .padding(.top, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum LoginItem {
    static func set(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Island Effect: no se pudo cambiar el ítem de inicio: \(error.localizedDescription)")
        }
    }
}

final class SettingsWindowController: NSWindowController {
    private static let autosaveName = "IslandEffectPreferences"

    convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Island Effect Preferences")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // Fijamos el tamaño antes de centrar: si no, centra con un marco que
        // todavía no es el definitivo y queda descuadrada.
        window.setContentSize(NSSize(width: 460, height: 380))

        // AppKit recuerda el marco por nombre; solo colocamos la ventana la
        // primera vez, para no pisar donde el usuario la dejó.
        let key = "NSWindow Frame " + Self.autosaveName
        let isFirstRun = UserDefaults.standard.string(forKey: key) == nil
        window.setFrameAutosaveName(Self.autosaveName)
        if isFirstRun {
            window.center()
            if let screen = window.screen ?? NSScreen.main {
                var frame = window.frame
                frame.origin.y = min(frame.origin.y, screen.visibleFrame.maxY - frame.height - 140)
                window.setFrame(frame, display: false)
            }
            window.saveFrame(usingName: Self.autosaveName)
        }
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        window?.saveFrame(usingName: Self.autosaveName)
    }

    func windowWillClose(_ notification: Notification) {
        window?.saveFrame(usingName: Self.autosaveName)
        // Volvemos a ser un accesorio: sin ventanas no hay por qué ocupar el Dock.
        NSApp.setActivationPolicy(.accessory)
    }
}
