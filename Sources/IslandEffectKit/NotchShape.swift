import SwiftUI

/// Forma del notch en reposo: esquinas superiores invertidas (se funden con el
/// borde de la pantalla) y esquinas inferiores redondeadas.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    init(topRadius: CGFloat = 8, bottomRadius: CGFloat = 14) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let tr = min(topRadius, rect.width / 4)
        let br = min(bottomRadius, rect.width / 4, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Isla desplegada: el notch se queda en la fila de la barra de menús y el
/// panel cuelga por debajo, ensanchándose con un filete cóncavo.
///
/// Así los íconos de la barra de menús siguen visibles y se pueden pulsar,
/// que es como se comporta una isla de verdad.
struct IslandShape: Shape {
    /// Ancho del notch físico (o del asa en pantallas sin notch).
    var notchWidth: CGFloat
    /// Alto de la fila de la barra de menús.
    var notchHeight: CGFloat
    /// Alto del panel que cuelga (0 = isla cerrada).
    var boardHeight: CGFloat
    var topRadius: CGFloat = 8
    var notchBottomRadius: CGFloat = 10
    var boardRadius: CGFloat = 22
    var fillet: CGFloat = 14

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(boardHeight, notchWidth) }
        set { boardHeight = newValue.first; notchWidth = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let boardW = rect.width
        let nw = min(notchWidth, boardW)
        let nh = notchHeight
        let bh = max(0, boardHeight)

        // Isla cerrada: es solo el notch.
        guard bh > 1 else {
            let notchRect = CGRect(x: rect.midX - nw / 2, y: rect.minY, width: nw, height: max(nh, rect.height))
            return NotchShape(topRadius: topRadius, bottomRadius: notchBottomRadius).path(in: notchRect)
        }

        let spread = max(0, (boardW - nw) / 2)
        // Cuánto "board" hay: modula el paso de esquina convexa a filete cóncavo.
        let t = min(1, spread / 40)
        let tr = min(topRadius, nw / 4)
        let f = min(fillet, spread) * t
        let rc = notchBottomRadius * (1 - t)
        let br = min(boardRadius, boardW / 2, bh / 2)

        let nx0 = rect.midX - nw / 2
        let nx1 = rect.midX + nw / 2
        let yNotch = rect.minY + nh
        let yBottom = rect.minY + nh + bh
        let dx = rc - f
        let dy = max(rc, f)

        var p = Path()
        p.move(to: CGPoint(x: nx0, y: rect.minY))
        // Esquina superior izquierda invertida (contra el borde de la pantalla).
        p.addQuadCurve(to: CGPoint(x: nx0 + tr, y: rect.minY + tr),
                       control: CGPoint(x: nx0 + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: nx0 + tr, y: yNotch - dy))
        // Encuentro con el panel: convexo si está cerrada, cóncavo si está abierta.
        p.addQuadCurve(to: CGPoint(x: nx0 + tr + dx, y: yNotch),
                       control: CGPoint(x: nx0 + tr, y: yNotch))
        p.addLine(to: CGPoint(x: rect.minX + br, y: yNotch))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: yNotch + br),
                       control: CGPoint(x: rect.minX, y: yNotch))
        p.addLine(to: CGPoint(x: rect.minX, y: yBottom - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + br, y: yBottom),
                       control: CGPoint(x: rect.minX, y: yBottom))
        p.addLine(to: CGPoint(x: rect.maxX - br, y: yBottom))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: yBottom - br),
                       control: CGPoint(x: rect.maxX, y: yBottom))
        p.addLine(to: CGPoint(x: rect.maxX, y: yNotch + br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: yNotch),
                       control: CGPoint(x: rect.maxX, y: yNotch))
        p.addLine(to: CGPoint(x: nx1 - tr - dx, y: yNotch))
        p.addQuadCurve(to: CGPoint(x: nx1 - tr, y: yNotch - dy),
                       control: CGPoint(x: nx1 - tr, y: yNotch))
        p.addLine(to: CGPoint(x: nx1 - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: nx1, y: rect.minY),
                       control: CGPoint(x: nx1 - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
