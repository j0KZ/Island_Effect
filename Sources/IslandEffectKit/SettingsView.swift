import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    enum Tab: Hashable { case general, appearance, modules, about }

    @ObservedObject private var prefs: Prefs
    @State private var tab: Tab
    /// La miniatura de macOS, leída al abrir Preferencias. No es nuestra, así
    /// que se relee en vez de guardarse.
    @State private var systemThumbnail = SystemScreenshotThumbnail.isOn()

    /// Las preferencias se reciben para que una vista previa no le cambie los
    /// ajustes a quien esté usando la app; la pestaña, para poder revisar cada
    /// una por separado (un `TabView` sin selección siempre muestra la primera).
    init(prefs: Prefs = .shared, tab: Tab = .general) {
        _prefs = ObservedObject(wrappedValue: prefs)
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(Tab.general)
            appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }.tag(Tab.appearance)
            modules.tabItem { Label("Modules", systemImage: "square.grid.2x2") }.tag(Tab.modules)
            about.tabItem { Label("About", systemImage: "info.circle") }.tag(Tab.about)
        }
        // Módulos es la pestaña larga: con 380 quedaban las capturas bajo el
        // borde y había que adivinar que la lista seguía.
        .frame(width: 460, height: 440)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                Toggle("Open on hover", isOn: $prefs.openOnHover)
                HStack {
                    Text("Open delay")
                    Slider(value: Self.stepped($prefs.hoverOpenDelay, by: 0.05), in: 0...0.8)
                    Text(String(format: "%.2fs", prefs.hoverOpenDelay))
                        .monospacedDigit().frame(width: 46, alignment: .trailing)
                }
                Toggle("Follow the screen the pointer is on", isOn: $prefs.followMouseScreen)
                Toggle("Trackpad haptics", isOn: $prefs.haptics)
            }
            Section {
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
                Slider(value: Self.stepped($prefs.rimOpacity, by: 0.02), in: 0...1)
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
            Slider(value: Self.stepped(value, by: step), in: range)
            Text("\(Int(value.wrappedValue))")
                .monospacedDigit().frame(width: 46, alignment: .trailing)
        }
    }

    /// El salto se hace en el binding y no con el `step:` del `Slider`.
    ///
    /// macOS dibuja una marca por cada paso: el ancho abierto va de 420 a 900
    /// de a 10, o sea 48 marcas, y el control queda hecho un peine que además
    /// no dice nada —nadie cuenta marcas para elegir 620—. Redondeando acá se
    /// sigue moviendo de a pasos, pero la barra queda limpia.
    private static func stepped(_ value: Binding<Double>, by step: Double) -> Binding<Double> {
        Binding(get: { value.wrappedValue },
                set: { value.wrappedValue = step > 0 ? ((($0) / step).rounded()) * step : $0 })
    }

    // MARK: Módulos

    private var modules: some View {
        Form {
            Section("Player") {
                // El último módulo encendido no se puede apagar: sin ninguno,
                // la isla abierta no tendría nada que mostrar.
                Toggle("Music", isOn: $prefs.enableMusic)
                    .disabled(prefs.enableMusic && !prefs.enableShelf)
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
                    .disabled(prefs.enableShelf && !prefs.enableMusic)
                Text("A pocket: drop files onto the notch and drag them back out wherever you need them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Screenshots land on the shelf", isOn: $prefs.captureShelf)
                    .disabled(!prefs.enableShelf)
                HStack {
                    Text("They leave after")
                    Slider(value: Self.stepped($prefs.captureMinutes, by: 1),
                           in: Prefs.Limits.captureMinutes)
                    Text(String(format: "%.0f min", prefs.captureMinutes))
                        .monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                .disabled(!prefs.enableShelf || !prefs.captureShelf)
                Text("macOS already shows a thumbnail in the corner, but it lasts five seconds. This one waits for you, and clears itself once you use it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if prefs.captureShelf, systemThumbnail {
                    // Mientras la miniatura de macOS esté activada, el archivo
                    // no llega al disco hasta que ella se va: cinco segundos en
                    // los que la isla no tiene nada que mostrar.
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Screenshots take about five seconds to show up")
                                .font(.caption).bold()
                            Text("macOS only writes the file once its own thumbnail goes away. Turning that thumbnail off makes them appear at once — the island already does its job.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Turn off the macOS thumbnail") {
                                SystemScreenshotThumbnail.set(false)
                                systemThumbnail = false
                            }
                        }
                    }
                } else if prefs.captureShelf {
                    HStack(spacing: 8) {
                        Text("The macOS thumbnail is off, so screenshots appear immediately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Undo") {
                            SystemScreenshotThumbnail.set(true)
                            systemThumbnail = true
                        }
                    }
                }
            }
            Section("Notices under the notch") {
                Text("Volume and brightness are not shown: macOS already shows its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Track change", isOn: $prefs.liveMusic)
                Toggle("Battery charging", isOn: $prefs.liveBattery)
                Toggle("Screenshot taken", isOn: $prefs.liveScreenshot)
                    .disabled(!prefs.captureShelf)
                HStack {
                    Text("Duration")
                    Slider(value: Self.stepped($prefs.activityDuration, by: 0.2), in: 1...6)
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
