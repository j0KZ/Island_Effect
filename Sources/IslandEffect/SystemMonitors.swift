import AppKit
import Combine
import notify
import CoreAudio
import AudioToolbox
import IOKit.ps

// MARK: - Volumen del sistema (CoreAudio, API pública)

final class VolumeMonitor: ObservableObject {
    static let shared = VolumeMonitor()

    @Published private(set) var volume: Float = 0
    @Published private(set) var muted: Bool = false
    /// Se dispara cuando el volumen cambia por cualquier motivo (teclas, nosotros, otra app).
    var onChange: ((Float, Bool) -> Void)?

    private var device: AudioDeviceID = kAudioObjectUnknown
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var listenerDevice: AudioDeviceID = kAudioObjectUnknown
    /// Si CoreAudio nos avisa de verdad, el sondeo sobra.
    private var sawListener = false

    private init() {
        refreshDevice()
        volume = readVolume()
        muted = readMuted()
    }

    private var poller: Timer?
    private var cancellable: AnyCancellable?

    func start() {
        installListener()
        refreshPolling()
        cancellable = Prefs.shared.$liveVolume
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPolling() }

        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.refreshDevice()
            self?.installListener()
        }
    }

    /// El listener de CoreAudio no es fiable para el volumen virtual, así que
    /// sondeamos —pero solo si el aviso está activo; si no, es gasto puro.
    private func refreshPolling() {
        poller?.invalidate()
        poller = nil
        guard Prefs.shared.liveVolume, !sawListener else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.publish(notify: true)
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    private func refreshDevice() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        if status == noErr { device = id }
    }

    private func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    func readVolume() -> Float {
        guard device != kAudioObjectUnknown else { return 0 }
        var addr = volumeAddress()
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    func readMuted() -> Bool {
        guard device != kAudioObjectUnknown else { return false }
        var addr = muteAddress()
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value == 1
    }

    func setVolume(_ new: Float) {
        guard device != kAudioObjectUnknown else { return }
        var addr = volumeAddress()
        var value = Float32(max(0, min(1, new)))
        let size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &addr) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return }
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
        if value > 0 && readMuted() { setMuted(false) }
        publish()
    }

    func setMuted(_ new: Bool) {
        guard device != kAudioObjectUnknown else { return }
        var addr = muteAddress()
        var value: UInt32 = new ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &addr) else { return }
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
        publish()
    }

    private func listenAddresses() -> [AudioObjectPropertyAddress] {
        var list = [volumeAddress(), muteAddress()]
        // El volumen "virtual" no siempre notifica; la escala por canal sí.
        for element in [UInt32(0), 1, 2] {
            list.append(AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element))
        }
        return list
    }

    private func removeListener() {
        guard let block = listenerBlock, listenerDevice != kAudioObjectUnknown else { return }
        for var addr in listenAddresses() {
            AudioObjectRemovePropertyListenerBlock(listenerDevice, &addr, DispatchQueue.main, block)
        }
        listenerBlock = nil
        listenerDevice = kAudioObjectUnknown
    }

    private func installListener() {
        guard device != kAudioObjectUnknown else { return }
        removeListener()
        listenerDevice = device
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.sawListener {
                    self.sawListener = true
                    IslandDebug.log("CoreAudio notifica el volumen: se deja de sondear")
                    self.refreshPolling()   // el listener funciona: fuera el sondeo
                }
                self.publish(notify: true)
            }
        }
        listenerBlock = block
        for var addr in listenAddresses() where AudioObjectHasProperty(device, &addr) {
            AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main, block)
        }
    }

    func publish(notify: Bool = false) {
        let v = readVolume()
        let m = readMuted()
        let changed = abs(v - volume) > 0.0001 || m != muted
        volume = v
        muted = m
        if notify && changed { onChange?(v, m) }
    }
}

// MARK: - Brillo de la pantalla interna (DisplayServices, cargado dinámicamente)

final class BrightnessMonitor: ObservableObject {
    static let shared = BrightnessMonitor()

    @Published private(set) var brightness: Float = 0
    private(set) var available = false
    var onChange: ((Float) -> Void)?

    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    private var getFn: GetFn?
    private var setFn: SetFn?
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private var sawNotification = false

    private init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        if let handle = dlopen(path, RTLD_LAZY) {
            if let g = dlsym(handle, "DisplayServicesGetBrightness") {
                getFn = unsafeBitCast(g, to: GetFn.self)
            }
            if let s = dlsym(handle, "DisplayServicesSetBrightness") {
                setFn = unsafeBitCast(s, to: SetFn.self)
            }
        }
        available = getFn != nil
        brightness = read()
    }

    private var displayID: CGDirectDisplayID { CGMainDisplayID() }

    func read() -> Float {
        guard let getFn else { return 0 }
        var value: Float = 0
        guard getFn(displayID, &value) == 0 else { return 0 }
        return value
    }

    func setBrightness(_ new: Float) {
        guard let setFn else { return }
        _ = setFn(displayID, max(0, min(1, new)))
        brightness = read()
    }

    /// Sondeo ligero: el brillo no emite notificaciones públicas.
    func start() {
        guard available else { return }
        // El sistema publica un aviso al cambiar el backlight; si llega,
        // dejamos de sondear.
        var token: Int32 = 0
        notify_register_dispatch("com.apple.backlight.changed", &token, DispatchQueue.main) { [weak self] (_: Int32) in
            guard let self else { return }
            if !self.sawNotification {
                self.sawNotification = true
                IslandDebug.log("el sistema notifica el brillo: se deja de sondear")
                self.refreshPolling()
            }
            let v = self.read()
            if abs(v - self.brightness) > 0.002 {
                self.brightness = v
                self.onChange?(v)
            }
        }
        refreshPolling()
        cancellable = Prefs.shared.$liveBrightness
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPolling() }
    }

    private func refreshPolling() {
        timer?.invalidate()
        timer = nil
        guard Prefs.shared.liveBrightness, !sawNotification else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let v = self.read()
            if abs(v - self.brightness) > 0.005 {
                let previous = self.brightness
                self.brightness = v
                if previous > 0 || v > 0 { self.onChange?(v) }
            }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: - Batería

struct BatteryState: Equatable {
    var percent: Int = 100
    var charging: Bool = false
    var plugged: Bool = false
    var timeToFull: Int = -1
    var timeToEmpty: Int = -1
    var present: Bool = false
}

final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()
    @Published private(set) var state = BatteryState()
    /// (nuevo estado, cambió el estado de conexión a corriente)
    var onChange: ((BatteryState, Bool) -> Void)?

    private var timer: Timer?

    private init() { state = read() }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 2
    }

    private func tick() {
        let new = read()
        guard new != state else { return }
        let plugChanged = new.plugged != state.plugged
        state = new
        onChange?(new, plugChanged)
    }

    func read() -> BatteryState {
        var s = BatteryState()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return s }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            s.present = true
            s.percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            s.charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            s.plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            s.timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            s.timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            break
        }
        return s
    }
}

// MARK: - Memoria

enum SystemStats {
    /// Fracción de RAM en uso (0...1) y GB usados.
    static func memoryUsage() -> (fraction: Double, usedGB: Double, totalGB: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS, total > 0 else { return (0, 0, total / 1_073_741_824) }
        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        return (min(1, used / total), used / 1_073_741_824, total / 1_073_741_824)
    }

    /// Espacio libre del disco de arranque en GB.
    static func diskFreeGB() -> (free: Double, total: Double) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) else {
            return (0, 0)
        }
        let free = Double(values.volumeAvailableCapacityForImportantUsage ?? 0) / 1_073_741_824
        let total = Double(values.volumeTotalCapacity ?? 0) / 1_073_741_824
        return (free, total)
    }
}
