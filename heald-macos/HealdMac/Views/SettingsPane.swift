import SwiftUI

struct SettingsPane: View {
    @Environment(AppState.self) private var appState
    @AppStorage("heald_api_url") private var apiURL = "https://heald.merados.com"
    @AppStorage("heald_api_key") private var apiKey = "REDACTED"
    @AppStorage("heald_refresh_interval") private var refreshInterval = 10.0
    @State private var isTesting = false
    @State private var testResult: (success: Bool, message: String)?

    var body: some View {
        Form {
            Section("Connection") {
                TextField("API URL", text: $apiURL)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(apiKey.isEmpty || isTesting)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(Theme.accent)
                    }

                    if let result = testResult {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.success ? Theme.success : Theme.critical)
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(result.success ? Theme.success : Theme.critical)
                    }
                }
            }

            Section("Refresh") {
                Picker("Interval", selection: $refreshInterval) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                }
                .onChange(of: refreshInterval) {
                    appState.stopAutoRefresh()
                    appState.startAutoRefresh()
                }
            }

            Section("Status") {
                LabeledContent("Machines") {
                    Text("\(appState.machines.count)")
                }
                LabeledContent("Events") {
                    Text("\(appState.events.count)")
                }
                if let last = appState.lastRefresh {
                    LabeledContent("Last Refresh") {
                        Text(last, format: .dateTime.hour().minute().second())
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("1.0.0")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 380)
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let machines = try await HealdAPI.shared.fetchMachines()
                await MainActor.run {
                    testResult = (true, "\(machines.count) machine(s) found")
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = (false, error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}
