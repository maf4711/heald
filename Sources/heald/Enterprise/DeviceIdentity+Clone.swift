import Foundation
import HealdCore
import OSLog

/// Result of checking ~/.heald/device.json against this Mac's IOPlatformUUID (issue #18).
enum IdentityStatus: Sendable {
    case ok
    case notEnrolled
    /// ioreg returned no UUID — identity kept, check repeats next start.
    case unverifiable
    /// Record had no hardwareUUID — kept (same deviceId/token), UUID recorded.
    case backfilled
    /// Record came from another Mac: its per-device state was archived and a new identity enrolled.
    case reenrolled(wasPrefix: String, archive: URL, record: DeviceRecord)
    /// Mismatch detected but archiving or saving failed — everything was rolled back, the old
    /// device.json is still in place, and the check repeats next start.
    case failed(String)
}

extension DeviceIdentity {
    static var healdDir: URL { deviceURL.deletingLastPathComponent() }
    static var identityLockURL: URL { healdDir.appendingPathComponent(".identity.lock") }

    /// If device.json was enrolled on another Mac: warn, archive it and the copied per-device data into
    /// ~/.heald/data/.cloned-<prefix>-<ts>/ (never delete), then enroll a fresh identity.
    /// Serialised by an flock so the daemon and `heald enroll` cannot both rotate.
    /// Run before anything reads device.json, the outbox, findings or push cursors.
    @discardableResult
    static func ensureBoundToThisMac() -> IdentityStatus {
        IdentityLock.withLock(at: identityLockURL) { checkAndRebind() }
    }

    private static func checkAndRebind() -> IdentityStatus {
        guard var stored = load() else { return .notEnrolled }
        let current = hardwareUUID()
        switch CloneDetection.decide(
            storedHardwareUUID: stored.hardwareUUID,
            storedDeviceId: stored.deviceId,
            currentHardwareUUID: current
        ) {
        case .keep:
            return current == nil ? .unverifiable : .ok
        case .backfill:
            stored.hardwareUUID = current
            do {
                try save(stored)
                Logger.lifecycle.info("device.json: backfilled hardwareUUID (identity kept)")
            } catch {
                Logger.lifecycle.error("device.json backfill failed: \(error.localizedDescription, privacy: .public)")
            }
            return .backfilled
        case .reenroll:
            return rebind(stored: stored, current: current)
        }
    }

    private static func rebind(stored: DeviceRecord, current: String?) -> IdentityStatus {
        let was = CloneDetection.idPrefix(stored.deviceId)
        Logger.lifecycle.warning(
            "Cloned ~/.heald: device.json belongs to \(was, privacy: .public)… (hw \(stored.hardwareUUID ?? "nil", privacy: .public)), this Mac is \(current ?? "?", privacy: .public) — archiving per-device state and re-enrolling"
        )
        // The UUID read above is reused: a second ioreg probe that timed out would yield a nil-hw record.
        let fresh = makeRecord(hardwareUUID: current)
        do {
            let rel = try CloneDetection.relocate(
                healdDir: healdDir,
                sourceDeviceId: stored.deviceId,
                commit: { try save(fresh) } // new identity written last; old device.json copied first
            )
            Logger.lifecycle.warning(
                "Cloned identity archived to \(rel.archiveDirectory.path, privacy: .public): \(rel.moved.joined(separator: ", "), privacy: .public); new id=\(fresh.deviceId.prefix(8), privacy: .public)…"
            )
            return .reenrolled(wasPrefix: was, archive: rel.archiveDirectory, record: fresh)
        } catch {
            Logger.lifecycle.error("Cloned identity re-enroll failed, rolled back: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Read-only identity line for `heald doctor` — decides but never relocates or enrolls.
    static func identitySummary() -> String {
        guard let stored = load() else { return "not enrolled" }
        let current = hardwareUUID()
        switch CloneDetection.decide(
            storedHardwareUUID: stored.hardwareUUID,
            storedDeviceId: stored.deviceId,
            currentHardwareUUID: current
        ) {
        case .keep: return current == nil ? "unverified (no IOPlatformUUID)" : "ok"
        case .backfill: return "ok (hardwareUUID missing — recorded on next daemon start / enroll)"
        case .reenroll:
            return "MISMATCH (enrolled on \(CloneDetection.idPrefix(stored.deviceId))…) — run heald enroll"
        }
    }
}
