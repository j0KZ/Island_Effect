import AppKit
import SwiftUI

/// Ventana flotante sin bordes que se dibuja por encima de la barra de menús.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        canHide = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    /// El panel solo roba el foco del teclado cuando la isla lo necesita
    /// (buscador del portapapeles); el resto del tiempo no molesta a la app de adelante.
    func setWantsKeyboard(_ wants: Bool) {
        becomesKeyOnlyIfNeeded = !wants
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

/// Hosting view que deja pasar los clics fuera del área visible de la isla.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Rectángulo activo en coordenadas de la vista (origen abajo-izquierda).
    var activeRect: () -> CGRect = { .zero }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard activeRect().contains(point) else { return nil }
        return super.hitTest(point)
    }
}
