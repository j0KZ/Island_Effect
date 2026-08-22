import SwiftUI
import AppKit

enum TimeFormat {
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    static func clock(_ seconds: Double) -> String { clock(Int(seconds.rounded())) }
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
struct EqualizerBars: View {
    var active: Bool
    var tint: Color = .white
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        let speed = [3.1, 4.3, 2.6, 3.7][i]
                        let offset = [0.0, 1.2, 2.4, 0.7][i]
                        let raw = active ? (sin(t * speed + offset) + 1) / 2 : 0.15
                        let h = max(0.18, raw) * geo.size.height
                        Capsule()
                            .fill(tint)
                            .frame(height: h)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

/// Barra pequeña de progreso (volumen/brillo en modo compacto).
struct MiniBar: View {
    var value: Double
    var tint: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(tint)
                    .frame(width: max(3, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(width: 58, height: 5)
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
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
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
                        let f = min(1, max(0, g.location.x / geo.size.width))
                        value = range.lowerBound + f * span
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

/// Anillo de progreso para widgets.
struct RingGauge<Label: View>: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 6
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            label()
        }
    }
}

/// Tarjeta base de los widgets.
struct WidgetCard<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(.white.opacity(0.45))
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
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
