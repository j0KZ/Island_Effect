import Foundation
import IOKit
import IOKit.ps

/// Lo que la máquina está haciendo ahora mismo: CPU, memoria, GPU y batería.
///
/// Todo sale de APIs que no piden ningún permiso y no necesitan root. Se
/// descartó `powermetrics`, que es lo que casi todo el mundo usa para esto:
/// pide root, y una app de la barra de menús que pide la contraseña de
/// administrador para enseñar un número no es una app, es un problema.
///
/// La aritmética vive en funciones puras a las que se les pasan los números
/// crudos. Es lo único de esto que se puede comprobar sin el hardware delante,
/// y es justo donde están los errores: un contador que da la vuelta, una
/// división por cero cuando la máquina lleva despierta un segundo, o una
/// resta entre dos muestras que llegan al revés.
enum SystemStats {

    // MARK: - CPU

    /// Los tics acumulados que devuelve el kernel, ya sumados entre núcleos.
    struct CPUTicks: Equatable {
        var user: Double = 0
        var system: Double = 0
        var idle: Double = 0
        var nice: Double = 0

        var total: Double { user + system + idle + nice }
        var busy: Double { user + system + nice }
    }

    /// Cuánta CPU se usó ENTRE dos muestras.
    ///
    /// El kernel entrega totales desde el arranque, no un porcentaje: sin restar
    /// dos muestras, lo que sale es el promedio desde que encendiste el Mac, que
    /// no se mueve nunca y parece que estuviera roto.
    static func cpuUsage(from previous: CPUTicks, to current: CPUTicks) -> Double? {
        let elapsed = current.total - previous.total
        // Dos muestras demasiado juntas caen en el mismo tic: sin esto, una
        // división por cero. Y si los contadores retroceden (una muestra que
        // llegó desordenada, o el contador dando la vuelta), no hay nada que
        // informar: mejor callarse que enseñar un número inventado.
        guard elapsed > 0 else { return nil }
        let busy = current.busy - previous.busy
        guard busy >= 0 else { return nil }
        return min(1, max(0, busy / elapsed))
    }

    // MARK: - Memoria

    /// Las páginas de memoria que informa el kernel.
    struct MemoryPages: Equatable {
        var active: UInt64 = 0
        var wired: UInt64 = 0
        var compressed: UInt64 = 0
        var inactive: UInt64 = 0
        var free: UInt64 = 0
    }

    /// Lo que el Monitor de Actividad llama "memoria usada": lo que está en uso
    /// de verdad, sin contar lo que el sistema tiene guardado por si acaso.
    ///
    /// La inactiva no cuenta: son páginas que se pueden recuperar al instante si
    /// hace falta. Contarlas daría un 95 % permanente en cualquier Mac y no
    /// significaría nada.
    static func memoryUsed(_ pages: MemoryPages, pageSize: UInt64) -> UInt64 {
        (pages.active + pages.wired + pages.compressed) * pageSize
    }

    /// La fracción usada, para la barra.
    static func memoryFraction(used: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }

    // MARK: - Batería

    struct Power: Equatable {
        /// Negativo descargando, positivo cargando. Lo que informa el sistema.
        var milliamps: Double
        var millivolts: Double
        /// Minutos que el sistema estima, o `nil` si todavía está calculando.
        var minutesRemaining: Int?
        var percent: Int
        var cycles: Int
        var charging: Bool
        var plugged: Bool
    }

    /// El amperaje viene de IOKit como un entero SIN signo de 64 bits, y la
    /// descarga se representa dando la vuelta al contador.
    ///
    /// Leerlo tal cual da 18.446.744.073.709.550.652 miliamperios, que son
    /// dieciocho trillones y en realidad es −964. Es el error clásico con este
    /// registro y no avisa de nada: sale un consumo absurdo, o cero.
    static func signedMilliamps(_ raw: UInt64) -> Double {
        raw > UInt64(Int64.max) ? Double(Int64(bitPattern: raw)) : Double(raw)
    }

    /// Los watts que está gastando la máquina ahora mismo.
    ///
    /// Solo se puede saber DESCARGANDO. Enchufado, el amperaje es el de la
    /// carga, no el del consumo, y separar los dos sí necesita `powermetrics`
    /// con root. Antes que enseñar un número que significa otra cosa, no se
    /// enseña ninguno.
    static func watts(_ power: Power) -> Double? {
        guard !power.plugged else { return nil }
        let amps = abs(power.milliamps) / 1000
        let volts = power.millivolts / 1000
        let w = amps * volts
        guard w.isFinite, w > 0 else { return nil }
        return w
    }

    /// Cuánto queda para llegar a cierto porcentaje, al ritmo de ahora.
    ///
    /// El sistema estima cuánto falta para agotarse; lo de "hasta el 20 %" se
    /// saca de ahí a proporción, que es lo mismo que hace la estimación por
    /// dentro y evita inventar un segundo modelo que diría otra cosa.
    static func minutesTo(_ target: Int, power: Power) -> Int? {
        guard !power.plugged else { return nil }
        guard let remaining = power.minutesRemaining, remaining > 0 else { return nil }
        guard power.percent > target else { return 0 }
        let usable = Double(power.percent - target) / Double(power.percent)
        return Int((Double(remaining) * usable).rounded())
    }

    // MARK: - Lecturas del sistema

    static func readCPU() -> CPUTicks? {
        var count = mach_msg_type_number_t(0)
        var cpus = natural_t(0)
        var info: processor_info_array_t?
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpus, &info, &count) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        }

        var ticks = CPUTicks()
        for cpu in 0..<Int(cpus) {
            let base = cpu * Int(CPU_STATE_MAX)
            ticks.user += Double(info[base + Int(CPU_STATE_USER)])
            ticks.system += Double(info[base + Int(CPU_STATE_SYSTEM)])
            ticks.idle += Double(info[base + Int(CPU_STATE_IDLE)])
            ticks.nice += Double(info[base + Int(CPU_STATE_NICE)])
        }
        return ticks
    }

    static func readMemory() -> MemoryPages? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MemoryPages(active: UInt64(stats.active_count),
                           wired: UInt64(stats.wire_count),
                           compressed: UInt64(stats.compressor_page_count),
                           inactive: UInt64(stats.inactive_count),
                           free: UInt64(stats.free_count))
    }

    /// Uso de la GPU, de 0 a 1.
    ///
    /// Sale del registro del acelerador, que es lectura pública: `powermetrics`
    /// daría lo mismo y pediría root.
    static func readGPU() -> Double? {
        var iterator = io_iterator_t()
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any],
                  let use = stats["Device Utilization %"] as? Int else { continue }
            // Con GPU integrada y discreta se queda la más ocupada: es la que
            // explica por qué el ventilador está sonando.
            best = max(best ?? 0, Double(use) / 100)
        }
        return best
    }

    static func readPower() -> Power? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else { return nil }

        let raw = (dict["Amperage"] as? NSNumber)?.uint64Value ?? 0
        let minutes = (dict["TimeRemaining"] as? Int).flatMap { $0 > 0 && $0 < 60 * 24 ? $0 : nil }
        return Power(milliamps: signedMilliamps(raw),
                     millivolts: Double((dict["Voltage"] as? Int) ?? 0),
                     minutesRemaining: minutes,
                     percent: (dict["CurrentCapacity"] as? Int) ?? 0,
                     cycles: (dict["CycleCount"] as? Int) ?? 0,
                     charging: (dict["IsCharging"] as? Bool) ?? false,
                     plugged: (dict["ExternalConnected"] as? Bool) ?? false)
    }
}
