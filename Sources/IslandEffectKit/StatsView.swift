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

    @Published private(set) var cpu: Double?
    @Published private(set) var memory: (used: UInt64, total: UInt64)?
    @Published private(set) var gpu: Double?
    @Published private(set) var power: SystemStats.Power?

    private var timer: Timer?
    private var lastTicks: SystemStats.CPUTicks?
    private var watchers = 0
    /// Una instancia con números puestos a mano no se pone a muestrear.
    private let frozen: Bool

    init() { frozen = false }

    /// Para las vistas previas, que corren en un sandbox donde las llamadas
    /// Mach —CPU, memoria, GPU— no contestan. Sin esto, la única forma de
    /// revisar cómo queda el panel sería lanzando la app.
    init(cpu: Double?, memory: (used: UInt64, total: UInt64)?, gpu: Double?,
         power: SystemStats.Power?) {
        frozen = true
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.power = power
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
        if let now = SystemStats.readCPU() {
            if let before = lastTicks { cpu = SystemStats.cpuUsage(from: before, to: now) }
            lastTicks = now
        }
        if let pages = SystemStats.readMemory() {
            let used = SystemStats.memoryUsed(pages, pageSize: UInt64(vm_kernel_page_size))
            memory = (used, ProcessInfo.processInfo.physicalMemory)
        }
        gpu = SystemStats.readGPU()
        power = SystemStats.readPower()
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
            HStack(alignment: .firstTextBaseline, spacing: density.isCompact ? 10 : 16) {
                // Los watts van primero y grandes: es el único número de acá que
                // no se puede ver en ninguna otra parte del sistema.
                if let watts = SystemStats.watts(power) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(StatsFormat.watts(watts))
                            .font(.system(size: density.isCompact ? 16 : 20, weight: .semibold,
                                          design: .rounded).monospacedDigit())
                        Text("right now")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(power.percent) %")
                            .font(.system(size: density.isCompact ? 16 : 20, weight: .semibold,
                                          design: .rounded).monospacedDigit())
                        // Enchufado no se puede saber el consumo: el amperaje es
                        // el de la carga. Se dice, en vez de enseñar un número
                        // que significa otra cosa.
                        Text(power.charging ? "charging" : "plugged in")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    if let toEmpty = power.minutesRemaining {
                        Line(label: "empty", value: StatsFormat.clock(minutes: toEmpty))
                    }
                    if let toLow = SystemStats.minutesTo(20, power: power) {
                        Line(label: "20 %", value: StatsFormat.clock(minutes: toLow))
                    }
                    if !density.isCompact {
                        Line(label: "cycles", value: "\(power.cycles)")
                    }
                }
            }
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
