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
            HStack {
                Text("Retardo de cierre")
                Slider(value: $prefs.hoverCloseDelay, in: 0...1.2)
                Text(String(format: "%.2fs", prefs.hoverCloseDelay))
                    .monospacedDigit().frame(width: 46, alignment: .trailing)
            }
            Divider()
            Toggle("Seguir la pantalla donde está el mouse", isOn: $prefs.followMouseScreen)
            Toggle("Respuesta háptica del trackpad", isOn: $prefs.haptics)
            Toggle("Ícono en la barra de menús", isOn: $prefs.showMenuBarIcon)
            Text("Si lo apagas, la barra deja de correrse hacia la izquierda. Vuelves acá desde el engranaje de la isla.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Abrir al iniciar sesión", isOn: $prefs.launchAtLogin)
                .onChange(of: prefs.launchAtLogin) { _, enabled in
                    LoginItem.set(enabled: enabled)
                }
            Divider()
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
            HStack {
                Text("Ancho abierto")
                Slider(value: $prefs.expandedWidth, in: 420...900, step: 10)
                Text("\(Int(prefs.expandedWidth))").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Alto abierto")
                Slider(value: $prefs.expandedHeight, in: 96...340, step: 2)
                Text("\(Int(prefs.expandedHeight))").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Radio de esquinas")
                Slider(value: $prefs.cornerRadius, in: 8...40, step: 1)
                Text("\(Int(prefs.cornerRadius))").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Ancho extra en reposo")
                Slider(value: $prefs.extraClosedWidth, in: 0...260, step: 2)
                Text("\(Int(prefs.extraClosedWidth))").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Contorno Liquid Glass")
                Slider(value: $prefs.rimOpacity, in: 0...1, step: 0.02)
                Text("\(Int(prefs.rimOpacity * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            Toggle("Halo exterior del contorno", isOn: $prefs.rimGlow)
            Toggle("Fondo translúcido al abrir", isOn: $prefs.glassBackground)
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
                Toggle("Repisa de archivos", isOn: $prefs.enableShelf)
                Text("La repisa es un bolsillo: sueltas archivos sobre el notch, quedan ahí y los vuelves a arrastrar a donde los necesites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        // Un poco más abajo: así nunca queda bajo la isla desplegada.
        if let screen = window.screen ?? NSScreen.main {
            var frame = window.frame
            frame.origin.y = min(frame.origin.y, screen.visibleFrame.maxY - frame.height - 140)
            window.setFrame(frame, display: false)
        }
        self.init(window: window)
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
