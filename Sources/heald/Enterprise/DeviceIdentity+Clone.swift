import Foundation
import HealdCore
import OSLog

/// Result of checking ~/.heald/device.json against this Mac's IOPlatformUUID (issue #18).
enum IdentityStatus: Sendable {
    case ok
    case notEnrolled
    /// ioreg returned no UUID — identity kept, check repeats next start.
    case unverifiable
    /// Record came from another Mac: its per-device state was archived and a new identity enrolled.
    case reenrolled(wasPrefix: String, archive: URL, record: DeviceRecord)
    /// Mismatch detected but archiving or enrolling failed — the old record was left untouched.
    case failed(String)

    /// One-line form for `heald doctor`.
    var summary: String {
        switch self {
        case .ok: "ok"
        case .notEnrolled: "not enrolled"
        case .unverifiable: "unverified (no IOPlatformUUID)"
        case .reenrolled(let was, _, _): "re-enrolled (was \(was))"
        case .failed(let why): "MISMATCH — re-enroll failed: \(why)"
        }
    }
}

extension DeviceIdentity {
    static var healdDir: URL { deviceURL.deletingLastPathComponent() }

    /// If device.json was enrolled on another Mac: warn, move it and the copied per-device data into
    /// ~/.heald/data/.cloned-<prefix>-<ts>/ (never delete), then enroll a fresh identity.
    /// Run before anything reads device.json, the outbox, findings or push cursors.
    @discardableResult
    static func ensureBoundToThisMac() -> IdentityStatus {
        guard let stored = load() else { return .notEnrolled }
        let current = hardwareUUID()
        let decision = CloneDetection.decide(
            storedHardwareUUID: stored.hardwareUUID,
            storedDeviceId: stored.deviceId,
            currentHardwareUUID: current
        )
        guard decision == .reenroll else { return current == nil ? .unverifiable : .ok }

        let was = CloneDetection.idPrefix(stored.deviceId)
        Logger.lifecycle.warning(
            "Cloned ~/.heald: device.json belongs to \(was, privacy: .public)… (hw \(stored.hardwareUUID ?? "nil", privacy: .public)), this Mac is \(current ?? "?", privacy: .public) — archiving per-device state and re-enrolling"
        )
        do {
            let rel = try CloneDetection.relocate(healdDir: healdDir, sourceDeviceId: stored.deviceId)
            Logger.lifecycle.warning(
                "Cloned identity archived to \(rel.archiveDirectory.path, privacy: .public): \(rel.moved.joined(separator: ", "), privacy: .public)"
            )
            let rec = try enroll(force: true)
            return .reenrolled(wasPrefix: was, archive: rel.archiveDirectory, record: rec)
        } catch {
            Logger.lifecycle.error("Cloned identity re-enroll failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }
}
