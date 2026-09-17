import Foundation
import IOKit.ps
import Testing
@testable import IslandEffectKit

/// Pruebas de cómo se interpreta lo que IOKit cuenta de la batería. Se le pasan
/// descripciones de mentira, así la prueba vale igual en un Mac de escritorio.
struct BatteryMonitorTests {

    private static func source(type: String = kIOPSInternalBatteryType,
                               current: Int = 50, max: Int = 100,
                               charging: Bool = false, ac: Bool = false) -> [String: Any] {
        [kIOPSTypeKey: type,
         kIOPSCurrentCapacityKey: current,
         kIOPSMaxCapacityKey: max,
         kIOPSIsChargingKey: charging,
         kIOPSPowerSourceStateKey: ac ? kIOPSACPowerValue : kIOPSBatteryPowerValue]
    }

    @Test("Sin batería no se inventa una")
    func noBattery() {
        // Un Mac de escritorio: la lista viene vacía.
        let s = BatteryMonitor.battery(from: [])
        #expect(!s.present)
    }

    @Test("El porcentaje sale de la capacidad, no del número crudo")
    func percentIsRelative() {
        // 42 de 84 es media batería, aunque el número diga 42.
        let s = BatteryMonitor.battery(from: [Self.source(current: 42, max: 84)])
        #expect(s.present)
        #expect(s.percent == 50)
    }

    @Test("El porcentaje se redondea al entero más cercano")
    func percentRounds() {
        #expect(BatteryMonitor.battery(from: [Self.source(current: 2, max: 3)]).percent == 67)
        #expect(BatteryMonitor.battery(from: [Self.source(current: 1, max: 3)]).percent == 33)
    }

    @Test("Enchufada y cargando son cosas distintas")
    func pluggedAndCharging() {
        // Con la batería llena, el Mac sigue enchufado pero deja de cargar.
        let llena = BatteryMonitor.battery(from: [Self.source(current: 100, charging: false, ac: true)])
        #expect(llena.plugged)
        #expect(!llena.charging)

        let cargando = BatteryMonitor.battery(from: [Self.source(current: 30, charging: true, ac: true)])
        #expect(cargando.plugged)
        #expect(cargando.charging)

        let suelta = BatteryMonitor.battery(from: [Self.source(current: 30, ac: false)])
        #expect(!suelta.plugged)
    }

    @Test("Los teclados y mouse con batería no cuentan")
    func ignoresOtherPowerSources() {
        // IOKit lista también accesorios: solo interesa la batería interna.
        let s = BatteryMonitor.battery(from: [
            Self.source(type: kIOPSUPSType, current: 10, max: 100),
            Self.source(current: 80, max: 100, ac: true)
        ])
        #expect(s.percent == 80)
        #expect(s.plugged)
    }

    @Test("Una capacidad máxima imposible no divide por cero")
    func zeroCapacity() {
        let s = BatteryMonitor.battery(from: [Self.source(current: 77, max: 0)])
        #expect(s.present)
        #expect(s.percent == 77)
    }

    @Test("Si falta un dato, se asume lo más conservador")
    func missingFields() {
        let s = BatteryMonitor.battery(from: [[kIOPSTypeKey: kIOPSInternalBatteryType]])
        #expect(s.present)
        #expect(s.percent == 0)
        #expect(!s.charging)
        #expect(!s.plugged)
    }
}
