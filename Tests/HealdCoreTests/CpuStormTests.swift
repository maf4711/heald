import Foundation
import Testing
@testable import HealdCore

struct CpuStormTests {
    @Test func etimeParses() {
        #expect(CpuStorm.parseEtime("01:29:34") == 5374)
        #expect(CpuStorm.parseEtime("21:38") == 1298)
        #expect(CpuStorm.parseEtime("2-03:04:05") == 183_845)
    }

    @Test func classifiesHudAndIgnoresWrappers() {
        #expect(
            CpuStorm.classify("bash -c \n CACHE=x; LOCKDIR=/x/statusline-daemon.lockdir; sleep 10")
                == .hudDaemon
        )
        #expect(
            CpuStorm.classify(
                "/bin/bash /Users/a321/Developer/dotfiles/grok/hooks/statusline-daemon.sh run-loop"
            ) == .hudDaemon
        )
        #expect(
            CpuStorm.classify(
                "/Applications/iTerm.app/Contents/Resources/utilities/it2 session list"
            ) == .it2
        )
        #expect(
            CpuStorm.classify(
                "bash -c IT2=/Applications/iTerm.app/Contents/Resources/utilities/it2; sleep 10"
            ) == nil
        )
        #expect(
            CpuStorm.classify("npm exec @claude-flow/cli hooks statusline --json")
                == .statuslineNpm
        )
        #expect(
            CpuStorm.classify("xcodebuild -project Foo.xcodeproj -showBuildSettings -json")
                == .showBuildSettings
        )
        #expect(
            CpuStorm.classify("timeout 90 xcodebuild -project Foo.xcodeproj -showBuildSettings -json")
                == nil
        )
        #expect(
            CpuStorm.classify(
                "/bin/zsh -c snap=x; eval -- timeout 90 xcodebuild -showBuildSettings -json"
            ) == nil
        )
        #expect(CpuStorm.classify("grok") == nil)
        #expect(CpuStorm.classify("xcodebuild -project App.xcodeproj test") == nil)
    }

    @Test func planKeepsOneHudAndPidfile() {
        func P(_ pid: Int32, _ kind: CpuStorm.Kind, _ etime: Int) -> CpuStorm.Proc {
            CpuStorm.Proc(pid: pid, etime: etime, args: kind.rawValue, kind: kind)
        }
        let hud = [
            P(10, .hudDaemon, 100),
            P(11, .hudDaemon, 50),
            P(12, .hudDaemon, 10),
        ]
        #expect(CpuStorm.plan(procs: hud, hold: false, hudPidfile: 11).map(\.0) == [10, 12])
        #expect(CpuStorm.plan(procs: hud, hold: false, hudPidfile: nil).map(\.0) == [11, 12])
        #expect(CpuStorm.plan(procs: hud, hold: true, hudPidfile: nil).isEmpty)
        let melt = (0..<6).map { P(Int32(100 + $0), .hudDaemon, $0) }
        #expect(!CpuStorm.plan(procs: melt, hold: true, hudPidfile: nil).isEmpty)
    }

    @Test func planCapsIt2AndAgesNpm() {
        func P(_ pid: Int32, _ kind: CpuStorm.Kind, _ etime: Int) -> CpuStorm.Proc {
            CpuStorm.Proc(pid: pid, etime: etime, args: kind.rawValue, kind: kind)
        }
        let it2 = (20..<26).map { P(Int32($0), .it2, 100 - $0) }
        #expect(CpuStorm.plan(procs: Array(it2.prefix(4)), hold: false, hudPidfile: nil).isEmpty)
        #expect(CpuStorm.plan(procs: it2, hold: false, hudPidfile: nil).count == 2)
        let npm = [P(30, .statuslineNpm, 20), P(31, .statuslineNpm, 5)]
        #expect(CpuStorm.plan(procs: npm, hold: false, hudPidfile: nil).map(\.0) == [30])
        let settings = [P(40, .showBuildSettings, 130), P(41, .showBuildSettings, 10)]
        #expect(CpuStorm.plan(procs: settings, hold: false, hudPidfile: nil).map(\.0) == [40])
    }

    @Test func holdExpires() {
        let now = Date()
        #expect(CpuStorm.holdActive(now: now, holdMtime: nil) == false)
        #expect(CpuStorm.holdActive(now: now, holdMtime: now.addingTimeInterval(-60)) == true)
        #expect(
            CpuStorm.holdActive(now: now, holdMtime: now.addingTimeInterval(-7 * 3600)) == false
        )
    }
}
