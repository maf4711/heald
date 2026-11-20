import Foundation
import Testing
@testable import HealdCore

/// Reviewer F7: tokens / secrets never leave the device in samples, cloud or SIEM payloads.
struct SecretRedactorTests {
    @Test func secretsAreRedacted() throws {
        let s = SecretRedactor.redact("""
        Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc.def token=0123456789abcdef0123456789abcdef \
        key=QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVowMTIzNDU2Nzg5 dsid=12345678901 \
        path=/System/Library/PrivateFrameworks/CoreAnalytics.framework addr=0xfffffe0012345678
        """)
        #expect(!s.contains("eyJhbGci"))
        #expect(!s.contains("0123456789abcdef0123456789abcdef"))
        #expect(!s.contains("QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVowMTIzNDU2Nzg5"))
        #expect(!s.contains("12345678901"))
        #expect(s.contains("/System/Library/PrivateFrameworks/CoreAnalytics.framework"))
        #expect(s.contains("0xfffffe0012345678"))
    }
}
