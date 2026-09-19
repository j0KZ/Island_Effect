import Foundation
import Testing
@testable import IslandEffectKit

/// La aritmética de las estadísticas.
///
/// Las lecturas en sí (IOKit, Mach) no se pueden probar sin la máquina delante,
/// pero tampoco es ahí donde están los errores: están en lo que se hace con los
/// números. Un contador que se lee sin signo, dos muestras que llegan al revés,
/// una división por cero cuando las muestras caen en el mismo tic. Todos dan un
/// número plausible y equivocado, que es la peor clase de error para un panel
/// que existe justo para que te fíes de lo que dice.
struct CPUUsageTests {

    private static func ticks(user: Double = 0, system: Double = 0,
                              idle: Double = 0, nice: Double = 0) -> SystemStats.CPUTicks {
        SystemStats.CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test("La mitad ocupada es 50 %")
    func halfBusy() {
        let antes = Self.ticks(user: 100, idle: 100)
        let ahora = Self.ticks(user: 150, idle: 150)
        #expect(SystemStats.cpuUsage(from: antes, to: ahora) == 0.5)
    }

    @Test("Se mide entre muestras, no desde que encendiste el Mac")
    func measuresTheInterval() {
        // El kernel entrega totales desde el arranque. Sin restar, lo que sale
        // es el promedio de toda la sesión: un número que no se mueve nunca y
        // que parece que el panel estuviera colgado.
        let antes = Self.ticks(user: 10_000, idle: 90_000)   // 10 % histórico
        let ahora = Self.ticks(user: 10_900, idle: 90_100)   // 90 % en el intervalo
        let uso = SystemStats.cpuUsage(from: antes, to: ahora)
        #expect(uso != nil)
        #expect(abs((uso ?? 0) - 0.9) < 0.0001)
    }

    @Test("El trabajo con prioridad baja también ocupa la CPU")
    func niceCountsAsBusy() {
        // Un respaldo o una indexación corren en `nice`. Sin contarlo, la CPU
        // saldría al 0 % con el ventilador a todo dar.
        let antes = Self.ticks(idle: 100)
        let ahora = Self.ticks(idle: 150, nice: 50)
        #expect(SystemStats.cpuUsage(from: antes, to: ahora) == 0.5)
    }

    @Test("Dos muestras en el mismo tic no dan un número, dan nada")
    func sameInstant() {
        // Es una división por cero. Antes que un NaN en pantalla, nada.
        let iguales = Self.ticks(user: 100, idle: 100)
        #expect(SystemStats.cpuUsage(from: iguales, to: iguales) == nil)
    }

    @Test("Si los contadores retroceden, no se informa nada")
    func countersGoingBackwards() {
        // Pasa con una muestra desordenada o con el contador dando la vuelta.
        // Restando a ciegas saldría un porcentaje negativo o gigante.
        let antes = Self.ticks(user: 500, idle: 500)
        let ahora = Self.ticks(user: 100, idle: 100)
        #expect(SystemStats.cpuUsage(from: antes, to: ahora) == nil)
    }

    @Test("Solo el ocioso retrocediendo tampoco cuela")
    func partialRegression() {
        let antes = Self.ticks(user: 100, idle: 100)
        let ahora = Self.ticks(user: 50, idle: 300)
        // El total sube, pero el ocupado baja: no hay nada sensato que decir.
        #expect(SystemStats.cpuUsage(from: antes, to: ahora) == nil)
    }

    @Test("Nunca se pasa de 100 % ni baja de 0")
    func alwaysInRange() {
        let antes = Self.ticks(user: 0, idle: 0)
        let ahora = Self.ticks(user: 100, idle: 0)
        #expect(SystemStats.cpuUsage(from: antes, to: ahora) == 1)
    }

    @Test("La CPU quieta da 0 %")
    func fullyIdle() {
        let antes = Self.ticks(idle: 100)
        let ahora = Self.ticks(idle: 200)
        #expect(SystemStats.cpuUsage(from: antes, to: ahora) == 0)
    }
}

/// La memoria usada.
struct MemoryTests {

    private static let page: UInt64 = 16_384   // el tamaño en Apple Silicon

    @Test("Usada es activa + reservada + comprimida")
    func usedPages() {
        let pages = SystemStats.MemoryPages(active: 10, wired: 5, compressed: 5,
                                            inactive: 100, free: 100)
        #expect(SystemStats.memoryUsed(pages, pageSize: Self.page) == 20 * Self.page)
    }

    @Test("La inactiva no cuenta")
    func inactiveDoesNotCount() {
        // Son páginas que el sistema recupera al instante si hacen falta.
        // Contándolas, cualquier Mac saldría al 95 % para siempre y el número
        // dejaría de significar nada.
        let poca = SystemStats.MemoryPages(active: 10, wired: 0, compressed: 0, inactive: 0)
        let mucha = SystemStats.MemoryPages(active: 10, wired: 0, compressed: 0, inactive: 10_000)
        #expect(SystemStats.memoryUsed(poca, pageSize: Self.page)
                == SystemStats.memoryUsed(mucha, pageSize: Self.page))
    }

    @Test("La comprimida sí cuenta")
    func compressedCounts() {
        // Es memoria que sigue ocupada, solo que apretada. Sin contarla, un Mac
        // con la memoria llena saldría holgado.
        let sin = SystemStats.MemoryPages(active: 10, wired: 0, compressed: 0)
        let con = SystemStats.MemoryPages(active: 10, wired: 0, compressed: 10)
        #expect(SystemStats.memoryUsed(con, pageSize: Self.page)
                > SystemStats.memoryUsed(sin, pageSize: Self.page))
    }

    @Test("La fracción va de 0 a 1")
    func fraction() {
        #expect(SystemStats.memoryFraction(used: 8_000, total: 16_000) == 0.5)
        #expect(SystemStats.memoryFraction(used: 0, total: 16_000) == 0)
        #expect(SystemStats.memoryFraction(used: 20_000, total: 16_000) == 1)
    }

    @Test("Sin memoria total no se divide por cero")
    func noTotal() {
        #expect(SystemStats.memoryFraction(used: 100, total: 0) == 0)
    }
}

/// La batería: consumo, tiempos y el contador con signo.
struct PowerTests {

    private static func power(mA: Double = -900, mV: Double = 11_200,
                              minutes: Int? = 180, percent: Int = 50,
                              cycles: Int = 12, charging: Bool = false,
                              plugged: Bool = false) -> SystemStats.Power {
        SystemStats.Power(milliamps: mA, millivolts: mV, minutesRemaining: minutes,
                          percent: percent, cycles: cycles, charging: charging, plugged: plugged)
    }

    // MARK: - El contador que da la vuelta

    @Test("Un amperaje de descarga se lee negativo, no gigante")
    func negativeAmperageWrapsAround() {
        // IOKit informa la descarga dando la vuelta a un entero sin signo de 64
        // bits. Leído tal cual son dieciocho trillones de miliamperios; en
        // realidad son −964. Es el error clásico con este registro, y no avisa:
        // sale un consumo absurdo o un cero.
        #expect(SystemStats.signedMilliamps(18_446_744_073_709_550_652) == -964)
    }

    @Test("Un amperaje de carga se lee tal cual")
    func positiveAmperage() {
        #expect(SystemStats.signedMilliamps(1_500) == 1_500)
        #expect(SystemStats.signedMilliamps(0) == 0)
    }

    // MARK: - Watts

    @Test("Los watts son amperios por voltios")
    func wattsFromAmpsAndVolts() {
        // 964 mA a 11,2 V son los 10,8 W medidos en la máquina de verdad.
        let w = SystemStats.watts(Self.power(mA: -964, mV: 11_224))
        #expect(w != nil)
        #expect(abs((w ?? 0) - 10.82) < 0.01)
    }

    @Test("El signo no cambia el consumo")
    func signDoesNotMatter() {
        #expect(SystemStats.watts(Self.power(mA: -900)) == SystemStats.watts(Self.power(mA: 900)))
    }

    @Test("Enchufado no se dice cuánto gasta, porque no se sabe")
    func pluggedInHasNoWatts() {
        // El amperaje pasa a ser el de la CARGA. Separar consumo de carga sí
        // necesita powermetrics con root. Antes que enseñar un número que
        // significa otra cosa, no se enseña ninguno.
        #expect(SystemStats.watts(Self.power(mA: 2_000, plugged: true)) == nil)
        #expect(SystemStats.watts(Self.power(mA: -900, plugged: true, )) == nil)
    }

    @Test("Un amperaje en cero no da 0 W, da nada")
    func zeroAmperage() {
        // Justo al desenchufar, el registro puede venir en cero un instante.
        // Un "0,0 W" sería falso: el Mac nunca gasta cero.
        #expect(SystemStats.watts(Self.power(mA: 0)) == nil)
    }

    @Test("Un voltaje ausente tampoco inventa un número")
    func missingVoltage() {
        #expect(SystemStats.watts(Self.power(mV: 0)) == nil)
    }

    // MARK: - Tiempos

    @Test("Hasta el 20 % sale a proporción de lo que queda")
    func minutesToTwentyPercent() {
        // Los números reales de la máquina: 41 %, 184 minutos hasta agotarse.
        let p = Self.power(minutes: 184, percent: 41)
        #expect(SystemStats.minutesTo(20, power: p) == 94)
    }

    @Test("Por debajo del objetivo, no queda nada")
    func alreadyBelowTarget() {
        #expect(SystemStats.minutesTo(20, power: Self.power(minutes: 30, percent: 15)) == 0)
        #expect(SystemStats.minutesTo(20, power: Self.power(minutes: 30, percent: 20)) == 0)
    }

    @Test("Mientras el sistema calcula, no se estima nada")
    func systemStillEstimating() {
        // Al desenchufar, macOS tarda un par de minutos en dar una estimación.
        // Inventar una propia daría un número que se contradice con el suyo.
        #expect(SystemStats.minutesTo(20, power: Self.power(minutes: nil)) == nil)
        #expect(SystemStats.minutesTo(20, power: Self.power(minutes: 0)) == nil)
    }

    @Test("Enchufado tampoco hay cuenta atrás")
    func pluggedInHasNoCountdown() {
        #expect(SystemStats.minutesTo(20, power: Self.power(plugged: true)) == nil)
    }

    @Test("Llegar al 20 % siempre es antes que agotarse")
    func reachingTwentyComesFirst() {
        for percent in 21...100 {
            let p = Self.power(minutes: 300, percent: percent)
            let hasta20 = SystemStats.minutesTo(20, power: p) ?? 0
            #expect(hasta20 < 300, "al \(percent) % el 20 % llegaría después de agotarse")
        }
    }
}

/// Cómo se escriben los números en pantalla.
struct StatsFormatTests {

    @Test("Sin dato todavía, una raya y no un cero")
    func noDataYet() {
        // Un "0 %" diría que la CPU está parada. Lo cierto es que aún no hay dos
        // muestras que restar, que es otra cosa.
        #expect(StatsFormat.percent(nil) == "—")
        #expect(StatsFormat.percent(0) == "0 %")
    }

    @Test("Los porcentajes se redondean")
    func percentRounds() {
        #expect(StatsFormat.percent(0.179) == "18 %")
        #expect(StatsFormat.percent(1) == "100 %")
    }

    @Test("La memoria se lee en los mismos gigas que dice el resto del Mac")
    func memoryReadsInGigabytes() {
        // Los bytes de verdad de un Mac de 48 GB. En gigas decimales serían
        // 51,5 y saldría "52 GB", contradiciendo a Acerca de este Mac, al
        // Monitor de Actividad y a la caja. Apple cuenta en gigas binarios.
        #expect(StatsFormat.gigabytes(used: 28_690_000_000, total: 51_539_607_552)
                == "26.7 / 48 GB")
    }

    @Test("Los tamaños redondos salen redondos")
    func roundSizes() {
        let giga: UInt64 = 1024 * 1024 * 1024
        #expect(StatsFormat.gigabytes(used: 8 * giga, total: 16 * giga) == "8.0 / 16 GB")
    }

    @Test("Los watts llevan un decimal")
    func wattsHaveOneDecimal() {
        // El consumo baila lo bastante como para que el segundo decimal sea
        // ruido, y sin ninguno no se distinguiría leer de tener veinte pestañas.
        #expect(StatsFormat.watts(9.74) == "9.7 W")
        #expect(StatsFormat.watts(10.82) == "10.8 W")
    }

    @Test("Un tiempo largo se lee en horas")
    func longTimesReadInHours() {
        // "184 min" obliga a dividir mentalmente cada vez que lo miras.
        #expect(StatsFormat.clock(minutes: 184) == "3 h 4 min")
        #expect(StatsFormat.clock(minutes: 60) == "1 h 0 min")
        #expect(StatsFormat.clock(minutes: 59) == "59 min")
        #expect(StatsFormat.clock(minutes: 0) == "0 min")
    }

    @Test("Un tiempo negativo no se escribe en negativo")
    func negativeTimes() {
        #expect(StatsFormat.clock(minutes: -5) == "0 min")
    }
}

/// Los módulos de la isla, ahora que son tres.
struct ModuleTests {

    @Test("Las pestañas salen en su orden, solo las encendidas")
    func availableTabs() {
        #expect(NotchTab.available(music: true, shelf: true, stats: true) == [.music, .shelf, .stats])
        #expect(NotchTab.available(music: true, shelf: false, stats: true) == [.music, .stats])
        #expect(NotchTab.available(music: false, shelf: false, stats: true) == [.stats])
    }

    @Test("El último módulo encendido no se puede apagar")
    func cannotDisableTheLastOne() {
        // Sin ninguno, la isla abierta sería un panel vacío con una barra de
        // pestañas vacía, y no habría forma de recuperarla desde la interfaz.
        #expect(!NotchTab.canDisable(.stats, music: false, shelf: false, stats: true))
        #expect(!NotchTab.canDisable(.music, music: true, shelf: false, stats: false))
        #expect(!NotchTab.canDisable(.shelf, music: false, shelf: true, stats: false))
    }

    @Test("Con dos encendidos, cualquiera de los dos se puede apagar")
    func twoEnabled() {
        #expect(NotchTab.canDisable(.music, music: true, shelf: true, stats: false))
        #expect(NotchTab.canDisable(.shelf, music: true, shelf: true, stats: false))
    }

    @Test("Apagar uno que ya está apagado no es asunto de nadie")
    func alreadyOff() {
        // La interfaz nunca lo pregunta, pero la regla no debe depender de eso.
        #expect(NotchTab.canDisable(.stats, music: true, shelf: false, stats: false))
    }

    @Test("Si la pestaña activa se apaga, se cae en la primera que quede")
    func resolveFallsBack() {
        let quedan = NotchTab.available(music: false, shelf: true, stats: true)
        #expect(NotchTab.resolve(.music, available: quedan) == .shelf)
        #expect(NotchTab.resolve(.stats, available: quedan) == .stats)
    }

    @Test("Cada pestaña tiene su ícono y su nombre")
    func everyTabIsPresentable() {
        for tab in NotchTab.allCases {
            #expect(!tab.symbol.isEmpty)
            #expect(!tab.title.isEmpty)
        }
    }
}

/// El redondeo de las muestras.
///
/// No es cosmético: cada muestra distinta redibuja la isla, y redibujarla
/// significa que el material translúcido vuelve a muestrear lo que tiene
/// detrás, que es lo más caro que hace la app. Leer los cuatro datos cuesta
/// 0,93 ms; dibujarlos, mil veces más. Redondear a lo que se llega a ver hace
/// que haya segundos en los que no se redibuja nada.
struct QuantizeTests {

    @Test("Un porcentaje se redondea al entero que se enseña")
    func percentIsRounded() {
        // 12,3001 % y 12,3002 % pintan el mismo "12 %", y sin redondear eran
        // dos muestras distintas y dos redibujos.
        #expect(StatsMonitor.quantize(0.123001) == StatsMonitor.quantize(0.123002))
        #expect(StatsFormat.percent(StatsMonitor.quantize(0.1234)) == "12 %")
    }

    @Test("Con la máquina quieta, dos segundos seguidos dan la misma muestra")
    func idleMachineDoesNotRedraw() {
        // Es el caso normal: la CPU no se mueve de un segundo a otro.
        let a = StatsMonitor.quantize(0.1201)
        let b = StatsMonitor.quantize(0.1204)
        #expect(a == b)
    }

    @Test("El amperaje se redondea a 10 mA")
    func amperageIsRounded() {
        // El de verdad cambia de unidad CADA segundo, así que la muestra
        // siempre era distinta y la isla siempre se redibujaba, aunque en
        // pantalla dijera lo mismo.
        let base = SystemStats.Power(milliamps: -964, millivolts: 11_224,
                                     minutesRemaining: 184, percent: 41,
                                     cycles: 12, charging: false, plugged: false)
        var movido = base
        movido.milliamps = -961
        #expect(StatsMonitor.quantize(base) == StatsMonitor.quantize(movido))
    }

    @Test("Y el redondeo no mueve el número que se ve")
    func roundingStaysBelowWhatIsShown() {
        // Los watts salen con un decimal: 10 mA a 11 V son 0,11 W, así que el
        // paso queda por debajo de lo que se llega a distinguir... y hay que
        // comprobarlo, porque redondear de más sería falsear la medida.
        let real = SystemStats.Power(milliamps: -964, millivolts: 11_224,
                                     minutesRemaining: 184, percent: 41,
                                     cycles: 12, charging: false, plugged: false)
        let exactos = SystemStats.watts(real) ?? 0
        let redondeados = SystemStats.watts(StatsMonitor.quantize(real)) ?? 0
        #expect(abs(exactos - redondeados) < 0.12)
    }

    @Test("Lo que no es ruido no se toca")
    func meaningfulFieldsSurvive() {
        // El porcentaje, los ciclos y los minutos se enseñan tal cual: si el
        // redondeo los tocara, el panel mentiría.
        let p = SystemStats.Power(milliamps: -964, millivolts: 11_224,
                                  minutesRemaining: 184, percent: 41,
                                  cycles: 12, charging: false, plugged: true)
        let q = StatsMonitor.quantize(p)
        #expect(q.percent == 41)
        #expect(q.cycles == 12)
        #expect(q.minutesRemaining == 184)
        #expect(q.plugged)
    }
}
