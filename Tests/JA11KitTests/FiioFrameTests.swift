import Testing
@testable import JA11Kit

/// Codec tests. They never create a transport and never touch IOKit, so they pass with the dongle
/// unplugged and cannot send anything.
@Suite struct FiioFrameTests {
    // MARK: - Reference frames (CONTEXT D-03, D-05)

    /// The slot read request before padding.
    static let slotRequest: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x16, 0x00, 0x00, 0xEE]
    /// A reply saying the active slot is 3 (USER1).
    static let slotReply: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x16, 0x01, 0x03, 0x00, 0xEE]

    /// A frame zero-padded to one full report.
    static func padded(_ frame: [UInt8]) -> [UInt8] {
        frame + [UInt8](repeating: 0x00, count: max(0, JA11.payloadLength - frame.count))
    }

    /// A report as macOS may deliver it: with the report-ID byte in front.
    static func withReportID(_ report: [UInt8]) -> [UInt8] {
        [JA11.reportID] + report
    }

    // MARK: - Request building (D-03)

    @Test func paddedSlotRequestIsTheReferenceFrameFollowedByTwelveZeroBytes() {
        let frame = FiioFrame.getRequest(.presetSlot)
        #expect(frame == Self.slotRequest + [UInt8](repeating: 0x00, count: 12))
        #expect(frame.count == 20)
    }

    @Test func paddedIsTheDefaultForm() {
        #expect(FiioFrame.getRequest(.presetSlot) == FiioFrame.getRequest(.presetSlot, form: .padded))
    }

    @Test func unpaddedSlotRequestIsExactlyTheReferenceFrame() {
        #expect(FiioFrame.getRequest(.presetSlot, form: .unpadded) == Self.slotRequest)
    }

    // MARK: - The send gate (D-03, D-04)

    @Test func gateAcceptsBothFormsOfTheSlotRequest() {
        #expect(FiioFrame.isGetRequest(Self.padded(Self.slotRequest)))
        #expect(FiioFrame.isGetRequest(Self.slotRequest))
    }

    @Test func gateRejectsA21ByteFrame() {
        #expect(!FiioFrame.isGetRequest(Self.padded(Self.slotRequest) + [0x00]))
    }

    @Test func gateRejectsA19ByteFrame() {
        #expect(!FiioFrame.isGetRequest(Array(Self.padded(Self.slotRequest).dropLast())))
    }

    @Test func gateRejectsAnUnpaddedFrameWithAnExtraByte() {
        #expect(!FiioFrame.isGetRequest(Self.slotRequest + [0x00]))
        #expect(!FiioFrame.isGetRequest(Self.slotRequest + [0x01]))
    }

    @Test func gateRejectsANonZeroPaddingByte() {
        var first = Self.padded(Self.slotRequest)
        first[8] = 0x01
        #expect(!FiioFrame.isGetRequest(first))

        var last = Self.padded(Self.slotRequest)
        last[19] = 0x01
        #expect(!FiioFrame.isGetRequest(last))
    }

    @Test func gateRejectsAnyOtherFirstByte() {
        for frame in [Self.padded(Self.slotRequest), Self.slotRequest] {
            for firstByte in [UInt8(0x00), 0xBA, 0xBC, 0xFF] {
                var changed = frame
                changed[0] = firstByte
                #expect(!FiioFrame.isGetRequest(changed))
            }
        }
    }

    @Test func gateRejectsAnyOtherSecondByte() {
        for frame in [Self.padded(Self.slotRequest), Self.slotRequest] {
            var changed = frame
            changed[1] = 0x0A
            #expect(!FiioFrame.isGetRequest(changed))
        }
    }

    @Test func gateRejectsCommand0x19() {
        for frame in [Self.padded(Self.slotRequest), Self.slotRequest] {
            var changed = frame
            changed[4] = 0x19
            #expect(!FiioFrame.isGetRequest(changed))
        }
    }

    @Test func gateRejectsEveryCommandByteOutsideTheFourReadCommands() {
        for command in UInt8.min...UInt8.max where !(0x15...0x18).contains(command) {
            var changed = Self.slotRequest
            changed[4] = command
            #expect(!FiioFrame.isGetRequest(changed))
            #expect(!FiioFrame.isGetRequest(Self.padded(changed)))
        }
    }

    @Test func gateRejectsADataLengthTheRequestDoesNotHave() {
        // The slot request carries no data, so a slot frame with a data byte is not a read request.
        let slotWithData: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x16, 0x01, 0x03, 0x00, 0xEE]
        #expect(!FiioFrame.isGetRequest(slotWithData))
        #expect(!FiioFrame.isGetRequest(Self.padded(slotWithData)))

        // The filter request carries its index, so a filter frame without one is not a read request.
        let filterWithoutIndex: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x15, 0x00, 0x00, 0xEE]
        #expect(!FiioFrame.isGetRequest(filterWithoutIndex))
        #expect(!FiioFrame.isGetRequest(Self.padded(filterWithoutIndex)))
    }

    @Test func gateRejectsAMissingTerminator() {
        var changed = Self.slotRequest
        changed[7] = 0x00
        #expect(!FiioFrame.isGetRequest(changed))
        #expect(!FiioFrame.isGetRequest(Self.padded(changed)))
    }

    @Test func gateRejectsEmptyAndShortPayloads() {
        #expect(!FiioFrame.isGetRequest([]))
        #expect(!FiioFrame.isGetRequest(Array(Self.slotRequest.dropLast())))
    }

    // MARK: - Reply parsing (D-05, D-06)

    @Test func slotReplyParsesWithTheHeaderAtOffset0() throws {
        let reply = try #require(FiioFrame.replyFrame(from: Self.padded(Self.slotReply)))
        #expect(reply.command == 0x16)
        #expect(reply.headerOffset == 0)
        #expect(reply.slotID() == 3)
    }

    @Test func slotReplyParsesBehindALeadingReportIDByte() throws {
        let reply = try #require(FiioFrame.replyFrame(from: Self.withReportID(Self.padded(Self.slotReply))))
        #expect(reply.command == 0x16)
        #expect(reply.headerOffset == 1)
        #expect(reply.slotID() == 3)
    }

    @Test func replyBytesStartAtTheHeaderInBothLayouts() throws {
        let direct = try #require(FiioFrame.replyFrame(from: Self.padded(Self.slotReply)))
        let prefixed = try #require(FiioFrame.replyFrame(from: Self.withReportID(Self.padded(Self.slotReply))))
        #expect(direct.bytes == Self.padded(Self.slotReply))
        #expect(prefixed.bytes == direct.bytes)
    }

    @Test func emptyReportGivesNoFrame() {
        #expect(FiioFrame.replyFrame(from: []) == nil)
    }

    @Test func threeByteReportGivesNoFrame() {
        #expect(FiioFrame.replyFrame(from: [0xBB, 0x0B, 0x00]) == nil)
    }

    @Test func allZeroReportGivesNoFrame() {
        #expect(FiioFrame.replyFrame(from: [UInt8](repeating: 0x00, count: 20)) == nil)
    }

    @Test func headerAtAnyOtherOffsetGivesNoFrame() {
        #expect(FiioFrame.replyFrame(from: [0x00, 0x00] + Self.padded(Self.slotReply)) == nil)
    }

    @Test func slotIDIsNilForAReplyToAnotherCommand() throws {
        let countReply: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x18, 0x01, 0x05, 0x00, 0xEE]
        let reply = try #require(FiioFrame.replyFrame(from: Self.padded(countReply)))
        #expect(reply.slotID() == nil)
    }

    // MARK: - Hex

    @Test func hexIsTwoDigitLowercaseSeparatedBySingleSpaces() {
        #expect(FiioFrame.hex([0xBB, 0x0B, 0x00]) == "bb 0b 00")
        #expect(FiioFrame.hex([]) == "")
    }
}
