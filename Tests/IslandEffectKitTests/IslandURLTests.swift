import Foundation
import Testing
@testable import IslandEffectKit

/// El puente con Atajos: qué se acepta de una `islandeffect://…` y qué no.
///
/// Todo lo que llega acá lo escribió alguien a mano dentro de un Atajo, y no hay
/// autocompletado ni corrector que lo ayude. Un parámetro con una mayúscula de
/// más, una coma decimal, una ruta con `~`: cada uno de esos fallaría en
/// silencio, porque un Atajo que no hace nada no da ningún error. Esto decide
/// cuánto de eso se perdona.
struct IslandURLTests {

    private static func parse(_ string: String) -> IslandURL.Command? {
        guard let url = URL(string: string) else { return nil }
        return IslandURL.parse(url)
    }

    // MARK: - Avisos

    @Test("Un aviso con su texto")
    func plainNotice() {
        #expect(Self.parse("islandeffect://notice?text=Listo")
                == .notice(text: "Listo", symbol: nil, seconds: nil))
    }

    @Test("Con ícono y duración")
    func noticeWithEverything() {
        let comando = Self.parse("islandeffect://notice?text=Respaldo&icon=externaldrive&seconds=6")
        #expect(comando == .notice(text: "Respaldo", symbol: "externaldrive", seconds: 6))
    }

    @Test("`pill` es lo mismo que `notice`")
    func pillIsAnAlias() {
        // Las dos palabras son razonables para lo mismo, y recordar cuál era la
        // buena seis meses después no lo es.
        #expect(Self.parse("islandeffect://pill?text=Hola") == Self.parse("islandeffect://notice?text=Hola"))
    }

    @Test("Sin texto no hay aviso")
    func noticeNeedsText() {
        // Una píldora vacía asomándose bajo el notch parece un fallo de la app,
        // no un Atajo mal escrito.
        #expect(Self.parse("islandeffect://notice") == nil)
        #expect(Self.parse("islandeffect://notice?text=") == nil)
        #expect(Self.parse("islandeffect://notice?text=%20%20") == nil)
    }

    @Test("Las mayúsculas de los parámetros no importan")
    func parameterNamesAreCaseInsensitive() {
        // Quien escribe un Atajo no tiene por qué acertar las mayúsculas, y un
        // `?Text=` fallando en silencio es lo que hace abandonar la integración.
        #expect(Self.parse("islandeffect://notice?Text=Hola&Icon=star&Seconds=3")
                == .notice(text: "Hola", symbol: "star", seconds: 3))
    }

    @Test("Y el nombre de la acción tampoco")
    func actionIsCaseInsensitive() {
        #expect(Self.parse("islandeffect://NOTICE?text=Hola")
                == .notice(text: "Hola", symbol: nil, seconds: nil))
        #expect(Self.parse("ISLANDEFFECT://notice?text=Hola")
                == .notice(text: "Hola", symbol: nil, seconds: nil))
    }

    @Test("Los acentos, los espacios y los emoji llegan enteros")
    func percentEncoding() {
        let comando = Self.parse("islandeffect://notice?text=Copia%20de%20seguridad%20lista%20%F0%9F%8E%89")
        #expect(comando == .notice(text: "Copia de seguridad lista 🎉", symbol: nil, seconds: nil))
    }

    @Test("Un texto larguísimo se recorta")
    func longTextIsTrimmed() {
        // No cabe en la píldora y tampoco tiene sentido leerlo ahí.
        let largo = String(repeating: "a", count: 500)
        guard case let .notice(text, _, _)? = Self.parse("islandeffect://notice?text=\(largo)") else {
            Issue.record("no se entendió la URL")
            return
        }
        #expect(text.count == IslandURL.maxTextLength)
    }

    // MARK: - El ícono

    @Test("Un ícono inventado se descarta, no se dibuja en blanco")
    func unknownSymbolIsDropped() {
        // Un nombre que no existe deja un hueco donde iba el ícono y el aviso
        // sale descuadrado, sin nada que explique por qué.
        #expect(Self.parse("islandeffect://notice?text=Hola&icon=esto.no.existe")
                == .notice(text: "Hola", symbol: nil, seconds: nil))
    }

    @Test("Un ícono de verdad se conserva")
    func realSymbolSurvives() {
        for nombre in ["star.fill", "checkmark.circle", "bolt"] {
            #expect(IslandURL.symbol(from: nombre) == nombre)
        }
    }

    // MARK: - Números

    @Test("La duración se acota en vez de descartarse")
    func secondsAreClamped() {
        // Quien escribió `seconds=600` quería que durara mucho: darle el máximo
        // se parece más a lo que pidió que ignorarlo y darle lo de siempre.
        #expect(IslandURL.seconds(from: "600") == IslandURL.secondsRange.upperBound)
        #expect(IslandURL.seconds(from: "0") == IslandURL.secondsRange.lowerBound)
        #expect(IslandURL.seconds(from: "-5") == IslandURL.secondsRange.lowerBound)
    }

    @Test("La coma decimal también vale")
    func decimalComma() {
        // Es lo que escribe medio mundo, y lo que devuelven varias acciones de
        // Atajos según el idioma del sistema.
        #expect(IslandURL.seconds(from: "2,5") == 2.5)
        #expect(IslandURL.seconds(from: "2.5") == 2.5)
    }

    @Test("Un número que no es un número no rompe el aviso")
    func garbageNumbers() {
        // El aviso sale igual, con la duración de siempre: perder el texto por
        // una duración mal escrita sería el peor cambio posible.
        #expect(Self.parse("islandeffect://notice?text=Hola&seconds=pronto")
                == .notice(text: "Hola", symbol: nil, seconds: nil))
        #expect(IslandURL.seconds(from: "NaN") == nil)
        #expect(IslandURL.seconds(from: "") == nil)
    }

    // MARK: - La repisa

    @Test("Un archivo a la repisa")
    func shelfCommand() {
        #expect(Self.parse("islandeffect://shelf?path=/tmp/informe.pdf")
                == .shelf(path: "/tmp/informe.pdf", minutes: nil))
    }

    @Test("Con minutos, entra de paso")
    func temporaryShelfItem() {
        #expect(Self.parse("islandeffect://shelf?path=/tmp/a.png&minutes=10")
                == .shelf(path: "/tmp/a.png", minutes: 10))
    }

    @Test("Una ruta con espacios llega entera")
    func pathWithSpaces() {
        #expect(Self.parse("islandeffect://shelf?path=/tmp/mi%20informe.pdf")
                == .shelf(path: "/tmp/mi informe.pdf", minutes: nil))
    }

    @Test("Sin ruta no hay nada que guardar")
    func shelfNeedsAPath() {
        #expect(Self.parse("islandeffect://shelf") == nil)
        #expect(Self.parse("islandeffect://shelf?path=") == nil)
    }

    // MARK: - Abrir y cerrar

    @Test("Abrir y cerrar la isla")
    func openAndClose() {
        #expect(Self.parse("islandeffect://open") == .open)
        #expect(Self.parse("islandeffect://close") == .close)
    }

    // MARK: - Lo que no se acepta

    @Test("Una acción desconocida no hace nada")
    func unknownAction() {
        #expect(Self.parse("islandeffect://loquesea") == nil)
        #expect(Self.parse("islandeffect://") == nil)
    }

    @Test("Otro esquema no es asunto nuestro")
    func otherSchemes() {
        // Vale la pena comprobarlo: la app recibe las URLs que le manda el
        // sistema, y responder a un `https://` sería un fallo serio.
        #expect(Self.parse("https://ejemplo.com/notice?text=Hola") == nil)
        #expect(Self.parse("file:///tmp/notice?text=Hola") == nil)
        #expect(Self.parse("notice?text=Hola") == nil)
    }

    @Test("Una barra de más sigue funcionando")
    func extraSlash() {
        // `islandeffect:///notice` es fácil de escribir sin querer y deja la
        // acción en la ruta en vez de en el host.
        #expect(Self.parse("islandeffect:///notice?text=Hola")
                == .notice(text: "Hola", symbol: nil, seconds: nil))
    }

    @Test("Los parámetros vacíos se ignoran, no se toman como puestos")
    func emptyParameters() {
        #expect(Self.parse("islandeffect://notice?text=Hola&icon=&seconds=")
                == .notice(text: "Hola", symbol: nil, seconds: nil))
    }

    @Test("Un parámetro repetido no rompe la lectura")
    func repeatedParameters() {
        let comando = Self.parse("islandeffect://notice?text=Uno&text=Dos")
        #expect(comando != nil)
    }
}
