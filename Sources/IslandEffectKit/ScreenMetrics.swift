import AppKit

/// Geometría del notch (o del "handler" en pantallas sin notch).
struct ScreenMetrics {
    let screen: NSScreen
    let hasNotch: Bool
    /// Tamaño físico del notch en puntos.
    let notchSize: CGSize

    static func metrics(for screen: NSScreen) -> ScreenMetrics {
        let found = notch(frameWidth: screen.frame.width,
                          topInset: screen.safeAreaInsets.top,
                          left: screen.auxiliaryTopLeftArea,
                          right: screen.auxiliaryTopRightArea)
        return ScreenMetrics(screen: screen, hasNotch: found.hasNotch, notchSize: found.size)
    }

    /// Asa para pantallas sin notch: centrada bajo la barra de menús.
    static let handleSize = CGSize(width: 180, height: 32)

    /// Un notch de verdad deja libre una franja a cada lado de la barra de menús.
    /// El hueco del medio es el recorte; si midiera menos que esto no sería un
    /// notch sino un artefacto de la pantalla, y se usa el asa.
    static let minimumNotchWidth: CGFloat = 40

    /// Mide el notch a partir de lo que reporta la pantalla. Aparte de `NSScreen`
    /// porque una pantalla no se puede fabricar en una prueba.
    static func notch(frameWidth: CGFloat, topInset: CGFloat,
                      left: CGRect?, right: CGRect?) -> (hasNotch: Bool, size: CGSize) {
        if topInset > 0, let left, let right {
            let width = frameWidth - left.width - right.width
            if width > minimumNotchWidth {
                return (true, CGSize(width: width, height: topInset))
            }
        }
        return (false, handleSize)
    }

    /// Pantalla objetivo según preferencias (la del mouse, o la que tenga notch, o la principal).
    static func targetScreen(followMouse: Bool) -> NSScreen {
        if followMouse {
            let p = NSEvent.mouseLocation
            if let s = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) { return s }
        }
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) { return notched }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}
