import SwiftUI
import AppKit

/// Material translúcido de macOS detrás de la isla (desenfoca lo que hay debajo).
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

enum TimeFormat {
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    /// Un valor no finito (una emisora sin duración, por ejemplo) no se puede
    /// convertir a entero: intentarlo aborta el proceso. Se muestra 0:00.
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return clock(0) }
        return clock(Int(seconds.rounded()))
    }
}

/// Carátula del tema actual, con placeholder cuando no hay imagen.
struct ArtworkView: View {
    @ObservedObject private var media = MediaManager.shared
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }
}

/// Barras animadas tipo ecualizador.
///
/// La animación es implícita (Core Animation): se declara una vez y la mueve
/// el servidor de render. Con `TimelineView` había que reevaluar la vista 20
/// veces por segundo, y con el vidrio y el halo detrás eso se notaba en la CPU.
struct EqualizerBars: View {
    var active: Bool
    var tint: Color = .white
    @State private var animating = false

    private let speeds: [Double] = [0.52, 0.38, 0.61, 0.45]
    private let lows: [CGFloat] = [0.30, 0.22, 0.38, 0.26]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(height: geo.size.height * ((animating && active) ? 1 : lows[i]))
                        .animation(active
                                   ? .easeInOut(duration: speeds[i]).repeatForever(autoreverses: true)
                                   : .default,
                                   value: animating)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}

/// Slider plano estilo isla (para volumen, brillo y scrubbing).
struct IslandSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var height: CGFloat = 6
    var tint: Color = .white
    var onEditingChanged: ((Bool) -> Void)? = nil
    @State private var dragging = false
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let fraction = SliderMath.fraction(of: value, in: range)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(tint.opacity(0.9))
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
            .frame(height: dragging || hovering ? height + 2 : height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging { dragging = true; onEditingChanged?(true) }
                        value = SliderMath.value(atX: g.location.x, width: geo.size.width, in: range)
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged?(false)
                    }
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: dragging)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

/// Botón circular translúcido.
struct CircleButton: View {
    var symbol: String
    var size: CGFloat = 30
    var iconSize: CGFloat = 12
    var filled: Bool = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(filled ? 0.92 : (hovering ? 0.16 : 0.10)))
                Image(systemName: symbol)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(filled ? Color.black : Color.white)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}


/// Conversión entre el valor de un slider y su posición en pantalla. Aparte de
/// la vista porque es lo que se nota torcido al arrastrar la barra de la canción.
enum SliderMath {
    /// Qué fracción del recorrido ocupa un valor. Un rango degenerado da 0 en
    /// vez de dividir por cero.
    static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    /// El valor que corresponde a un punto del recorrido, acotado a los extremos.
    static func value(atX x: CGFloat, width: CGFloat, in range: ClosedRange<Double>) -> Double {
        guard width > 0 else { return range.lowerBound }
        let f = min(1, max(0, Double(x / width)))
        return range.lowerBound + f * (range.upperBound - range.lowerBound)
    }
}
