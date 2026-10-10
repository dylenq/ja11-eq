import Testing
@testable import JA11Kit

/// Tests for how an open result is classified and worded (D-10). They use the error type only and
/// never create a transport.
@Suite struct HIDTransportErrorTests {
    static let notPermitted = Int32(bitPattern: 0xE00002E2)
    static let notPrivileged = Int32(bitPattern: 0xE00002C1)
    static let exclusiveAccess = Int32(bitPattern: 0xE00002C5)
    static let settingsPath = "System Settings → Privacy & Security → Input Monitoring"

    @Test func aNotPermittedOpenIsAccessDenied() {
        #expect(HIDTransportError.forOpenResult(Self.notPermitted) == .accessDenied(code: Self.notPermitted))
    }

    @Test func aNotPrivilegedOpenIsAccessDenied() {
        #expect(HIDTransportError.forOpenResult(Self.notPrivileged) == .accessDenied(code: Self.notPrivileged))
    }

    @Test func theAccessDeniedMessageNamesInputMonitoringAndWhereToFindIt() {
        for code in [Self.notPermitted, Self.notPrivileged] {
            #expect(HIDTransportError.forOpenResult(code).description.contains(Self.settingsPath))
        }
    }

    @Test func anyOtherOpenResultKeepsItsCodeAndDoesNotMentionInputMonitoring() {
        let error = HIDTransportError.forOpenResult(Self.exclusiveAccess)

        #expect(error == .openFailed(code: Self.exclusiveAccess))
        #expect(error.description.contains("0xE00002C5"))
        #expect(!error.description.contains("Input Monitoring"))
    }

    @Test func aFailedSendKeepsItsCode() {
        #expect(HIDTransportError.sendFailed(code: Self.exclusiveAccess).description.contains("0xE00002C5"))
    }
}
