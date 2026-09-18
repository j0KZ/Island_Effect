# Island Effect

*[English](README.md) · [Español](README.es.md)*

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
  dominante de la carátula; en macOS 14–15 cae a `NSVisualEffectView`.
- Además, el panel toma un **lavado de color de la propia portada**: la carátula
  reducida a 16×16 y ampliada de vuelta, que la interpolación convierte en un
  degradado con los colores del disco. Es el truco del fondo de Música de Apple
  y cuesta lo mismo que dibujar una imagen de 256 píxeles.
- Contorno especular alrededor de todo el borde, con halo, más intenso en el
  canto inferior. Sirve para ubicar la isla cuando la barra es toda negra, y se
  regula de 0 a 100 % en Preferencias. Se dibuja un poco por fuera del recorte
  del notch: dentro no hay píxeles y no se vería.
- Esquinas superiores invertidas para fundirse con el borde de la pantalla.
- En pantallas **sin notch** se convierte en un asa centrada bajo la barra de
  menús, con la misma funcionalidad.
- Multi‑monitor: sigue la pantalla donde está el mouse (configurable).

**Avisos** (píldora pequeña colgando bajo el notch, sin tapar la barra)
- Cambio de canción: carátula, ecualizador, tiempo transcurrido y una línea de
  progreso en el canto inferior. Espera a que llegue la portada antes de
  aparecer, así no sale nunca sin color.
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

**Bandeja de capturas**
- Cada captura de pantalla cae sola en la repisa, con su miniatura y una cuenta
  atrás encima. La arrastras a donde iba y se va; si no la usas, se borra sola a
  los cinco minutos (configurable entre 1 y 30).
- macOS ya muestra su miniatura abajo a la derecha, pero dura cinco segundos,
  solo enseña la última y no deja rastro. Esta espera, y acumula.
- Si quieres quedarte con una, arrástrala de vuelta al notch: deja de tener
  cuenta atrás y pasa a la repisa de siempre.
- Encuentra las capturas donde las tengas configuradas (`defaults write
  com.apple.screencapture location`), no solo en el Escritorio. Incluye las
  grabaciones de pantalla de ⇧⌘5.

**Estadísticas**
- CPU, memoria y GPU, con su barra.
- **Watts que estás gastando ahora mismo** — el número que macOS no muestra en
  ninguna parte. Abre algo pesado y se ve saltar. Solo se puede saber con
  batería: enchufado, el amperaje es el de la carga, y separar consumo de carga
  sí necesita `powermetrics` con root. Antes que un número que significa otra
  cosa, no se muestra ninguno.
- Cuánto queda **hasta agotarse y hasta el 20 %**, recalculado según el consumo
  de ahora.
- Ciclos de la batería, que si no hay que ir a buscar a Configuración → General
  → Información.
- Solo mide mientras estás mirando la pestaña. Cerrada, no corre nada.

**Cómo se usa**
- Pasa el mouse por el notch para abrirla.
- Clic: se queda abierta; otro clic la cierra.
- Arrastra archivos al notch y van a la repisa.

No hay gestos de scroll para volumen ni para cambiar de canción: eso ya está en
las teclas del Mac, y sostenerlo obligaba a un monitor global de scroll que
despertaba el proceso con cada scroll del sistema.

**Preferencias** (engranaje de la isla o el menú de la barra)
- Tamaño abierto (el contenido se compacta solo en los altos chicos), radio de
  esquinas, ancho extra en reposo y contorno.
- Retardo de apertura, háptica, pantalla a seguir, abrir al iniciar sesión y
  ocultar el ícono de la barra de menús (con botón de salir acá mismo).
- Qué módulos quieres (reproductor, fuentes de música, repisa) y qué avisos,
  con su duración. Si solo dejas un módulo activo, la barra de pestañas
  desaparece sola, y el último encendido no se puede apagar.

Son cuatro pestañas: General, Apariencia, Módulos y Acerca de.

## Instalar

```bash
./build.sh --install
```

Compila, arma `Island Effect.app`, la firma ad‑hoc, la copia a `/Applications` y
la lanza. Sin el flag solo compila en `build/`; con `--run` la ejecuta desde ahí.

Requiere macOS 14 o superior y las Command Line Tools de Xcode (`swift`).

## Permisos

Uno solo:

| Permiso | Para qué | Cuándo |
|---|---|---|
| Automatización (Música / Spotify) | Leer y controlar la reproducción | La primera vez que hay un reproductor abierto |

No es obligatorio: sin él la app funciona, solo pierdes el reproductor, y la
pestaña de Música te ofrece el atajo a Ajustes para concederlo. Si solo usas
uno de los dos reproductores, apaga el otro en Módulos y macOS no te preguntará
por él.

**No pide** accesibilidad, grabación de pantalla, cámara, micrófono, ubicación,
contactos ni calendario, y no usa ninguna API que las requiera. Tampoco va en
sandbox, así que la repisa lee los archivos que le sueltas sin más trámite
(macOS sí puede preguntar por Escritorio, Documentos o Descargas la primera vez
que se toca un archivo de esas carpetas, como a cualquier app).

> Al estar firmada ad‑hoc, macOS le da una identidad nueva en cada recompilación
> y puede volver a pedir los permisos. Es normal en apps locales sin certificado
> de desarrollador.

## Idiomas

Inglés y español. La app sigue el idioma del sistema y cae al inglés si no es
ninguno de los dos. Las cadenas viven en `Resources/en.lproj` y
`Resources/es.lproj`; las claves son el propio texto en inglés, así que añadir
un idioma es copiar una carpeta `.lproj` y traducir.

## Cómo está hecho

| Archivo | Rol |
|---|---|
| `NotchPanel.swift` | `NSPanel` sin bordes sobre la barra de menús, con click‑through fuera de la isla |
| `NotchController.swift` | Posición, hover, avisos, multi‑monitor, paso de clics |
| `NotchViewModel.swift` | Estado (reposo / aviso / abierta) y tamaños de cada uno |
| `NotchShape.swift` | Forma del notch en reposo y de la isla desplegada (notch + panel colgante) |
| `RootView.swift` | Fondo, contorno, píldora de aviso y panel abierto |
| `MediaManager.swift` | Now playing y control: notificaciones distribuidas + AppleScript |
| `MusicView.swift` | Reproductor, con tres densidades según el alto del panel |
| `ShelfStore.swift` / `ShelfView.swift` | Repisa de archivos y bandeja de capturas |
| `ScreenshotWatcher.swift` | Vigila la carpeta de capturas (`DispatchSource`) |
| `SystemMonitors.swift` | Volumen (CoreAudio, bajo demanda) y batería (IOKit) |
| `SystemStats.swift` / `StatsView.swift` | CPU y memoria (Mach), GPU y consumo (IOKit) |
| `Components.swift` | Piezas compartidas: carátula, slider, ecualizador, botones |
| `SettingsView.swift` | Preferencias + ítem de inicio |
| `Debug.swift` | Log opcional y ganchos de prueba (`ISLAND_*`) |

### Rendimiento

Medido en un MacBook Pro M5 Pro, promediando tiempo de CPU real (delta de
`cputime` sobre tiempo de reloj; `ps %cpu` no sirve, promedia desde el arranque
del proceso e incluye el pico de lanzamiento).

| Escenario | CPU | Memoria |
|---|---|---|
| **Reposo**, sin ningún aviso | **0,40 %** | 72 MB |
| Reposo con un cambio de canción en la ventana | 0,93 % | 72 MB |
| Píldora de canción animada | 1,35 – 3,15 % | 76 MB |
| Isla abierta, pantalla quieta detrás | 1,63 % | 73 MB |
| Isla abierta, contenido cambiando detrás | 5,04 % | 71 MB |
| *(referencia: antes de optimizar, en reposo)* | *5,33 %* | *125 MB* |

Arranque en frío: **~130 ms** desde el lanzamiento hasta la isla montada y
escuchando (tres medidas: 128, 129, 130 ms). Binario 1,3 MB, bundle 1,6 MB,
10 hilos.

Los dos escenarios de isla abierta son el mismo código: el material translúcido
vuelve a muestrear lo que tiene detrás cada vez que eso cambia, así que sobre un
escritorio quieto cuesta un tercio que sobre una terminal escupiendo texto. Es
inherente a cualquier cosa translúcida, incluido el propio macOS.

Medir el reposo con el Mac en uso da números engañosos: la isla se abre de
verdad cada vez que el puntero roza el notch. Las cifras de arriba se tomaron
verificando en el log que hubo cero aperturas durante la ventana.

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
- **Sin monitor global de scroll.** Los gestos de scroll sobre el notch exigían
  escuchar todos los eventos de scroll del sistema; se quitaron por inútiles
  (el teclado ya hace eso) y con ellos ese despertar constante.
- **Batería por notificación de IOKit** en vez de sondeo cada 5 s: el aviso de
  carga ya no llega cinco segundos tarde y desaparece otro temporizador.
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
- Probada solo en macOS 26 con Apple Silicon. El mínimo declarado es macOS 14 y
  el compilador garantiza que no se usa nada más nuevo sin guarda de versión,
  pero nadie la ha corrido en Sonoma, Sequoia ni en un Intel.
- Una portada en blanco y negro tiñe el panel de gris, porque así es la
  portada. Es correcto, aunque sorprenda la primera vez.

### Depuración

```bash
ISLAND_DEBUG=1 ISLAND_LOG=/tmp/island.log open -n build/Island\ Effect.app
```

`ISLAND_TAB=music|shelf` fuerza la pestaña inicial, `ISLAND_SETTINGS=1` abre
Preferencias al arrancar, `ISLAND_DEMO=1` dispara un aviso de prueba e
`ISLAND_OPEN=1` abre la isla fijada.

## Licencia y autoría

Hecho por **j0KZ** — [github.com/j0KZ](https://github.com/j0KZ).
Publicado bajo licencia MIT (ver [LICENSE](LICENSE)): úsalo, modifícalo y
distribúyelo, conservando el aviso de copyright.

El crédito aparece también dentro de la app, en Preferencias › Acerca de, y en
`NSHumanReadableCopyright` del bundle (lo que Finder muestra en Obtener
información).
