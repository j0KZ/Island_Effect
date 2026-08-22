import AppKit
import Combine
import CoreAudio
import AudioToolbox
import IOKit.ps

// MARK: - Volumen del sistema (CoreAudio, API pública)

/// Lectura y escritura del volumen de salida. Ya no vigila cambios: macOS
/// muestra su propio HUD y duplicarlo era gasto puro.
final class VolumeMonitor: ObservableObject {
    static let shared = VolumeMonitor()

    private var device: AudioDeviceID = kAudioObjectUnknown

    private init() { refreshDevice() }

    func start() {
        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.refreshDevice()
        }
    }

    private func refreshDevice() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr {
            device = id
        }
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

    var muted: Bool { readMuted() }

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
        if value > 0, readMuted() { setMuted(false) }
        objectWillChange.send()
    }

    func setMuted(_ new: Bool) {
        guard device != kAudioObjectUnknown else { return }
        var addr = muteAddress()
        var value: UInt32 = new ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &addr) else { return }
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
        objectWillChange.send()
    }
}

// MARK: - Batería

struct BatteryState: Equatable {
    var percent: Int = 100
    var charging: Bool = false
    var plugged: Bool = false
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
            break
        }
        return s
    }
}
