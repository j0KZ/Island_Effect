import SwiftUI
import AppKit
import Combine

/// Muestrea la máquina mientras la pestaña está a la vista, y solo entonces.
///
/// En reposo no corre nada. La isla pasa la mayor parte del día cerrada y un
/// sondeo permanente para un panel que nadie está mirando es justo el tipo de
/// gasto que esta app evita en todo lo demás.
@MainActor
final class StatsMonitor: ObservableObject {
    static let shared = StatsMonitor()

    /// Todo lo que se mide, junto.
    ///
    /// Junto y no en cuatro propiedades sueltas por una razón medida: cada
    /// `@Published` que cambia dispara un redibujo, y redibujar la isla
    /// significa que el material translúcido vuelve a muestrear lo que tiene
    /// detrás, que es lo más caro que hace esta app. Cuatro propiedades eran
    /// hasta cuatro redibujos por segundo para enseñar los mismos cuatro
    /// números. Leer los datos cuesta 0,93 ms; dibujarlos, mil veces más.
    ///
    /// Es `Equatable` para lo otro: si en este segundo no cambió nada de lo que
    /// se ve, no se redibuja nada.
    struct Snapshot: Equatable {
        var cpu: Double?
        var memory: Memory?
        var gpu: Double?
        var power: SystemStats.Power?
    }

    struct Memory: Equatable {
        var used: UInt64
        var total: UInt64
    }

    @Published private(set) var snapshot = Snapshot()

    var cpu: Double? { snapshot.cpu }
    var memory: Memory? { snapshot.memory }
    var gpu: Double? { snapshot.gpu }
    var power: SystemStats.Power? { snapshot.power }

    private var timer: Timer?
    private var lastTicks: SystemStats.CPUTicks?
    private var watchers = 0
    /// Una instancia con números puestos a mano no se pone a muestrear.
    private let frozen: Bool

    init() { frozen = false }

    /// Para las vistas previas, que corren en un sandbox donde las llamadas
    /// Mach —CPU, memoria, GPU— no contestan. Sin esto, la única forma de
    /// revisar cómo queda el panel sería lanzando la app.
    init(cpu: Double?, memory: Memory?, gpu: Double?, power: SystemStats.Power?) {
        frozen = true
        snapshot = Snapshot(cpu: cpu, memory: memory, gpu: gpu, power: power)
    }

    /// Una vez por segundo. Más rápido no se nota —los números no cambian tanto—
    /// y más lento hace que el porcentaje de CPU parezca colgado.
    private let interval: TimeInterval = 1

    func start() {
        guard !frozen else { return }
        watchers += 1
        guard timer == nil else { return }
        // La primera muestra de CPU no da porcentaje: hace falta una anterior
        // con la que restar. Se toma ya, así el primer tic sí tiene algo.
        lastTicks = SystemStats.readCPU()
        sample()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        guard !frozen else { return }
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
        lastTicks = nil
    }

    private func sample() {
        var next = snapshot

        if let now = SystemStats.readCPU() {
            if let before = lastTicks {
                next.cpu = SystemStats.cpuUsage(from: before, to: now).map(Self.quantize)
            }
            lastTicks = now
        }
        if let pages = SystemStats.readMemory() {
            next.memory = Memory(used: SystemStats.memoryUsed(pages, pageSize: UInt64(vm_kernel_page_size)),
                                 total: ProcessInfo.processInfo.physicalMemory)
        }
        next.gpu = SystemStats.readGPU()
        next.power = SystemStats.readPower().map(Self.quantize)

        // Un solo cambio, y solo si de verdad cambió algo.
        guard next != snapshot else { return }
        snapshot = next
    }

    /// Los porcentajes se redondean al entero que se va a enseñar.
    ///
    /// Sin esto, un 12,3001 % y un 12,3002 % son valores distintos y obligan a
    /// redibujar la isla entera para pintar el mismo "12 %". Con la máquina
    /// tranquila, que es casi siempre, así hay segundos en los que no se
    /// redibuja nada.
    nonisolated static func quantize(_ fraction: Double) -> Double {
        (fraction * 100).rounded() / 100
    }

    /// Lo mismo con la batería, que es la que nunca se está quieta.
    ///
    /// El amperaje cambia de unidad cada segundo, así que la muestra SIEMPRE
    /// era distinta y la isla SIEMPRE se redibujaba, aunque en pantalla dijera
    /// lo mismo. Se redondea a lo que se llega a ver: los watts salen con un
    /// decimal, y 10 mA a 11 V son 0,11 W, así que con este paso el número
    /// mostrado no se mueve por ruido.
    nonisolated static func quantize(_ power: SystemStats.Power) -> SystemStats.Power {
        var out = power
        out.milliamps = (power.milliamps / 10).rounded() * 10
        out.millivolts = (power.millivolts / 10).rounded() * 10
        return out
    }
}

struct StatsView: View {
    @ObservedObject private var stats: StatsMonitor

    /// Sin valor por omisión: un `= .shared` se evalúa fuera del actor
    /// principal y Swift 6 lo rechaza. Lo pasa quien la construye.
    init(monitor: StatsMonitor) {
        _stats = ObservedObject(wrappedValue: monitor)
    }

    var body: some View {
        GeometryReader { geo in
            let density = PanelLayout.density(contentHeight: geo.size.height)
            VStack(alignment: .leading, spacing: density.isTiny ? 5 : 9) {
                meters(density)
                if !density.isTiny { Divider().overlay(Color.white.opacity(0.08)) }
                battery(density)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    /// Las tres filas salen siempre, con una raya mientras no hay dato.
    ///
    /// Antes se insertaban a medida que llegaban las lecturas, y el panel se
    /// reacomodaba solo en el primer segundo: las filas se cruzaban a media
    /// animación y una quedaba encima de otra. Aparte de feo, hace dudar de
    /// todo lo que dice un panel cuyo trabajo es que te fíes de sus números.
    @ViewBuilder
    private func meters(_ density: PanelLayout.Density) -> some View {
        Meter(title: "CPU", fraction: stats.cpu,
              value: StatsFormat.percent(stats.cpu), compact: density.isCompact)
        Meter(title: "Memory",
              fraction: stats.memory.map {
                  SystemStats.memoryFraction(used: $0.used, total: $0.total)
              },
              value: stats.memory.map {
                  StatsFormat.gigabytes(used: $0.used, total: $0.total)
              } ?? "—",
              compact: density.isCompact)
        if !density.isTiny {
            Meter(title: "GPU", fraction: stats.gpu,
                  value: StatsFormat.percent(stats.gpu), compact: density.isCompact)
        }
    }

    @ViewBuilder
    private func battery(_ density: PanelLayout.Density) -> some View {
        if let power = stats.power {
            // Con el panel al mínimo todo va en UNA fila. Apilado ocupaba más
            // alto del que hay, y el bloque terminaba pegado al borde de la
            // isla, sin aire por debajo.
            let stacked = !density.isTiny
            HStack(alignment: .firstTextBaseline, spacing: density.isCompact ? 10 : 16) {
                // Los watts van primero y grandes: es el único número de acá que
                // no se puede ver en ninguna otra parte del sistema.
                headline(power, density: density, stacked: stacked)

                Spacer(minLength: 6)

                if stacked {
                    VStack(alignment: .trailing, spacing: 2) {
                        times(power, showCycles: !density.isCompact)
                    }
                } else {
                    HStack(spacing: 12) {
                        times(power, showCycles: false)
                    }
                }
            }
        }
    }

    /// El número grande: los watts, o el porcentaje si está enchufado.
    @ViewBuilder
    private func headline(_ power: SystemStats.Power, density: PanelLayout.Density,
                          stacked: Bool) -> some View {
        let size: CGFloat = density.isTiny ? 15 : (density.isCompact ? 16 : 20)
        let big = SystemStats.watts(power).map(StatsFormat.watts) ?? "\(power.percent) %"
        // Enchufado no se puede saber el consumo: el amperaje es el de la carga.
        // Se dice, en vez de enseñar un número que significa otra cosa.
        let small: LocalizedStringKey = SystemStats.watts(power) != nil
            ? "right now"
            : (power.charging ? "charging" : "plugged in")

        if stacked {
            VStack(alignment: .leading, spacing: 0) {
                Text(big)
                    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                Text(small)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(big)
                    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                Text(small)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func times(_ power: SystemStats.Power, showCycles: Bool) -> some View {
        if let toEmpty = power.minutesRemaining {
            Line(label: "empty", value: StatsFormat.clock(minutes: toEmpty))
        }
        if let toLow = SystemStats.minutesTo(20, power: power) {
            Line(label: "20 %", value: StatsFormat.clock(minutes: toLow))
        }
        if showCycles {
            Line(label: "cycles", value: "\(power.cycles)")
        }
    }

    private struct Line: View {
        let label: LocalizedStringKey
        let value: String
        var body: some View {
            HStack(spacing: 6) {
                // Nada por debajo de 10,5: a 9 puntos, "20 %" y "se agota" no se
                // leían de un vistazo, que es la única forma en que se mira este
                // panel. Eran las únicas letras de toda la app a ese tamaño.
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// Una medida con su barra.
struct Meter: View {
    let title: LocalizedStringKey
    /// `nil` mientras no hay dos muestras con las que comparar.
    var fraction: Double?
    var value: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: compact ? 9.5 : 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: compact ? 46 : 54, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * (fraction ?? 0))
                }
            }
            .frame(height: compact ? 4 : 5)
            Text(value)
                .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold,
                              design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: compact ? 62 : 80, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
    }

    /// Verde casi siempre, ámbar cuando aprieta, rojo cuando ya molesta. Los
    /// cortes son altos a propósito: una barra que se pone roja al 60 % enseña
    /// a ignorarla.
    private var tint: Color {
        switch fraction ?? 0 {
        case ..<0.7: return .green.opacity(0.75)
        case ..<0.9: return .orange.opacity(0.8)
        default: return .red.opacity(0.8)
        }
    }
}

/// Cómo se escribe cada número.
///
/// Aparte de la vista porque es donde están las decisiones que se pueden
/// equivocar: cuántos decimales, qué pasa mientras no hay dato, y que un tiempo
/// de 184 minutos se lea "3 h 4 min" y no "184 min".
enum StatsFormat {

    /// Sin dato todavía, una raya. Un "0 %" sería mentira: no es que la CPU
    /// esté parada, es que aún no hay dos muestras que restar.
    nonisolated static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((fraction * 100).rounded())) %"
    }

    /// En gigas binarios, aunque se escriba "GB".
    ///
    /// Es lo que hace Apple en todas partes: un Mac de 48 GB tiene 51.539.607.552
    /// bytes, que en gigas decimales son 51,5 y se redondean a 52. Un panel que
    /// dijera "52 GB" en un Mac que en la caja, en Acerca de este Mac y en el
    /// Monitor de Actividad dice 48, parecería roto, y con razón.
    nonisolated static func gigabytes(used: UInt64, total: UInt64) -> String {
        let giga = 1024.0 * 1024 * 1024
        return String(format: "%.1f / %.0f GB", Double(used) / giga, Double(total) / giga)
    }

    /// Un decimal: el consumo baila lo suficiente como para que el segundo sea
    /// ruido, y sin ninguno no se notaría la diferencia entre estar leyendo y
    /// tener veinte pestañas abiertas.
    nonisolated static func watts(_ w: Double) -> String {
        String(format: "%.1f W", w)
    }

    nonisolated static func clock(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(max(0, minutes)) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
