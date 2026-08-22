import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            appearance.tabItem { Label("Apariencia", systemImage: "paintbrush") }
            modules.tabItem { Label("Módulos", systemImage: "square.grid.2x2") }
            gestures.tabItem { Label("Gestos", systemImage: "hand.draw") }
            about.tabItem { Label("Acerca de", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 380)
    }

    // MARK: General

    private var general: some View {
        Form {
            Toggle("Abrir al pasar el mouse", isOn: $prefs.openOnHover)
            HStack {
                Text("Retardo de apertura")
                Slider(value: $prefs.hoverOpenDelay, in: 0...0.8)
                Text(String(format: "%.2fs", prefs.hoverOpenDelay))
                    .monospacedDigit().frame(width: 46, alignment: .trailing)
            }
            Toggle("Seguir la pantalla donde está el mouse", isOn: $prefs.followMouseScreen)
            Toggle("Respuesta háptica del trackpad", isOn: $prefs.haptics)
            Divider()
            Toggle("Ícono en la barra de menús", isOn: $prefs.showMenuBarIcon)
            Toggle("Abrir al iniciar sesión", isOn: $prefs.launchAtLogin)
                .onChange(of: prefs.launchAtLogin) { _, enabled in
                    LoginItem.set(enabled: enabled)
                }
            HStack {
                Button("Salir de Island Effect") { NSApp.terminate(nil) }
                Spacer()
                Button("Restaurar valores por omisión") { prefs.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Apariencia

    private var appearance: some View {
        Form {
            slider("Ancho abierto", value: $prefs.expandedWidth, range: 420...900, step: 10)
            slider("Alto abierto", value: $prefs.expandedHeight, range: 96...340, step: 2)
            slider("Radio de esquinas", value: $prefs.cornerRadius, range: 8...40, step: 1)
            slider("Ancho extra en reposo", value: $prefs.extraClosedWidth, range: 0...260, step: 2)
            HStack {
                Text("Contorno")
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
            Section("Reproductor") {
                Toggle("Música", isOn: $prefs.enableMusic)
                Toggle("Leer Spotify", isOn: $prefs.useSpotify)
                    .disabled(!prefs.enableMusic)
                Toggle("Leer Apple Music", isOn: $prefs.useAppleMusic)
                    .disabled(!prefs.enableMusic)
                Text("Apaga el que no uses: cada reproductor activo es una consulta menos y un permiso de automatización menos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Repisa") {
                Toggle("Repisa de archivos", isOn: $prefs.enableShelf)
                Text("Un bolsillo: sueltas archivos sobre el notch y los vuelves a arrastrar a donde los necesites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Avisos bajo el notch") {
                Text("Volumen y brillo no aparecen: macOS ya muestra los suyos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Cambio de canción", isOn: $prefs.liveMusic)
                Toggle("Carga de batería", isOn: $prefs.liveBattery)
                HStack {
                    Text("Duración")
                    Slider(value: $prefs.activityDuration, in: 1...6, step: 0.2)
                    Text(String(format: "%.1fs", prefs.activityDuration))
                        .monospacedDigit().frame(width: 46, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Gestos

    private var gestures: some View {
        Form {
            Toggle("Scroll vertical sobre el notch = volumen", isOn: $prefs.scrollVolume)
            Toggle("Scroll horizontal = canción anterior/siguiente", isOn: $prefs.scrollTrack)
            Section {
                Label("Clic en el notch: la deja abierta; otro clic la cierra", systemImage: "cursorarrow.click")
                Label("Arrastrar archivos al notch: van a la repisa", systemImage: "tray.and.arrow.down")
            }
            .foregroundStyle(.secondary)
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
            Text("Versión \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("Convierte el notch del Mac en una isla interactiva: reproductor, repisa de archivos y avisos discretos.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
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
        window.title = "Preferencias de Island Effect"
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
