import SwiftUI

/// Wrist glance of heald machine health. Shares API key/URL via App Group when
/// the iPhone app has been configured; otherwise shows a short setup hint.
struct WatchRootView: View {
    @State private var machines: [Machine] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if loading && machines.isEmpty {
                    ProgressView()
                } else if let error, machines.isEmpty {
                    VStack(spacing: 8) {
                        Text(error)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        Button("Aktualisieren") { Task { await load() } }
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            HStack {
                                statusChip(machines.filter { $0.status == .healthy }.count, "OK", .green)
                                statusChip(machines.filter { $0.status == .warning }.count, "Warn", .yellow)
                                statusChip(machines.filter { $0.status == .critical }.count, "Crit", .red)
                            }
                        }
                        ForEach(machines) { m in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Circle()
                                        .fill(color(m.status))
                                        .frame(width: 8, height: 8)
                                    Text(m.hostname)
                                        .font(.headline)
                                        .lineLimit(1)
                                }
                                Text("CPU \(m.cpu.overallPercent)%  RAM \(String(format: "%.1f", m.ram.usedGB)) GB")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Heald")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func statusChip(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack {
            Text("\(n)").font(.title3.bold().monospacedDigit())
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(color)
    }

    private func color(_ s: StatusLevel) -> Color {
        switch s {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .offline: return .gray
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let rows = try await HealdAPI.shared.fetchMachines()
            await MainActor.run {
                machines = rows.map(\.asMachine).sorted {
                    statusRank($0.status) < statusRank($1.status)
                }
                error = nil
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func statusRank(_ s: StatusLevel) -> Int {
        switch s {
        case .critical: return 0
        case .warning: return 1
        case .offline: return 2
        case .healthy: return 3
        }
    }
}
