import SwiftUI

struct SettingsView: View {
    var isOnboarding = false

    @Environment(AppState.self) private var appState
    @AppStorage("heald_api_url") private var apiURL = "https://heald.merados.com"
    @AppStorage("heald_api_key") private var apiKey = "REDACTED"
    @AppStorage("heald_refresh_interval") private var refreshInterval = 10.0
    @AppStorage("heald_notifications_enabled") private var notificationsEnabled = true
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var draftURL = ""
    @State private var draftKey = ""
    @State private var didInitDrafts = false

    private var currentURL: Binding<String> {
        isOnboarding ? $draftURL : $apiURL
    }

    private var currentKey: Binding<String> {
        isOnboarding ? $draftKey : $apiKey
    }

    var body: some View {
        NavigationStack {
            List {
                if isOnboarding {
                    onboardingHeader
                }

                // Connection
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API URL")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                        TextField("https://heald.merados.com", text: currentURL)
                            .font(.subheadline.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    .listRowBackground(Theme.cardBackground)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                        SecureField("Enter your API key", text: currentKey)
                            .font(.subheadline.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .listRowBackground(Theme.cardBackground)

                    if let result = testResult {
                        HStack {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.success ? Theme.success : Theme.critical)
                            Text(result.message)
                                .font(.caption)
                                .foregroundStyle(result.success ? Theme.success : Theme.critical)
                        }
                        .listRowBackground(Theme.cardBackground)
                    }
                } header: {
                    Text("Connection")
                        .foregroundStyle(Theme.textSecondary)
                }

                if isOnboarding {
                    Section {
                        Button {
                            connectAndContinue()
                        } label: {
                            HStack {
                                Spacer()
                                if isTesting {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                    Text("Verbinde...")
                                        .fontWeight(.semibold)
                                } else {
                                    Text("Verbinden")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 4)
                        }
                        .disabled(currentKey.wrappedValue.isEmpty || isTesting)
                        .listRowBackground(
                            currentKey.wrappedValue.isEmpty
                                ? Color.gray
                                : Theme.accent
                        )
                    }
                } else {
                    Section {
                        Button {
                            testConnection()
                        } label: {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                        .tint(Theme.accent)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                Text(isTesting ? "Testing..." : "Test Connection")
                            }
                            .foregroundStyle(Theme.accent)
                        }
                        .disabled(apiKey.isEmpty || isTesting)
                        .listRowBackground(Theme.cardBackground)
                    }
                }

                if !isOnboarding {
                    // Preferences
                    Section {
                        HStack {
                            Text("Refresh Interval")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Picker("", selection: $refreshInterval) {
                                Text("5s").tag(5.0)
                                Text("10s").tag(10.0)
                                Text("30s").tag(30.0)
                                Text("60s").tag(60.0)
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.accent)
                        }
                        .listRowBackground(Theme.cardBackground)

                        Toggle(isOn: $notificationsEnabled) {
                            Text("Push Notifications")
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.accent)
                        .listRowBackground(Theme.cardBackground)
                    } header: {
                        Text("Preferences")
                            .foregroundStyle(Theme.textSecondary)
                    }

                    // Info
                    Section {
                        HStack {
                            Text("Machines Connected")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(appState.machines.count)")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.cardBackground)

                        HStack {
                            Text("Events Loaded")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(appState.events.count)")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.cardBackground)

                        if let last = appState.lastRefresh {
                            HStack {
                                Text("Last Refresh")
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(last, format: .dateTime.hour().minute().second())
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .listRowBackground(Theme.cardBackground)
                        }
                    } header: {
                        Text("Status")
                            .foregroundStyle(Theme.textSecondary)
                    }

                    // About
                    Section {
                        HStack {
                            Text("Version")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("1.0.0")
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .listRowBackground(Theme.cardBackground)
                    } header: {
                        Text("About")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isOnboarding ? "Setup" : "Settings")
            .onAppear {
                guard !didInitDrafts else { return }
                didInitDrafts = true
                draftURL = apiURL
                draftKey = apiKey
            }
        }
    }

    // MARK: - Onboarding Header

    private var onboardingHeader: some View {
        Section {
            VStack(spacing: Theme.paddingLG) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)

                VStack(spacing: 6) {
                    Text("Welcome to Heald")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Connect to your Heald dashboard to monitor your Macs.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.paddingLG)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Connect (Onboarding)

    private func connectAndContinue() {
        isTesting = true
        testResult = nil

        // Save draft values to AppStorage so HealdAPI can use them
        apiURL = draftURL
        apiKey = draftKey

        Task {
            do {
                let machines = try await HealdAPI.shared.fetchMachines()
                await MainActor.run {
                    testResult = TestResult(
                        success: true,
                        message: "Verbunden. \(machines.count) Mac(s) gefunden."
                    )
                    isTesting = false
                    appState.markConfigured()
                    Task { await appState.refresh() }
                }
            } catch {
                await MainActor.run {
                    testResult = TestResult(success: false, message: error.localizedDescription)
                    isTesting = false
                    // Don't clear stored values — user can retry
                }
            }
        }
    }

    // MARK: - Test Connection

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                let machines = try await HealdAPI.shared.fetchMachines()
                await MainActor.run {
                    testResult = TestResult(
                        success: true,
                        message: "Connected. \(machines.count) machine(s) found."
                    )
                    isTesting = false
                    if isOnboarding {
                        Task { await appState.refresh() }
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = TestResult(success: false, message: error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}

private struct TestResult {
    let success: Bool
    let message: String
}
