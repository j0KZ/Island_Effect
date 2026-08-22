import SwiftUI
import AppKit

struct WidgetsView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            ClockWidget()
            ControlsWidget()
            StatusWidget()
            TimerWidget(vm: vm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClockWidget: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        WidgetCard(title: "Hora", symbol: "clock") {
            VStack(alignment: .leading, spacing: 2) {
                Text(now, format: .dateTime.hour(prefs.use24hClock ? .twoDigits(amPM: .omitted) : .defaultDigits(amPM: .abbreviated)).minute(.twoDigits))
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .onReceive(ticker) { now = $0 }
    }
}

struct ControlsWidget: View {
    @ObservedObject private var volume = VolumeMonitor.shared
    @ObservedObject private var brightness = BrightnessMonitor.shared
    @State private var vol: Double = 0
    @State private var bright: Double = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        WidgetCard(title: "Controles", symbol: "slider.horizontal.3") {
            VStack(spacing: 10) {
                row(symbol: volume.muted || vol < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    value: Binding(get: { vol }, set: { vol = $0; volume.setVolume(Float($0)) }))
                if brightness.available {
                    row(symbol: "sun.max.fill",
                        value: Binding(get: { bright }, set: { bright = $0; brightness.setBrightness(Float($0)) }))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .onAppear { sync() }
        .onReceive(ticker) { _ in sync() }
    }

    private func sync() {
        vol = Double(volume.readVolume())
        if brightness.available { bright = Double(brightness.read()) }
    }

    private func row(symbol: String, value: Binding<Double>) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 14)
            IslandSlider(value: value, height: 6)
                .frame(height: 14)
        }
    }
}

struct StatusWidget: View {
    @ObservedObject private var battery = BatteryMonitor.shared
    @State private var memory: (fraction: Double, usedGB: Double, totalGB: Double) = (0, 0, 0)
    @State private var disk: (free: Double, total: Double) = (0, 0)
    private let ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        WidgetCard(title: "Estado", symbol: "gauge.with.dots.needle.bottom.50percent") {
            HStack(spacing: 12) {
                RingGauge(progress: Double(battery.state.percent) / 100,
                          tint: batteryColor, lineWidth: 5) {
                    VStack(spacing: 0) {
                        if battery.state.charging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.green)
                        }
                        Text("\(battery.state.percent)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 5) {
                    statRow(label: "RAM", value: "\(Int(memory.fraction * 100))%", progress: memory.fraction, tint: .purple)
                    statRow(label: "Disco",
                            value: String(format: "%.0f GB", disk.free),
                            progress: disk.total > 0 ? 1 - disk.free / disk.total : 0,
                            tint: .teal)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .onAppear { refresh() }
        .onReceive(ticker) { _ in refresh() }
    }

    private var batteryColor: Color {
        if battery.state.charging { return .green }
        if battery.state.percent <= 15 { return .red }
        if battery.state.percent <= 30 { return .orange }
        return .white
    }

    private func refresh() {
        memory = SystemStats.memoryUsage()
        disk = SystemStats.diskFreeGB()
    }

    private func statRow(label: String, value: String, progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(value).font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(tint.opacity(0.85))
                        .frame(width: max(2, geo.size.width * min(1, max(0, progress))))
                }
            }
            .frame(height: 4)
        }
    }
}

struct TimerWidget: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        WidgetCard(title: "Temporizador", symbol: "timer") {
            VStack(spacing: 8) {
                Text(TimeFormat.clock(vm.timerRemaining))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(vm.timerRunning ? .white : .white.opacity(0.7))

                if vm.timerRemaining == 0 {
                    HStack(spacing: 5) {
                        ForEach([5, 15, 25], id: \.self) { minutes in
                            Button("\(minutes)m") { vm.startTimer(seconds: minutes * 60) }
                                .buttonStyle(PillButtonStyle())
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        CircleButton(symbol: vm.timerRunning ? "pause.fill" : "play.fill",
                                     size: 26, iconSize: 10) { vm.toggleTimer() }
                        CircleButton(symbol: "stop.fill", size: 26, iconSize: 10) { vm.stopTimer() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
