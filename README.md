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
- Clic en el notch = fijar abierta / cerrar. El botón de chincheta la mantiene
  abierta mientras hagas cosas dentro.
- Al abrirse, el panel **cuelga por debajo de la barra de menús**: en esa fila
  solo queda el notch, así que los íconos de tus otras apps siguen visibles.
- La ventana solo acepta clics mientras el puntero está sobre la isla
  (`ignoresMouseEvents` conmutado a 60 Hz): todo lo demás llega a la barra de
  menús como si la isla no existiera.
- Fondo translúcido de verdad (`NSVisualEffectView`): desenfoca lo que hay
  detrás en vez de ser un rectángulo negro.
- Contorno tipo *Liquid Glass*: borde especular, más intenso en el canto
  inferior, con halo. Sirve para ubicar la isla cuando la barra es toda negra.
  Regulable de 0 a 100 % en Preferencias.
- Esquinas superiores invertidas para fundirse con el borde de la pantalla.
- En pantallas **sin notch** se convierte en un asa centrada bajo la barra de
  menús, con la misma funcionalidad.
- Multi‑monitor: sigue la pantalla donde está el mouse (configurable).

**Live activities** (píldora pequeña colgando bajo el notch, sin tapar la barra)
- Cambio de canción: carátula + ecualizador animado.
- Volumen y brillo al tocar las teclas.
- Conexión/desconexión del cargador.

**Música** — Apple Music y Spotify
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

**Preferencias** (ícono de engranaje en la isla o el menú de la barra)
- Tamaño abierto (el contenido se compacta solo en los altos chicos), radio de
  esquinas, ancho extra en reposo, contorno, halo y fondo translúcido.
- Retardos de apertura/cierre, háptica, pantalla a seguir, abrir al iniciar
  sesión y ocultar el ícono de la barra de menús (con botón de salir acá mismo).
- Qué pestañas y qué live activities quieres, y su duración. Las activities
  ocupan un momento el espacio a los lados del notch: si te estorban, cada una
  se apaga por separado.

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
| `NotchController.swift` | Posición, hover, gestos, live activities, multi‑monitor |
| `NotchViewModel.swift` | Estado (cerrada / abierta / activity), tamaños, temporizador |
| `NotchShape.swift` | Forma del notch en reposo y de la isla desplegada (notch + panel colgante) |
| `RootView.swift` | Isla cerrada (activities) y abierta (pestañas) |
| `MediaManager.swift` | Now playing y control vía AppleScript, con sondeo adaptativo |
| `ShelfStore.swift` / `ShelfView.swift` | Repisa de archivos |
| `SystemMonitors.swift` | Volumen (CoreAudio), brillo (DisplayServices), batería (IOKit), RAM |
| `SettingsView.swift` | Preferencias + ítem de inicio |

### Rendimiento

Medido en un MacBook Pro M5 Pro, la app en reposo con el puntero lejos del
notch, promediando tiempo de CPU real sobre una ventana de 45 s:

| Versión | CPU | Memoria |
|---|---|---|
| Antes de optimizar | 5,33 % | 125 MB |
| Después | **0,69 %** | **57 MB** |
| Solo la isla, sin live activities | 0,20 % | 53 MB |

Lo que se cambió:

- **Nada de `osascript` en reposo.** Music y Spotify publican una notificación
  distribuida en cada cambio de pista con los metadatos dentro; antes se
  lanzaba un proceso `osascript` cada segundo. Solo se sondea con la isla
  abierta (para que avance la barra de progreso) y como red de seguridad
  espaciada. Si el reproductor resulta no publicar notificaciones, la app lo
  detecta sola y vuelve a sondear más seguido.
- **Volumen por evento.** El listener estaba puesto en la propiedad de volumen
  "virtual", que no notifica; ahora escucha la escala por canal y en cuanto
  llega el primer aviso apaga el sondeo.
- **Brillo por evento** (`com.apple.backlight.changed`), con sondeo de respaldo
  si esa notificación no llega.
- **Sondeo del puntero adaptativo**: 8 Hz lejos del borde superior, 30 Hz cerca
  del notch o con la isla abierta, en vez de 60 Hz constantes. El trabajo real
  va por monitores de eventos; el temporizador es solo la red para apps a
  pantalla completa.

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
