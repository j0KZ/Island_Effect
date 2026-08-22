# Island Effect

Convierte el notch del MacBook en una isla interactiva, al estilo de
[NotchNook](https://lo.cafe/notchnook), pero nativa, propia y sin licencia.

App de macOS en Swift + SwiftUI, sin dependencias externas. Vive en la barra de
menús (`LSUIElement`), dibuja un panel flotante encima del notch y se expande al
pasar el mouse.

![tabs](docs/preview.png)

## Qué hace

**Isla que se expande**
- En reposo es indistinguible del notch. Al pasar el mouse se abre con un
  resorte tipo Dynamic Island; al salir se cierra sola.
- Clic en el notch: la deja abierta mientras trabajas dentro; otro clic la cierra.
- Al abrirse, el panel **cuelga por debajo de la barra de menús**: en esa fila
  solo queda el notch, así que los íconos de tus otras apps siguen visibles.
- La ventana solo acepta clics mientras el puntero está sobre la isla
  (`ignoresMouseEvents`): todo lo demás llega a la barra de menús como si la
  isla no existiera.
- **Liquid Glass del sistema** (`glassEffect`, macOS 26) teñido con el color
  dominante de la carátula que esté sonando; en macOS 14–15 cae a
  `NSVisualEffectView`.
- Contorno especular alrededor de todo el borde, con halo, más intenso en el
  canto inferior. Sirve para ubicar la isla cuando la barra es toda negra, y se
  regula de 0 a 100 % en Preferencias. Se dibuja un poco por fuera del recorte
  del notch: dentro no hay píxeles y no se vería.
- Esquinas superiores invertidas para fundirse con el borde de la pantalla.
- En pantallas **sin notch** se convierte en un asa centrada bajo la barra de
  menús, con la misma funcionalidad.
- Multi‑monitor: sigue la pantalla donde está el mouse (configurable).

**Avisos** (píldora pequeña colgando bajo el notch, sin tapar la barra)
- Cambio de canción: carátula + ecualizador animado.
- Conexión/desconexión del cargador.

Volumen y brillo no tienen aviso a propósito: macOS ya muestra el suyo y
duplicarlo costaba un sondeo permanente para nada.

**Música** — Apple Music y Spotify, cada uno activable por separado (apagar el
que no uses ahorra una consulta y un permiso de automatización)
- Carátula, título, artista, barra de progreso con scrubbing, anterior/play/
  siguiente y volumen del sistema.
- Clic en la carátula abre la app de origen.

**Repisa de archivos**
- Arrastra archivos al notch y quedan ahí. Arrástralos de vuelta a donde
  quieras, o usa abrir / mostrar en Finder / copiar ruta.
- Persiste entre sesiones.

**Gestos sobre el notch**
- Scroll vertical = volumen.
- Scroll horizontal = canción anterior / siguiente.
- Arrastrar archivos = van a la repisa.

**Preferencias** (engranaje de la isla o el menú de la barra)
- Tamaño abierto (el contenido se compacta solo en los altos chicos), radio de
  esquinas, ancho extra en reposo y contorno.
- Retardo de apertura, háptica, pantalla a seguir, abrir al iniciar sesión y
  ocultar el ícono de la barra de menús (con botón de salir acá mismo).
- Qué módulos quieres (reproductor, fuentes de música, repisa) y qué avisos,
  con su duración. Si solo dejas un módulo activo, la barra de pestañas
  desaparece sola.

## Instalar

```bash
./build.sh --install
```

Compila, arma `Island Effect.app`, la firma ad‑hoc, la copia a `/Applications` y
la lanza. Sin el flag solo compila en `build/`; con `--run` la ejecuta desde ahí.

Requiere macOS 14 o superior y las Command Line Tools de Xcode (`swift`).

## Permisos que pide macOS

| Permiso | Para qué | Cuándo |
|---|---|---|
| Automatización (Música / Spotify) | Leer y controlar la reproducción | La primera vez que hay un reproductor abierto |

No es obligatorio: sin él la app funciona, solo pierdes el reproductor.

> Al estar firmada ad‑hoc, macOS le da una identidad nueva en cada recompilación
> y puede volver a pedir los permisos. Es normal en apps locales sin certificado
> de desarrollador.

## Cómo está hecho

| Archivo | Rol |
|---|---|
| `NotchPanel.swift` | `NSPanel` sin bordes sobre la barra de menús, con click‑through fuera de la isla |
| `NotchController.swift` | Posición, hover, gestos, avisos, multi‑monitor, paso de clics |
| `NotchViewModel.swift` | Estado (reposo / aviso / abierta) y tamaños de cada uno |
| `NotchShape.swift` | Forma del notch en reposo y de la isla desplegada (notch + panel colgante) |
| `RootView.swift` | Fondo, contorno, píldora de aviso y panel abierto |
| `MediaManager.swift` | Now playing y control: notificaciones distribuidas + AppleScript |
| `MusicView.swift` | Reproductor, con tres densidades según el alto del panel |
| `ShelfStore.swift` / `ShelfView.swift` | Repisa de archivos |
| `SystemMonitors.swift` | Volumen (CoreAudio, bajo demanda) y batería (IOKit) |
| `Components.swift` | Piezas compartidas: carátula, slider, ecualizador, botones |
| `SettingsView.swift` | Preferencias + ítem de inicio |
| `Debug.swift` | Log opcional y ganchos de prueba (`ISLAND_*`) |

### Rendimiento

Medido en un MacBook Pro M5 Pro, la app en reposo con el puntero lejos del
notch, promediando tiempo de CPU real sobre una ventana de 45 s:

| Escenario | CPU | Memoria |
|---|---|---|
| Antes de optimizar, en reposo | 5,33 % | 125 MB |
| **En reposo** | **0,40 %** | 73 MB |
| Píldora de canción animada | 1,35 % | 69 MB |
| Isla abierta (vidrio en vivo) | 3,40 % | 73 MB |

Medir en reposo con el Mac en uso da números mucho más altos y engañosos: la
isla se abre de verdad cada vez que el puntero roza el notch, y el vidrio
renderiza mientras esté abierta. Las cifras de arriba son de ventanas
tranquilas.

Lo que se cambió:

- **Nada de `osascript` en reposo.** Music y Spotify publican una notificación
  distribuida en cada cambio de pista con los metadatos dentro; antes se
  lanzaba un proceso `osascript` cada segundo. Solo se sondea con la isla
  abierta (para que avance la barra de progreso) y como red de seguridad
  espaciada. Si el reproductor resulta no publicar notificaciones, la app lo
  detecta sola y vuelve a sondear más seguido.
- **Sin vigilancia de volumen ni de brillo.** Eran dos sondeos permanentes para
  duplicar avisos que el sistema ya da. Además el brillo automático del Mac
  hace microajustes constantes: la píldora salía sola varias veces por minuto.
- **Sondeo del puntero adaptativo**: 8 Hz lejos del borde superior, 30 Hz cerca
  del notch o con la isla abierta, en vez de 60 Hz constantes, con salida
  temprana en el camino caliente. El trabajo real va por monitores de eventos;
  el temporizador es solo la red para apps a pantalla completa.
- **El contorno se rasteriza** (`drawingGroup`): sus desenfoques se recalculaban
  en cada fotograma y con la píldora animada la CPU se iba por encima del 15 %.
  El vidrio queda fuera de esa textura porque no sobrevive a un `drawingGroup`.
- **Ecualizador por Core Animation** en vez de `TimelineView`, para no
  reevaluar la vista veinte veces por segundo.

### Limitaciones conocidas

- El *now playing* solo cubre **Música y Spotify**. macOS 15.4 cerró el
  framework privado `MediaRemote` para apps sin entitlements de Apple, así que
  no hay forma pública de leer lo que suena en un navegador.
- El HUD nativo de volumen/brillo de macOS sigue apareciendo; la isla lo
  complementa, no lo reemplaza.

### Depuración

```bash
ISLAND_DEBUG=1 ISLAND_LOG=/tmp/island.log open -n build/Island\ Effect.app
```

`ISLAND_TAB=music|shelf` fuerza la pestaña inicial, `ISLAND_SETTINGS=1` abre
Preferencias al arrancar e `ISLAND_DEMO=1` dispara una live activity de prueba.
