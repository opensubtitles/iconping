import SwiftUI
import Charts
import IconPingCore
import AppKit

struct DashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showExportPanel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                chart
                Divider()
                statsGrid
                Divider()
                networkPath
                Divider()
                eventLog
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 560)
        .navigationTitle("IconPing")
    }

    private var header: some View {
        HStack(spacing: 16) {
            StateBadge(state: viewModel.state)
                .scaleEffect(1.6)
                .padding(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(viewModel.state.localizationKey))
                    .font(.largeTitle.bold())
                HStack(spacing: 8) {
                    Text(viewModel.engineConfig.targetHost)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(viewModel.resolvedAddress)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(viewModel.ipVersionInUse.rawValue.uppercased())
                        .foregroundStyle(.secondary)
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                .font(.callout)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(rttString)
                    .font(.system(.title, design: .rounded).monospacedDigit())
                Text(LocalizedStringKey("metric.latency"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

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
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2,2]))
                }
            }
            RuleMark(y: .value("warn", viewModel.thresholds.latencyWarnMs))
                .foregroundStyle(.orange.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,4]))
        }
        .chartYAxisLabel(LocalizedStringKey("metric.latency"))
        .frame(height: 200)
    }

    private var statsGrid: some View {
        let snap = viewModel.snapshot
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), spacing: 12) {
            StatCard(labelKey: "metric.min", value: ms(snap.rttMinMs))
            StatCard(labelKey: "metric.avg", value: ms(snap.rttAvgMs))
            StatCard(labelKey: "metric.max", value: ms(snap.rttMaxMs))
            StatCard(labelKey: "metric.jitter", value: ms(snap.jitterMs))
            StatCard(labelKey: "metric.loss",   value: String(format: "%.1f%%", snap.lossPercent))
            StatCard(labelKey: "metric.uptime", value: String(format: "%.1f%%", snap.uptimePercent))
            StatCard(labelKey: "stats.sent",     value: "\(snap.sent)")
            StatCard(labelKey: "stats.received", value: "\(snap.received)")
            StatCard(labelKey: "stats.lost",     value: "\(snap.lost)")
            StatCard(labelKey: "stats.window",   value: "\(snap.windowSize)")
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
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
        }
    }

    private var networkPath: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey("section.path"))
                .font(.headline)
            HStack(spacing: 24) {
                Label(viewModel.pathInfo?.interfaceTypes.joined(separator: ", ") ?? "—",
                      systemImage: "network")
                if let p = viewModel.pathInfo {
                    Label(p.supportsIPv4 ? "IPv4" : "—", systemImage: "4.circle")
                    Label(p.supportsIPv6 ? "IPv6" : "—", systemImage: "6.circle")
                    if p.isExpensive {
                        Label(LocalizedStringKey("path.expensive"), systemImage: "creditcard")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .font(.callout)
        }
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey("section.events"))
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.transitions) { t in
                        HStack(spacing: 10) {
                            Text(t.at, style: .time)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(t.from.localizationKey))
                                Image(systemName: "arrow.right")
                                Text(LocalizedStringKey(t.to.localizationKey))
                                    .bold()
                            }
                            if let note = t.note {
                                Text("(\(note))").foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 180)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - helpers

    private var rttString: String {
        if let ms = viewModel.snapshot.rttLastMs { return String(format: "%.0f ms", ms) }
        return "—"
    }

    private func ms(_ value: Double?) -> String {
        if let v = value { return String(format: "%.0f ms", v) }
        return "—"
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

struct StatCard: View {
    let labelKey: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(labelKey))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
