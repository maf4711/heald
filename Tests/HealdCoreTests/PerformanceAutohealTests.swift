import Foundation
import Testing
@testable import HealdCore

struct PerformanceAutohealTests {
    @Test func bootLoadAboveHalfCoresIsDegraded() {
        #expect(PerformanceAutoheal.isDegraded(load1: 8, ncpu: 14, cpuOverall: 0.2, uptime: 120) == true)
        #expect(PerformanceAutoheal.isDegraded(load1: 2, ncpu: 14, cpuOverall: 0.2, uptime: 120) == false)
    }

    @Test func steadyStateNeedsNearSaturation() {
        #expect(PerformanceAutoheal.isDegraded(load1: 8, ncpu: 14, cpuOverall: 0.2, uptime: 3600) == false)
        #expect(PerformanceAutoheal.isDegraded(load1: 12, ncpu: 14, cpuOverall: 0.2, uptime: 3600) == true)
        #expect(PerformanceAutoheal.isDegraded(load1: 1, ncpu: 14, cpuOverall: 0.8, uptime: 3600) == true)
    }

    @Test func stripsRunAtLoadOnlyOnIntervalBackgroundJobs() {
        #expect(PerformanceAutoheal.shouldStripRunAtLoad(
            runAtLoad: true, keepAlive: false, startInterval: 1200
        ) == true)
        #expect(PerformanceAutoheal.shouldStripRunAtLoad(
            runAtLoad: true, keepAlive: true, startInterval: nil
        ) == false)
        #expect(PerformanceAutoheal.shouldStripRunAtLoad(
            runAtLoad: false, keepAlive: false, startInterval: 1200
        ) == false)
        #expect(PerformanceAutoheal.shouldStripRunAtLoad(
            runAtLoad: true, keepAlive: false, startInterval: nil
        ) == false)
    }

    @Test func neverStripsProtectedAgentLabels() {
        #expect(PerformanceAutoheal.isProtectedAgentLabel("com.heald.daemon") == true)
        #expect(PerformanceAutoheal.isProtectedAgentLabel("ai.openclaw.gateway") == true)
        #expect(PerformanceAutoheal.isProtectedAgentLabel("com.merados.apple-mail-auto") == false)
        #expect(PerformanceAutoheal.isProtectedAgentLabel("com.merados.devsync") == false)
    }

    @Test func debugBuildPathsAreLoginItemJunk() {
        #expect(PerformanceAutoheal.isDebugLoginItemPath(
            "/Users/a321/Developer/AufRaum/build/Build/Products/Debug/AufRaum.app"
        ) == true)
        #expect(PerformanceAutoheal.isDebugLoginItemPath(
            "/Users/a321/Library/Developer/Xcode/DerivedData/Foo/Build/Products/Debug/Foo.app"
        ) == true)
        #expect(PerformanceAutoheal.isDebugLoginItemPath("/Applications/Stats.app") == false)
    }

    @Test func protectsNamedLoginItems() {
        #expect(PerformanceAutoheal.isProtectedLoginItem("Wispr Flow") == true)
        #expect(PerformanceAutoheal.isProtectedLoginItem("Stats") == true)
        #expect(PerformanceAutoheal.isProtectedLoginItem("AufRaum") == false)
    }

    @Test func runawayDuIsOnlyDocumentsTree() {
        let home = "/Users/a321"
        #expect(PerformanceAutoheal.isRunawayDocumentsDu(
            arguments: ["-sk", "/Users/a321/Documents"],
            home: home
        ) == true)
        #expect(PerformanceAutoheal.isRunawayDocumentsDu(
            arguments: ["-sk", "/Users/a321/Library/Caches"],
            home: home
        ) == false)
    }
}
