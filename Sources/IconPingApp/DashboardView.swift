import SwiftUI
import Charts
import IconPingCore
import AppKit

struct DashboardView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            hero
            statsRow
            chart
            footer
        }
        .padding(20)
        .frame(width: 620, height: 440, alignment: .topLeading)
        .background(.background)
    }

    // MARK: - Hero (big status)

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            HeroBadge(state: viewModel.state)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(viewModel.state.localizationKey))
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(viewModel.engineConfig.targetHost)
                        .fontWeight(.medium)
                    Text("·").foregroundStyle(.tertiary)
                    Text(viewModel.resolvedAddress)
                    Text("·").foregroundStyle(.tertiary)
                    Text(viewModel.ipVersionInUse.rawValue.uppercased())
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    viewModel.togglePause()
                } label: {
                    Image(systemName: viewModel.paused ? "play.fill" : "pause.fill")
                        .frame(width: 12)
                }
                .help(viewModel.paused ? "menu.resume" : "menu.pause")

                Button {
                    viewModel.resetStats()
                } label: {
                    Text(LocalizedStringKey("action.reset"))
                }
            }
            .controlSize(.small)
        }
    }

    // MARK: - Big stats row (only 4: Latency, Loss, Jitter, Uptime)

    private var statsRow: some View {
        let s = viewModel.snapshot
        return HStack(spacing: 10) {
            BigStat(labelKey: "metric.latency", value: ms(s.rttLastMs),    tint: latencyTint(s.rttLastMs))
            BigStat(labelKey: "metric.loss",    value: pct(s.lossPercent), tint: lossTint(s.lossPercent))
            BigStat(labelKey: "metric.jitter",  value: ms(s.jitterMs),     tint: .secondary)
            BigStat(labelKey: "metric.uptime",  value: pct(s.uptimePercent), tint: uptimeTint(s.uptimePercent))
        }
    }

    // MARK: - Chart

    private var chart: some View {
        let data = Array(viewModel.recentSamples.suffix(viewModel.thresholds.rollingWindow))
        return Chart {
            ForEach(data) { s in
                if let m = s.rttMs {
                    LineMark(
                        x: .value("seq", Int(s.seq)),
                        y: .value("rtt", m)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor.gradient)

                    AreaMark(
                        x: .value("seq", Int(s.seq)),
                        y: .value("rtt", m)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor.opacity(0.10).gradient)
                } else {
                    RuleMark(x: .value("seq", Int(s.seq)))
                        .foregroundStyle(.red.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2,2]))
                }
            }
            RuleMark(y: .value("warn", viewModel.thresholds.latencyWarnMs))
                .foregroundStyle(.orange.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,4]))
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 6).padding(.vertical, 6)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Footer (network path + export)

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "network").foregroundStyle(.secondary)
            if let p = viewModel.pathInfo {
                Text(p.interfaceTypes.joined(separator: ", "))
                Text("·").foregroundStyle(.tertiary)
                Text(p.supportsIPv4 ? "IPv4" : "").foregroundStyle(p.supportsIPv4 ? .primary : .tertiary)
                Text("·").foregroundStyle(.tertiary)
                Text(p.supportsIPv6 ? "IPv6" : "").foregroundStyle(p.supportsIPv6 ? .primary : .tertiary)
                if p.isExpensive {
                    Text("·").foregroundStyle(.tertiary)
                    Label(LocalizedStringKey("path.expensive"), systemImage: "creditcard")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                exportCSV()
            } label: {
                Text(LocalizedStringKey("action.export"))
            }
            .controlSize(.small)
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private func ms(_ value: Double?) -> String {
        if let v = value { return String(format: "%.0f ms", v) }
        return "—"
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func latencyTint(_ ms: Double?) -> Color {
        guard let v = ms else { return .secondary }
        if v >= viewModel.thresholds.latencyWarnMs { return .orange }
        return .primary
    }

    private func lossTint(_ pct: Double) -> Color {
        if pct >= 5 { return .red }
        if pct > 0  { return .orange }
        return .primary
    }

    private func uptimeTint(_ pct: Double) -> Color {
        if pct >= 99 { return .green }
        if pct >= 95 { return .orange }
        return .red
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "iconping-log.csv"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            var s = "timestamp,seq,rtt_ms,status\n"
            for sample in viewModel.recentSamples {
                let ts = ISO8601DateFormatter().string(from: sample.sentAt)
                let rtt = sample.rttMs.map { String(format: "%.3f", $0) } ?? ""
                s += "\(ts),\(sample.seq),\(rtt),\(sample.status.rawValue)\n"
            }
            try? s.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Subviews

struct HeroBadge: View {
    let state: ConnectivityState

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 64, height: 64)
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(tint)
        }
        .accessibilityLabel(Text(LocalizedStringKey(state.localizationKey)))
    }

    private var symbol: String {
        switch state {
        case .up:      return "checkmark.circle.fill"
        case .slow:    return "tortoise.fill"
        case .down:    return "wifi.exclamationmark"
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

struct BigStat: View {
    let labelKey: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(LocalizedStringKey(labelKey))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
