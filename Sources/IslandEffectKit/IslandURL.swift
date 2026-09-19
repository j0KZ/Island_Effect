import AppKit
import Foundation

/// El puente con Atajos de macOS: `islandeffect://…`.
///
/// Va al revés de lo que suelen ofrecer estas apps. Lo normal es "la isla
/// ejecuta un Atajo", que solo sirve si ya tienes Atajos hechos. Esto es lo
/// contrario: cualquier Atajo puede mandarle cosas a la isla, y así la isla se
/// convierte en la salida de todo lo que ya tengas automatizado. Un respaldo que
/// termina, un archivo que cae en la repisa desde un flujo del Finder, un número
/// que quieres ver sin abrir nada.
///
/// Se eligió un esquema de URL y no App Intents, que es la forma oficial. App
/// Intents necesita un paso de compilación que hace Xcode y que este proyecto,
/// que es SwiftPM puro con un `build.sh`, no ejecuta. Una URL la llama Atajos
/// con "Abrir URL", que existe desde siempre y funciona desde el primer día.
enum IslandURL {
    static let scheme = "islandeffect"

    enum Command: Equatable {
        /// Un aviso en la píldora bajo el notch.
        case notice(text: String, symbol: String?, seconds: Double?)
        /// Un archivo a la repisa. `minutes` lo deja de paso, como una captura.
        case shelf(path: String, minutes: Double?)
        case open
        case close
    }

    /// Qué pide esta URL, o `nil` si no se entiende.
    ///
    /// No lanza ni avisa: una URL mal escrita en un Atajo no debe hacer nada, y
    /// desde luego no debe abrir un panel con un texto vacío.
    static func parse(_ url: URL) -> Command? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        // El "host" es la acción. En `islandeffect://pill?...` es "pill"; si
        // alguien escribe `islandeffect:///pill` viene en la ruta.
        let action = (url.host ?? url.pathComponents.first { $0 != "/" } ?? "").lowercased()
        let query = parameters(of: url)

        switch action {
        case "notice", "pill":
            // Sin texto no hay aviso: una píldora vacía asomándose bajo el notch
            // parece un fallo de la app, no un Atajo mal escrito.
            guard let text = query["text"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return .notice(text: String(text.prefix(maxTextLength)),
                           symbol: query["icon"].flatMap(symbol(from:)),
                           seconds: query["seconds"].flatMap(seconds(from:)))
        case "shelf", "drop":
            guard let path = query["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else { return nil }
            return .shelf(path: path, minutes: query["minutes"].flatMap(minutes(from:)))
        case "open":
            return .open
        case "close":
            return .close
        default:
            return nil
        }
    }

    /// Lo que se enseña en Preferencias, para poder copiarlo a un Atajo sin
    /// tener que ir a buscar la documentación.
    static let examples = [
        "islandeffect://notice?text=Respaldo%20listo&icon=checkmark.circle",
        "islandeffect://notice?text=Hola&seconds=6",
        "islandeffect://shelf?path=/tmp/informe.pdf",
        "islandeffect://shelf?path=/tmp/captura.png&minutes=10",
        "islandeffect://open",
        "islandeffect://close"
    ]

    /// Un texto larguísimo no cabe en la píldora y tampoco tiene sentido leerlo
    /// ahí: se recorta antes de llegar a la vista.
    static let maxTextLength = 120

    static let secondsRange: ClosedRange<Double> = 1...30
    static let minutesRange: ClosedRange<Double> = 1...120

    /// Los parámetros, con las claves en minúsculas.
    ///
    /// Quien escribe un Atajo no tiene por qué acertar las mayúsculas, y
    /// `?Text=` fallando en silencio es exactamente el tipo de cosa que hace
    /// abandonar una integración.
    static func parameters(of url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        var out: [String: String] = [:]
        for item in items {
            guard let value = item.value, !value.isEmpty else { continue }
            out[item.name.lowercased()] = value
        }
        return out
    }

    /// Solo se aceptan símbolos que existan de verdad.
    ///
    /// Un nombre inventado deja un hueco en blanco donde debería ir el ícono, y
    /// el aviso sale descuadrado sin que nada explique por qué.
    static func symbol(from raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else {
            return nil
        }
        return name
    }

    static func seconds(from raw: String) -> Double? {
        clamped(raw, to: secondsRange)
    }

    static func minutes(from raw: String) -> Double? {
        clamped(raw, to: minutesRange)
    }

    /// Un número fuera de rango se acota en vez de descartarse: quien escribió
    /// `seconds=600` quería que durara mucho, y darle el máximo se parece más a
    /// lo que pidió que ignorarlo y darle lo de siempre.
    private static func clamped(_ raw: String, to range: ClosedRange<Double>) -> Double? {
        // La coma decimal es lo que escribe medio mundo, y lo que devuelven
        // varias acciones de Atajos según el idioma del sistema.
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
