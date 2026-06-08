import SwiftUI
import IconPingCore

struct PopoverView: View {
    @ObservedObject var viewModel: AppViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                StateBadge(state: viewModel.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(viewModel.state.localizationKey))
                        .font(.headline)
                    Text(viewModel.engineConfig.targetHost + "  ·  " + viewModel.resolvedAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            Divider()

            HStack(spacing: 16) {
                MetricView(labelKey: "metric.latency", value: rttString)
                MetricView(labelKey: "metric.loss",    value: String(format: "%.0f%%", viewModel.snapshot.lossPercent))
                MetricView(labelKey: "metric.jitter",  value: jitterString)
            }

            MiniSparkline(samples: viewModel.recentSamples)
                .frame(height: 40)

            HStack {
                Button {
                    onClose()
                    WindowManager.shared.openDashboard(viewModel: viewModel)
                } label: {
                    Text(LocalizedStringKey("menu.dashboard"))
                }
                Spacer()
                Button {
                    onClose()
                    WindowManager.shared.openSettings(viewModel: viewModel)
                } label: {
                    Text(LocalizedStringKey("menu.settings"))
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var rttString: String {
        if let ms = viewModel.snapshot.rttLastMs { return String(format: "%.0f ms", ms) }
        return "—"
    }

    private var jitterString: String {
        if let ms = viewModel.snapshot.jitterMs { return String(format: "%.0f ms", ms) }
        return "—"
    }
}

struct StateBadge: View {
    let state: ConnectivityState

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .accessibilityLabel(Text(LocalizedStringKey(state.localizationKey)))
    }

    private var symbol: String {
        switch state {
        case .up:      return "circle.fill"
        case .slow:    return "circle.bottomhalf.filled"
        case .down:    return "xmark.circle.fill"
        case .unknown: return "circle.dotted"
        }
    }

    private var tint: Color {
        switch state {
        case .up:      return .green
        case .slow:    return .orange
        case .down:    return .red
        case .unknown: return .secondary
        }
    }
}

struct MetricView: View {
    let labelKey: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(labelKey))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MiniSparkline: View {
    let samples: [Sample]

    var body: some View {
        GeometryReader { geo in
            let pts = samples.suffix(60)
            let rtts = pts.map { $0.rttMs ?? 0 }
            let maxV = max(rtts.max() ?? 1, 1)
            let stepX = pts.isEmpty ? geo.size.width : geo.size.width / CGFloat(max(pts.count - 1, 1))

            Path { p in
                for (i, s) in pts.enumerated() {
                    let x = CGFloat(i) * stepX
                    let v = s.rttMs ?? 0
                    let y = geo.size.height - (CGFloat(v / maxV) * geo.size.height)
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.accentColor, lineWidth: 1.5)

            // loss ticks at the baseline
            ForEach(Array(pts.enumerated()), id: \.offset) { (i, s) in
                if !s.isSuccess {
                    let x = CGFloat(i) * stepX
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: 6)
                        .position(x: x, y: geo.size.height - 3)
                }
            }
        }
    }
}
