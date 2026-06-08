import SwiftUI
import Charts
import IconPingCore
import AppKit

struct DashboardView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chart
                .frame(height: 130)
            statsGrid
            networkPath
            eventLog
        }
        .padding(14)
        .frame(width: 720, height: 540, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            StateBadge(state: viewModel.state)
                .scaleEffect(1.15)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(viewModel.state.localizationKey))
                    .font(.title3.bold())
                HStack(spacing: 6) {
                    Text(viewModel.engineConfig.targetHost)
                    Text("·").foregroundStyle(.tertiary)
                    Text(viewModel.resolvedAddress)
                    Text("·").foregroundStyle(.tertiary)
                    Text(viewModel.ipVersionInUse.rawValue.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    viewModel.togglePause()
                } label: {
                    Image(systemName: viewModel.paused ? "play.fill" : "pause.fill")
                }
                .help(viewModel.paused ? "menu.resume" : "menu.pause")

                Button {
                    viewModel.resetStats()
                } label: {
                    Text(LocalizedStringKey("action.reset"))
                }

                Button {
                    exportCSV()
                } label: {
                    Text(LocalizedStringKey("action.export"))
                }
            }
            .controlSize(.small)
        }
    }

    // MARK: - Chart

    private var chart: some View {
        let data = Array(viewModel.recentSamples.suffix(viewModel.thresholds.rollingWindow))
        return Chart {
            ForEach(data) { s in
                if let ms = s.rttMs {
                    LineMark(
                        x: .value("seq", Int(s.seq)),
                        y: .value("rtt", ms)
                    )
                    .foregroundStyle(Color.accentColor)
                } else {
                    RuleMark(x: .value("seq", Int(s.seq)))
                        .foregroundStyle(.red.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2,2]))
                }
            }
            RuleMark(y: .value("warn", viewModel.thresholds.latencyWarnMs))
                .foregroundStyle(.orange.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,4]))
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel() {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))").font(.caption2)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Stats grid (4 cols × 3 rows, compact)

    private var statsGrid: some View {
        let s = viewModel.snapshot
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 6) {
            StatCell(labelKey: "metric.min",    value: ms(s.rttMinMs))
            StatCell(labelKey: "metric.avg",    value: ms(s.rttAvgMs))
            StatCell(labelKey: "metric.max",    value: ms(s.rttMaxMs))
            StatCell(labelKey: "metric.latency",value: ms(s.rttLastMs))

            StatCell(labelKey: "metric.jitter", value: ms(s.jitterMs))
            StatCell(labelKey: "metric.loss",   value: String(format: "%.1f%%", s.lossPercent))
            StatCell(labelKey: "metric.uptime", value: String(format: "%.1f%%", s.uptimePercent))
            StatCell(labelKey: "stats.window",  value: "\(s.windowSize)")

            StatCell(labelKey: "stats.sent",     value: "\(s.sent)")
            StatCell(labelKey: "stats.received", value: "\(s.received)")
            StatCell(labelKey: "stats.lost",     value: "\(s.lost)")
            StatCell(labelKey: "stats.since",    value: relativeSince(s.since))
        }
    }

    // MARK: - Network path

    private var networkPath: some View {
        HStack(spacing: 10) {
            Image(systemName: "network").foregroundStyle(.secondary)
            Text(viewModel.pathInfo?.interfaceTypes.joined(separator: ", ") ?? "—")
            if let p = viewModel.pathInfo {
                Text("·").foregroundStyle(.tertiary)
                Text(p.supportsIPv4 ? "IPv4" : "—").foregroundStyle(p.supportsIPv4 ? .primary : .tertiary)
                Text("·").foregroundStyle(.tertiary)
                Text(p.supportsIPv6 ? "IPv6" : "—").foregroundStyle(p.supportsIPv6 ? .primary : .tertiary)
                if p.isExpensive {
                    Text("·").foregroundStyle(.tertiary)
                    Label(LocalizedStringKey("path.expensive"), systemImage: "creditcard")
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Event log

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LocalizedStringKey("section.events"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.transitions.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if viewModel.transitions.isEmpty {
                        Text(LocalizedStringKey("events.none"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(viewModel.transitions) { t in
                            EventRow(transition: t)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Helpers

    private func ms(_ value: Double?) -> String {
        if let v = value { return String(format: "%.0f ms", v) }
        return "—"
    }

    private func relativeSince(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return String(format: "%dh%02dm", s / 3600, (s % 3600) / 60)
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

struct StatCell: View {
    let labelKey: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(labelKey))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct EventRow: View {
    let transition: StateTransition
    var body: some View {
        HStack(spacing: 8) {
            Text(transition.at, format: .dateTime.hour().minute().second())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(transition.from.localizationKey))
                .font(.caption)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(LocalizedStringKey(transition.to.localizationKey))
                .font(.caption.bold())
            if let note = transition.note {
                Text("(\(note))").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}
