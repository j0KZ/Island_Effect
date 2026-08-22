import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var accessibilityGranted = Paster.isTrusted
    private let accessibilityTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            appearance.tabItem { Label("Apariencia", systemImage: "paintbrush") }
            modules.tabItem { Label("Módulos", systemImage: "square.grid.2x2") }
            clipboard.tabItem { Label("Portapapeles", systemImage: "doc.on.clipboard") }
            gestures.tabItem { Label("Gestos", systemImage: "hand.draw") }
            about.tabItem { Label("Acerca de", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 400)
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
            HStack {
                Text("Retardo de cierre")
                Slider(value: $prefs.hoverCloseDelay, in: 0...1.2)
                Text(String(format: "%.2fs", prefs.hoverCloseDelay))
                    .monospacedDigit().frame(width: 46, alignment: .trailing)
            }
            Divider()
            Toggle("Seguir la pantalla donde está el mouse", isOn: $prefs.followMouseScreen)
            Toggle("Respuesta háptica del trackpad", isOn: $prefs.haptics)
            Toggle("Abrir al iniciar sesión", isOn: $prefs.launchAtLogin)
                .onChange(of: prefs.launchAtLogin) { _, enabled in
                    LoginItem.set(enabled: enabled)
                }
            Divider()
            HStack {
                Spacer()
                Button("Restaurar valores por omisión") { prefs.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Apariencia

    private var appearance: some View {
        Form {
            HStack {
                Text("Ancho abierto")
                Slider(value: $prefs.expandedWidth, in: 420...900, step: 10)
                Text("\(Int(prefs.expandedWidth))").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Alto abierto")
                Slider(value: $prefs.expandedHeight, in: 140...340, step: 5)
                Text("\(Int(prefs.expandedHeight))").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Radio de esquinas")
                Slider(value: $prefs.cornerRadius, in: 8...40, step: 1)
                Text("\(Int(prefs.cornerRadius))").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Ancho extra en reposo")
                Slider(value: $prefs.extraClosedWidth, in: 0...80, step: 2)
                Text("\(Int(prefs.extraClosedWidth))").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            Toggle("Degradado sutil en el fondo", isOn: $prefs.tintedBackground)
            Toggle("Reloj de 24 horas", isOn: $prefs.use24hClock)
        }
        .formStyle(.grouped)
    }

    // MARK: Módulos

    private var modules: some View {
        Form {
            Section("Pestañas") {
                Toggle("Música", isOn: $prefs.enableMusic)
                Toggle("Portapapeles", isOn: $prefs.enableClipboard)
                    .onChange(of: prefs.enableClipboard) { _, _ in
                        Task { @MainActor in NotchController.shared.registerClipboardHotKey() }
                    }
                Toggle("Repisa de archivos", isOn: $prefs.enableShelf)
                Toggle("Widgets", isOn: $prefs.enableWidgets)
                Toggle("Recordar archivos de la repisa entre sesiones", isOn: $prefs.shelfPersists)
            }
            Section("Live activities") {
                Toggle("Cambio de canción", isOn: $prefs.liveMusic)
                Toggle("Volumen", isOn: $prefs.liveVolume)
                Toggle("Brillo", isOn: $prefs.liveBrightness)
                Toggle("Carga de batería", isOn: $prefs.liveBattery)
                HStack {
                    Text("Duración")
                    Slider(value: $prefs.activityDuration, in: 1...6, step: 0.2)
                    Text(String(format: "%.1fs", prefs.activityDuration))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Portapapeles

    private var clipboard: some View {
        Form {
            Section("Atajo") {
                Toggle("Atajo global para abrir el historial", isOn: $prefs.clipboardHotKeyEnabled)
                    .onChange(of: prefs.clipboardHotKeyEnabled) { _, _ in reloadHotKey() }
                HStack {
                    Text("Combinación")
                    Spacer()
                    HotKeyRecorder(keyCode: $prefs.clipboardHotKeyCode,
                                   modifiers: $prefs.clipboardHotKeyMods,
                                   onChange: reloadHotKey)
                }
                .disabled(!prefs.clipboardHotKeyEnabled)
                Text("Es el equivalente del ⊞+V de Windows. Después de elegir algo del historial queda en el portapapeles, así que el ⌘V normal lo vuelve a pegar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pegado") {
                Toggle("Pegar automáticamente al elegir", isOn: $prefs.clipboardAutoPaste)
                HStack(spacing: 8) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Text(accessibilityGranted
                         ? "Permiso de Accesibilidad concedido."
                         : "Sin Accesibilidad solo se copia; el ⌘V lo tienes que dar tú.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !accessibilityGranted {
                        Button("Conceder…") {
                            Paster.requestPermission()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section("Historial") {
                HStack {
                    Text("Máximo de recortes")
                    Slider(value: $prefs.clipboardMaxItems, in: 10...300, step: 10)
                    Text("\(Int(prefs.clipboardMaxItems))")
                        .monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Toggle("Recordar el historial entre sesiones", isOn: $prefs.clipboardPersists)
                Toggle("Guardar también imágenes", isOn: $prefs.clipboardKeepImages)
                Toggle("Ignorar gestores de contraseñas y copias marcadas como privadas",
                       isOn: $prefs.clipboardIgnoreConfidential)
                HStack {
                    Spacer()
                    Button("Borrar todo el historial", role: .destructive) {
                        Task { @MainActor in ClipboardStore.shared.purge() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityGranted = Paster.isTrusted }
        .onReceive(accessibilityTicker) { _ in
            let trusted = Paster.isTrusted
            if trusted != accessibilityGranted { accessibilityGranted = trusted }
        }
    }

    private func reloadHotKey() {
        Task { @MainActor in NotchController.shared.registerClipboardHotKey() }
    }

    // MARK: Gestos

    private var gestures: some View {
        Form {
            Toggle("Scroll vertical sobre el notch = volumen", isOn: $prefs.scrollVolume)
            Toggle("Scroll horizontal sobre el notch = canción anterior/siguiente", isOn: $prefs.scrollTrack)
            Section("Otros") {
                Label("Clic en el notch: fijar abierto o cerrar", systemImage: "cursorarrow.click")
                Label("Arrastrar archivos al notch: van a la repisa", systemImage: "tray.and.arrow.down")
                Label("Arrastrar desde la repisa: suelta el archivo donde quieras", systemImage: "arrow.up.doc")
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
            Text("Convierte el notch del Mac en una isla interactiva: música, repisa de archivos, widgets y live activities.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Text("El \"now playing\" usa AppleScript con Música y Spotify. La primera vez macOS pedirá permiso de Automatización.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 30)
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
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Preferencias de Island Effect"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Campo para capturar una combinación de teclas.
struct HotKeyRecorder: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onChange: () -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording.toggle()
        } label: {
            Text(recording ? "Presiona la combinación…" : HotKeySpec(keyCode: keyCode, modifiers: modifiers).display)
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 120)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onChange(of: recording) { _, on in on ? start() : stop() }
        .onDisappear { stop() }
        .help("Haz clic y presiona la combinación que quieras")
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mods = HotKeySpec.carbonModifiers(from: event.modifierFlags)
            if event.keyCode == 53 { // esc cancela
                recording = false
                return nil
            }
            guard mods != 0 else { NSSound.beep(); return nil }
            keyCode = Int(event.keyCode)
            modifiers = mods
            recording = false
            onChange()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
