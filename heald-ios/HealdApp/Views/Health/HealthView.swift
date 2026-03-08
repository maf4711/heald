import SwiftUI

struct HealthView: View {
    @Environment(AppState.self) private var appState

    private var smartStatuses: [(Machine, SMARTStatus)] {
        appState.machines.flatMap { machine in
            machine.disk.smart.map { (machine, $0) }
        }
    }

    private var healthIssues: [HealthIssue] {
        var issues: [HealthIssue] = []

        for machine in appState.machines {
            // CPU
            if machine.cpu.overall > 0.9 {
                issues.append(HealthIssue(
                    machine: machine.hostname,
                    category: "CPU",
                    icon: "cpu",
                    severity: .critical,
                    message: "CPU at \(machine.cpu.overallPercent)%"
                ))
            } else if machine.cpu.overall > 0.75 {
                issues.append(HealthIssue(
                    machine: machine.hostname,
                    category: "CPU",
                    icon: "cpu",
                    severity: .warning,
                    message: "CPU at \(machine.cpu.overallPercent)%"
                ))
            }

            // RAM
            if machine.ram.pressureLevel >= 4 {
                issues.append(HealthIssue(
                    machine: machine.hostname,
                    category: "Memory",
                    icon: "memorychip",
                    severity: .critical,
                    message: "Memory pressure critical"
                ))
            } else if machine.ram.pressureLevel >= 2 {
                issues.append(HealthIssue(
                    machine: machine.hostname,
                    category: "Memory",
                    icon: "memorychip",
                    severity: .warning,
                    message: "Memory pressure elevated"
                ))
            }

            // Swap
            if machine.ram.swapUsedMB > 500 {
                issues.append(HealthIssue(
                    machine: machine.hostname,
                    category: "Swap",
                    icon: "arrow.triangle.swap",
                    severity: .warning,
                    message: String(format: "Swap usage %.0f MB", machine.ram.swapUsedMB)
                ))
            }

            // Disk
            for vol in machine.disk.volumes {
                if vol.usedPercent > 0.95 {
                    issues.append(HealthIssue(
                        machine: machine.hostname,
                        category: "Disk",
                        icon: "internaldrive",
                        severity: .critical,
                        message: "\(vol.name): \(String(format: "%.0f GB", vol.freeGB)) free"
                    ))
                } else if vol.usedPercent > 0.85 {
                    issues.append(HealthIssue(
                        machine: machine.hostname,
                        category: "Disk",
                        icon: "internaldrive",
                        severity: .warning,
                        message: "\(vol.name): \(String(format: "%.0f GB", vol.freeGB)) free"
                    ))
                }
            }

            // SMART
            for smart in machine.disk.smart where !smart.isHealthy {
                issues.append(HealthIssue(
                    machine: machine.hostname,
                    category: "SMART",
                    icon: "exclamationmark.shield",
                    severity: .critical,
                    message: "\(smart.bsdName): \(smart.status)"
                ))
            }

            // Offline
            if machine.status == .offline {
                issues.append(HealthIssue(
                    machine: machine.hostname,
                    category: "Connection",
                    icon: "wifi.slash",
                    severity: .critical,
                    message: "Machine offline (\(machine.lastSeenFormatted))"
                ))
            }
        }

        return issues.sorted { $0.severity == .critical && $1.severity != .critical }
    }

    private var healthEvents: [ActivityEvent] {
        appState.events.filter {
            $0.category == .health || $0.type == "crashDetected" || $0.type == "dnsFlushed"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.paddingLG) {
                    // Overall Status
                    overallStatus

                    // Active Issues
                    if !healthIssues.isEmpty {
                        issuesSection
                    }

                    // SMART Status
                    if !smartStatuses.isEmpty {
                        smartSection
                    }

                    // Health Events
                    if !healthEvents.isEmpty {
                        healthEventsSection
                    }

                    // All Good
                    if healthIssues.isEmpty && appState.machines.isEmpty == false {
                        allGoodView
                    }
                }
                .padding(.horizontal, Theme.paddingLG)
                .padding(.bottom, Theme.paddingXL)
            }
            .background(Theme.background)
            .navigationTitle("Health")
            .refreshable {
                await appState.refresh()
            }
        }
    }

    // MARK: - Overall Status

    private var overallStatus: some View {
        HStack(spacing: Theme.paddingLG) {
            VStack(spacing: Theme.paddingSM) {
                ZStack {
                    Circle()
                        .stroke(Theme.cardBorder, lineWidth: 4)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: healthScore)
                        .stroke(healthScoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(healthScore * 100))")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(healthScoreColor)
                }
                Text("Health Score")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                MetricRow(
                    label: "Machines",
                    value: "\(appState.machines.count)",
                    color: Theme.textPrimary
                )
                MetricRow(
                    label: "Issues",
                    value: "\(healthIssues.count)",
                    color: healthIssues.isEmpty ? Theme.success : Theme.warning
                )
                MetricRow(
                    label: "Critical",
                    value: "\(healthIssues.filter { $0.severity == .critical }.count)",
                    color: healthIssues.contains(where: { $0.severity == .critical }) ? Theme.critical : Theme.success
                )
            }
        }
        .cardStyle()
    }

    private var healthScore: Double {
        guard !appState.machines.isEmpty else { return 1.0 }
        let criticalPenalty = Double(healthIssues.filter { $0.severity == .critical }.count) * 0.2
        let warningPenalty = Double(healthIssues.filter { $0.severity == .warning }.count) * 0.05
        return max(0, 1.0 - criticalPenalty - warningPenalty)
    }

    private var healthScoreColor: Color {
        if healthScore > 0.8 { return Theme.success }
        if healthScore > 0.5 { return Theme.warning }
        return Theme.critical
    }

    // MARK: - Issues

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            SectionHeader(title: "Active Issues", icon: "exclamationmark.triangle", value: "\(healthIssues.count)")

            ForEach(Array(healthIssues.enumerated()), id: \.offset) { _, issue in
                HStack(spacing: Theme.paddingMD) {
                    Image(systemName: issue.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(issue.severity == .critical ? Theme.critical : Theme.warning)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.message)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(issue.machine) -- \(issue.category)")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    Circle()
                        .fill(issue.severity == .critical ? Theme.critical : Theme.warning)
                        .frame(width: 8, height: 8)
                }
                .padding(.vertical, 4)
            }
        }
        .cardStyle()
    }

    // MARK: - SMART

    private var smartSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            SectionHeader(title: "Disk Health (SMART)", icon: "internaldrive", value: "")

            ForEach(Array(smartStatuses.enumerated()), id: \.offset) { _, item in
                let (machine, smart) = item
                HStack {
                    Image(systemName: smart.isHealthy ? "checkmark.shield.fill" : "xmark.shield.fill")
                        .foregroundStyle(smart.isHealthy ? Theme.success : Theme.critical)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(smart.bsdName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(machine.hostname)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text(smart.status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(smart.isHealthy ? Theme.success : Theme.critical)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Health Events

    private var healthEventsSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            SectionHeader(title: "Health Events", icon: "heart.text.clipboard", value: "\(healthEvents.count)")

            ForEach(healthEvents.prefix(10)) { event in
                EventRow(event: event)
                if event.id != healthEvents.prefix(10).last?.id {
                    Divider().background(Theme.cardBorder)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - All Good

    private var allGoodView: some View {
        VStack(spacing: Theme.paddingMD) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.success)
            Text("All Systems Healthy")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("No issues detected across all machines")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .cardStyle()
    }
}

// MARK: - Health Issue Model

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
