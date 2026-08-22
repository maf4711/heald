import Foundation
import Testing
@testable import HealdCore

struct DirectorySizeCacheTests {
    @Test func cacheHitDoesNotRecompute() {
        var cache = DirectorySizeCache(ttl: 1800)
        var computes = 0
        let url = URL(fileURLWithPath: "/tmp")
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        let first = cache.bytes(at: url, now: t0) { _ in
            computes += 1
            return 100
        }
        let second = cache.bytes(at: url, now: t0.addingTimeInterval(10)) { _ in
            computes += 1
            return 999
        }

        #expect(first == 100)
        #expect(second == 100)
        #expect(computes == 1)
    }

    @Test func cacheExpiresAfterTTL() {
        var cache = DirectorySizeCache(ttl: 60)
        var computes = 0
        let url = URL(fileURLWithPath: "/tmp")
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        _ = cache.bytes(at: url, now: t0) { _ in
            computes += 1
            return 1
        }
        let expired = cache.bytes(at: url, now: t0.addingTimeInterval(61)) { _ in
            computes += 1
            return 2
        }

        #expect(expired == 2)
        #expect(computes == 2)
    }

    @Test func bootIsNotSettledDuringLoginStampede() {
        #expect(BootStampede.settled(uptime: 10, minimum: 180) == false)
        #expect(BootStampede.settled(uptime: 180, minimum: 180) == true)
        #expect(BootStampede.settled(uptime: 400, minimum: 180) == true)
    }

    @Test func doesNotDownloadICloudPlaceholdersJustBecauseTheyExist() {
        #expect(ICloudHealPolicy.shouldDownloadPlaceholders(
            evictedDirCount: 0,
            lastHeal: nil,
            now: Date(timeIntervalSince1970: 1_000_000)
        ) == false)
    }

    @Test func doesNotReDownloadEvictedDirsInsideCooldown() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        #expect(ICloudHealPolicy.shouldDownloadPlaceholders(
            evictedDirCount: 2,
            lastHeal: t0,
            now: t0.addingTimeInterval(60),
            cooldown: 3600
        ) == false)
    }

    @Test func downloadsEvictedDirsAfterCooldown() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        #expect(ICloudHealPolicy.shouldDownloadPlaceholders(
            evictedDirCount: 1,
            lastHeal: t0,
            now: t0.addingTimeInterval(3601),
            cooldown: 3600
        ) == true)
        #expect(ICloudHealPolicy.shouldDownloadPlaceholders(
            evictedDirCount: 1,
            lastHeal: nil,
            now: t0
        ) == true)
    }
}
