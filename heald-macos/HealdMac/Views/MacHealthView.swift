import SwiftUI

struct MacHealthView: View {
    @Environment(AppState.self) private var appState

    private var issues: [HealthIssue] {
        var result: [HealthIssue] = []
        for machine in appState.machines {
            if machine.cpu.overall > 0.9 {
                result.append(HealthIssue(machine: machine.hostname, category: "CPU", icon: "cpu.fill",
                                          severity: .critical, message: "CPU at \(machine.cpu.overallPercent)%"))
            } else if machine.cpu.overall > 0.75 {
                result.append(HealthIssue(machine: machine.hostname, category: "CPU", icon: "cpu.fill",
                                          severity: .warning, message: "CPU at \(machine.cpu.overallPercent)%"))
            }
            if machine.ram.pressureLevel >= 4 {
                result.append(HealthIssue(machine: machine.hostname, category: "Memory", icon: "memorychip.fill",
                                          severity: .critical, message: "Memory pressure critical"))
            } else if machine.ram.pressureLevel >= 2 {
                result.append(HealthIssue(machine: machine.hostname, category: "Memory", icon: "memorychip.fill",
                                          severity: .warning, message: "Memory pressure elevated"))
            }
            if machine.ram.swapUsedMB > 500 {
                result.append(HealthIssue(machine: machine.hostname, category: "Swap", icon: "arrow.triangle.swap",
                                          severity: .warning, message: String(format: "Swap %.0f MB", machine.ram.swapUsedMB)))
            }
            for vol in machine.disk.volumes {
                if vol.usedPercent > 0.95 {
                    result.append(HealthIssue(machine: machine.hostname, category: "Disk", icon: "internaldrive.fill",
                                              severity: .critical, message: "\(vol.name): \(String(format: "%.0f GB", vol.freeGB)) free"))
                } else if vol.usedPercent > 0.85 {
                    result.append(HealthIssue(machine: machine.hostname, category: "Disk", icon: "internaldrive.fill",
                                              severity: .warning, message: "\(vol.name): \(String(format: "%.0f GB", vol.freeGB)) free"))
                }
            }
            for smart in machine.disk.smart where !smart.isHealthy {
                result.append(HealthIssue(machine: machine.hostname, category: "SMART", icon: "exclamationmark.shield.fill",
                                          severity: .critical, message: "\(smart.bsdName): \(smart.status)"))
            }
            if machine.status == .offline {
                result.append(HealthIssue(machine: machine.hostname, category: "Connection", icon: "wifi.slash",
                                          severity: .critical, message: "Offline (\(machine.lastSeenFormatted))"))
            }
        }
        return result.sorted { $0.severity == .critical && $1.severity != .critical }
    }

    private var healthScore: Double {
        guard !appState.machines.isEmpty else { return 1.0 }
        let cp = Double(issues.filter { $0.severity == .critical }.count) * 0.2
        let wp = Double(issues.filter { $0.severity == .warning }.count) * 0.05
        return max(0, 1.0 - cp - wp)
    }

    private var healthEvents: [ActivityEvent] {
        appState.events.filter { $0.category == .health || $0.type == "crashDetected" || $0.type == "dnsFlushed" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Score + Summary
                HStack(spacing: Theme.paddingXL) {
                    // Score Ring
                    ZStack {
                        Circle()
                            .stroke(Theme.cardBorder, lineWidth: 6)
                            .frame(width: 88, height: 88)
                        Circle()
                            .trim(from: 0, to: healthScore)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 88, height: 88)
                            .rotationEffect(.degrees(-90))
                            .shadow(color: scoreColor.opacity(0.3), radius: 8)
                        VStack(spacing: 0) {
                            Text("\(Int(healthScore * 100))")
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .foregroundStyle(scoreColor)
                            Text("Health")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                                .textCase(.uppercase)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MetricDetailRow(label: "Machines", value: "\(appState.machines.count)")
                        MetricDetailRow(label: "Active Issues", value: "\(issues.count)",
                                        color: issues.isEmpty ? Theme.success : Theme.warning)
                        MetricDetailRow(label: "Critical", value: "\(issues.filter { $0.severity == .critical }.count)",
                                        color: issues.contains(where: { $0.severity == .critical }) ? Theme.critical : Theme.success)
                        MetricDetailRow(label: "Health Events", value: "\(healthEvents.count)")
                    }
                    .frame(width: 200)

                    Spacer()

                    // SMART Overview
                    if !appState.machines.flatMap({ $0.disk.smart }).isEmpty {
                        VStack(alignment: .leading, spacing: Theme.paddingSM) {
                            Text("DISK HEALTH")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)

                            ForEach(appState.machines) { machine in
                                ForEach(machine.disk.smart) { smart in
                                    HStack(spacing: 6) {
                                        Image(systemName: smart.isHealthy ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(smart.isHealthy ? Theme.success : Theme.critical)
                                            .shadow(color: (smart.isHealthy ? Theme.success : Theme.critical).opacity(0.3), radius: 3)
                                        Text("\(machine.hostname) / \(smart.bsdName)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .cardStyle(glow: scoreColor)

                // Issues Table
                if !issues.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.warning)
                            Text("Active Issues")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(issues.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.cardBorder)
                                .clipShape(Capsule())
                        }

                        VStack(spacing: 0) {
                            HStack {
                                Text("").frame(width: 20)
                                Text("ISSUE").frame(maxWidth: .infinity, alignment: .leading)
                                Text("MACHINE").frame(width: 120, alignment: .leading)
                                Text("CATEGORY").frame(width: 100, alignment: .leading)
                                Text("SEVERITY").frame(width: 80, alignment: .trailing)
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, Theme.paddingLG)
                            .padding(.vertical, 10)
                            .background(Theme.surfacePrimary)

                            Rectangle().fill(Theme.cardBorder).frame(height: 0.5)

                            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                                HStack {
                                    Image(systemName: issue.icon)
                                        .font(.caption)
                                        .foregroundStyle(issue.severity == .critical ? Theme.critical : Theme.warning)
                                        .shadow(color: (issue.severity == .critical ? Theme.critical : Theme.warning).opacity(0.3), radius: 3)
                                        .frame(width: 20)

                                    Text(issue.message)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(issue.machine)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(width: 120, alignment: .leading)

                                    Text(issue.category)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                        .frame(width: 100, alignment: .leading)

                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(issue.severity == .critical ? Theme.critical : Theme.warning)
                                            .frame(width: 6, height: 6)
                                            .shadow(color: (issue.severity == .critical ? Theme.critical : Theme.warning).opacity(0.4), radius: 2)
                                        Text(issue.severity == .critical ? "Critical" : "Warning")
                                            .font(.caption)
                                            .foregroundStyle(issue.severity == .critical ? Theme.critical : Theme.warning)
                                    }
                                    .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.horizontal, Theme.paddingLG)
                                .padding(.vertical, 7)

                                Rectangle().fill(Theme.cardBorder.opacity(0.5)).frame(height: 0.5)
                            }
                        }
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .stroke(Theme.cardBorder, lineWidth: 0.5)
                        )
                    }
                } else if !appState.machines.isEmpty {
                    HStack(spacing: Theme.paddingLG) {
                        ZStack {
                            Circle()
                                .fill(Theme.success.opacity(0.1))
                                .frame(width: 44, height: 44)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.success)
                                .shadow(color: Theme.success.opacity(0.4), radius: 6)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Systems Healthy")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Text("No issues detected across \(appState.machines.count) machines")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    .cardStyle(glow: Theme.success)
                }

                // Health Events
                if !healthEvents.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        HStack {
                            Image(systemName: "heart.text.clipboard.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.warning)
                            Text("Health Events")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        ForEach(healthEvents.prefix(10)) { event in
                            MacEventRow(event: event)
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(Theme.paddingXL)
        }
        .background(Theme.background)
    }

    private var scoreColor: Color {
        if healthScore > 0.8 { return Theme.success }
        if healthScore > 0.5 { return Theme.warning }
        return Theme.critical
    }
}

struct HealthIssue {
    let machine: String
    let category: String
    let icon: String
    let severity: HealthSeverity
    let message: String
}

enum HealthSeverity {
    case warning, critical
}
