import ArgumentParser
import Foundation

// MARK: - Enroll (device token)

struct EnrollCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enroll",
        abstract: "Create per-device fleet identity + token (bank auth)"
    )

    @Flag(name: .long, help: "Rotate token even if enrolled")
    var force: Bool = false

    @Flag(name: .long, help: "Show existing enrollment only")
    var show: Bool = false

    @Flag(name: .long, help: "POST device to fleet /api/enroll (needs HEALD_ADMIN_KEY)")
    var register: Bool = false

    @Option(name: .long, help: "Fleet base URL (default https://heald.sh)")
    var fleetURL: String?

    @Option(name: .long, help: "Admin API key for register (or HEALD_ADMIN_KEY / HEALD_API_KEY)")
    var adminKey: String?

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        if show {
            if let d = DeviceIdentity.load() {
                print("deviceId:  \(d.deviceId)")
                print("hostname:  \(d.hostname)")
                print("serial:    \(d.serialNumber ?? "—")")
                print("hwUUID:    \(d.hardwareUUID ?? "—")")
                print("enrolled:  \(d.enrolledAt)")
                print("token:     \(d.token.prefix(8))… (\(d.token.count) hex chars)")
                print("path:      \(DeviceIdentity.deviceURL.path)")
                print("hint:      heald enroll --register  (admin key) or HEALD_DEVICE_TOKENS")
            } else {
                print("Not enrolled — run: heald enroll")
                throw ExitCode(1)
            }
            return
        }
        let d: DeviceRecord
        switch DeviceIdentity.ensureBoundToThisMac() {
        case .reenrolled(let was, let archive, let rec):
            // Already rotated for this Mac — `--force` must not rotate a second time.
            print("identity: re-enrolled (was \(was)) — cloned ~/.heald archived to \(archive.path)")
            d = rec
        case .failed(let why):
            print("identity: MISMATCH — re-enroll failed (rolled back, device.json kept): \(why)")
            throw ExitCode(1)
        default:
            d = try DeviceIdentity.enroll(force: force, checkBinding: false)
        }
        print("Enrolled heald device")
        print("deviceId:  \(d.deviceId)")
        print("serial:    \(d.serialNumber ?? "—")")
        print("token:     \(d.token)")
        print("path:      \(DeviceIdentity.deviceURL.path) (mode 600)")

        if register {
            let base = fleetURL
                ?? ProcessInfo.processInfo.environment["HEALD_FLEET_URL"]
                ?? "https://heald.sh"
            let key = adminKey
                ?? ProcessInfo.processInfo.environment["HEALD_ADMIN_KEY"]
                ?? ProcessInfo.processInfo.environment["HEALD_API_KEY"]
                ?? ""
            guard !key.isEmpty else {
                print("Error: --register needs HEALD_ADMIN_KEY or --admin-key")
                throw ExitCode(2)
            }
            guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/enroll") else {
                print("Error: bad fleet URL")
                throw ExitCode(2)
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "deviceId": d.deviceId,
                "token": d.token,
                "hostname": d.hostname,
                "serialNumber": d.serialNumber as Any,
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 15
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let text = String(data: data, encoding: .utf8) ?? ""
            if code == 200 {
                print("Registered with fleet \(url.absoluteString)")
            } else {
                print("Fleet register failed HTTP \(code): \(text.prefix(200))")
                throw ExitCode(1)
            }
        } else {
            print("")
            print("Next: heald enroll --register   # push token to fleet admin registry")
            print("  or: add token to HEALD_DEVICE_TOKENS / HEALD_API_KEYS on server")
        }
    }
}
