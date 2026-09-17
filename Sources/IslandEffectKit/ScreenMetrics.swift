import AppKit

/// Geometría del notch (o del "handler" en pantallas sin notch).
struct ScreenMetrics {
    let screen: NSScreen
    let hasNotch: Bool
    /// Tamaño físico del notch en puntos.
    let notchSize: CGSize

    static func metrics(for screen: NSScreen) -> ScreenMetrics {
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            if width > 40 {
                return ScreenMetrics(screen: screen, hasNotch: true,
                                     notchSize: CGSize(width: width, height: topInset))
            }
        }
        // Pantalla sin notch: usamos un "asa" centrada bajo la barra de menús.
        return ScreenMetrics(screen: screen, hasNotch: false,
                             notchSize: CGSize(width: 180, height: 32))
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
