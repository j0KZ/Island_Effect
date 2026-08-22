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
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

/// Hosting view que deja pasar los clics fuera del área visible de la isla.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// ¿El punto (en coordenadas de la vista, origen abajo-izquierda) pertenece
    /// a la isla? Todo lo demás deja pasar el clic a la app de abajo.
    var isActive: (NSPoint) -> Bool = { _ in false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isActive(point) else { return nil }
        return super.hitTest(point)
    }
}
