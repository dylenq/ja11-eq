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

    /// The filter-count, pre-gain and filter-3 read requests before padding.
    static let countRequest: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x18, 0x00, 0x00, 0xEE]
    static let preGainRequest: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x17, 0x00, 0x00, 0xEE]
    static let filter3Request: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x15, 0x01, 0x03, 0x00, 0xEE]

    /// A reply saying five filters are in use.
    static let countReply: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x18, 0x01, 0x05, 0x00, 0xEE]
    /// Pre-gain replies for -6.0 dB, +3.0 dB and 0.0 dB.
    static let preGainMinus6Reply: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x17, 0x02, 0xFF, 0xC4, 0x00, 0xEE]
    static let preGainPlus3Reply: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x17, 0x02, 0x00, 0x1E, 0x00, 0xEE]
    static let preGainZeroReply: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x17, 0x02, 0x00, 0x00, 0x00, 0xEE]
    /// Filter 0: low shelf, 100 Hz, +6.0 dB, Q 0.70.
    static let lowShelfReply: [UInt8] = [
        0xBB, 0x0B, 0x00, 0x00, 0x15, 0x08, 0x00, 0x00, 0x3C, 0x00, 0x64, 0x00, 0x46, 0x01, 0x00, 0xEE,
    ]
    /// Filter 2: peak, 1000 Hz, -6.0 dB, Q 1.41.
    static let negativePeakReply: [UInt8] = [
        0xBB, 0x0B, 0x00, 0x00, 0x15, 0x08, 0x02, 0xFF, 0xC4, 0x03, 0xE8, 0x00, 0x8D, 0x00, 0x00, 0xEE,
    ]

    /// The low-shelf filter reply with another number in its type byte.
    static func filterReply(type: UInt8) -> [UInt8] {
        var reply = lowShelfReply
        reply[13] = type
        return reply
    }

    /// The reply located in a report that holds `frame` zero-padded to 20 bytes.
    static func parsed(_ frame: [UInt8]) throws -> FiioReplyFrame {
        try #require(FiioFrame.replyFrame(from: padded(frame)))
    }

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
        #expect(try Self.parsed(Self.countReply).slotID() == nil)
    }

    // MARK: - Every read request (D-03)

    /// Command, request data and the reference frame before padding.
    static let referenceRequests: [(command: JA11Command, data: [UInt8], frame: [UInt8])] = [
        (.presetSlot, [], slotRequest),
        (.filterCount, [], countRequest),
        (.preGain, [], preGainRequest),
        (.filter, [3], filter3Request),
    ]

    @Test func everyUnpaddedRequestIsExactlyItsReferenceFrame() {
        for request in Self.referenceRequests {
            #expect(FiioFrame.getRequest(request.command, data: request.data, form: .unpadded) == request.frame)
        }
    }

    @Test func everyPaddedRequestIsItsReferenceFrameFollowedByZeroBytesToTwenty() {
        for request in Self.referenceRequests {
            let frame = FiioFrame.getRequest(request.command, data: request.data, form: .padded)
            #expect(frame == Self.padded(request.frame))
            #expect(frame.count == 20)
        }
    }

    @Test func gateAcceptsAllEightReferenceRequests() {
        for request in Self.referenceRequests {
            #expect(FiioFrame.isGetRequest(request.frame))
            #expect(FiioFrame.isGetRequest(Self.padded(request.frame)))
        }
    }

    @Test func theOnlyCommandsAreTheFourReadCommands() {
        #expect(JA11Command.allCases.map(\.rawValue).sorted() == [0x15, 0x16, 0x17, 0x18])
    }

    // MARK: - Reply decoding (D-05)

    @Test func countReplyDecodesTheFilterCount() throws {
        #expect(try Self.parsed(Self.countReply).filterCount() == 5)
    }

    @Test func preGainReplyDecodesNegativeGain() throws {
        #expect(try Self.parsed(Self.preGainMinus6Reply).preGain() == -6.0)
    }

    @Test func preGainReplyDecodesPositiveGain() throws {
        #expect(try Self.parsed(Self.preGainPlus3Reply).preGain() == 3.0)
    }

    @Test func preGainReplyDecodesZero() throws {
        #expect(try Self.parsed(Self.preGainZeroReply).preGain() == 0.0)
    }

    @Test func filterReplyDecodesTheReferenceLowShelf() throws {
        let band = try #require(try Self.parsed(Self.lowShelfReply).band())
        #expect(band == Band(index: 0, typeID: 1, frequency: 100, gain: 6.0, q: 0.70))
        #expect(band.type == .lowShelf)
    }

    @Test func filterReplyDecodesNegativeGain() throws {
        let band = try #require(try Self.parsed(Self.negativePeakReply).band())
        #expect(band == Band(index: 2, typeID: 0, frequency: 1000, gain: -6.0, q: 1.41))
        #expect(band.type == .peak)
    }

    @Test func filterTypeByte2IsHighShelf() throws {
        let band = try #require(try Self.parsed(Self.filterReply(type: 2)).band())
        #expect(band.typeID == 2)
        #expect(band.type == .highShelf)
    }

    @Test func unknownFilterTypeByteStaysVisibleAsItsNumber() throws {
        let band = try #require(try Self.parsed(Self.filterReply(type: 7)).band())
        #expect(band.typeID == 7)
        #expect(band.type == nil)
    }

    @Test func aQOfZeroIsNotReplacedByADefault() throws {
        var reply = Self.lowShelfReply
        reply[11] = 0x00
        reply[12] = 0x00
        #expect(try Self.parsed(reply).band()?.q == 0.0)
    }

    // MARK: - Leading report-ID byte (D-06)

    @Test func everyReplyDecodesTheSameBehindALeadingReportIDByte() throws {
        func prefixed(_ frame: [UInt8]) throws -> FiioReplyFrame {
            let reply = try #require(FiioFrame.replyFrame(from: Self.withReportID(Self.padded(frame))))
            #expect(reply.headerOffset == 1)
            return reply
        }
        #expect(try prefixed(Self.slotReply).slotID() == 3)
        #expect(try prefixed(Self.countReply).filterCount() == 5)
        #expect(try prefixed(Self.preGainMinus6Reply).preGain() == -6.0)
        #expect(try prefixed(Self.preGainPlus3Reply).preGain() == 3.0)
        #expect(try prefixed(Self.preGainZeroReply).preGain() == 0.0)
        #expect(try prefixed(Self.lowShelfReply).band() == Band(index: 0, typeID: 1, frequency: 100, gain: 6.0, q: 0.70))
        #expect(try prefixed(Self.negativePeakReply).band() == Band(index: 2, typeID: 0, frequency: 1000, gain: -6.0, q: 1.41))
        #expect(try prefixed(Self.filterReply(type: 2)).band()?.type == .highShelf)
        #expect(try prefixed(Self.filterReply(type: 7)).band()?.typeID == 7)
    }

    // MARK: - Short and mismatched replies

    @Test func preGainIsNilWhenTheReplyIsCutToSevenBytes() throws {
        let reply = try #require(FiioFrame.replyFrame(from: Array(Self.preGainMinus6Reply.prefix(7))))
        #expect(reply.preGain() == nil)
    }

    @Test func preGainDecodesFromExactlyEightBytes() throws {
        let reply = try #require(FiioFrame.replyFrame(from: Array(Self.preGainMinus6Reply.prefix(8))))
        #expect(reply.preGain() == -6.0)
    }

    @Test func bandIsNilWhenTheReplyIsCutToThirteenBytes() throws {
        let reply = try #require(FiioFrame.replyFrame(from: Array(Self.lowShelfReply.prefix(13))))
        #expect(reply.band() == nil)
    }

    @Test func bandDecodesFromExactlyFourteenBytes() throws {
        let reply = try #require(FiioFrame.replyFrame(from: Array(Self.lowShelfReply.prefix(14))))
        #expect(reply.band() == Band(index: 0, typeID: 1, frequency: 100, gain: 6.0, q: 0.70))
    }

    @Test func filterCountIsNilForASlotReply() throws {
        #expect(try Self.parsed(Self.slotReply).filterCount() == nil)
    }

    @Test func decodersAreNilForAReplyToAnotherCommand() throws {
        #expect(try Self.parsed(Self.countReply).preGain() == nil)
        #expect(try Self.parsed(Self.countReply).band() == nil)
        #expect(try Self.parsed(Self.lowShelfReply).preGain() == nil)
        #expect(try Self.parsed(Self.preGainMinus6Reply).filterCount() == nil)
    }

    // MARK: - Big-endian numbers (D-05)

    @Test func int16BEIsTwosComplement() {
        #expect(FiioFrame.int16BE(0xFF, 0xC4) == -60)
        #expect(FiioFrame.int16BE(0x00, 0x3C) == 60)
    }

    @Test func uint16BEIsUnsigned() {
        #expect(FiioFrame.uint16BE(0x03, 0xE8) == 1000)
        #expect(FiioFrame.uint16BE(0xFF, 0xC4) == 65476)
    }

    // MARK: - Model (D-02, D-13)

    @Test func presetSlotRawValuesMatchTheSlotIDs() {
        #expect(PresetSlot.vocal.rawValue == JA11SlotID.vocal)
        #expect(PresetSlot.classic.rawValue == JA11SlotID.classic)
        #expect(PresetSlot.bass.rawValue == JA11SlotID.bass)
        #expect(PresetSlot.user1.rawValue == JA11SlotID.user1)
        #expect(PresetSlot.off.rawValue == JA11SlotID.off)
        #expect(PresetSlot.allCases.count == 5)
    }

    @Test func presetSlotsAndFilterTypesHaveTheirDisplayNames() {
        #expect(PresetSlot.allCases.map(\.displayName) == ["Vocal", "Classic", "Bass", "USER1", "Off"])
        #expect(FilterType.allCases.map(\.displayName) == ["peak", "low-shelf", "high-shelf"])
    }

    @Test func slotAndTypeLookUpTheirTables() {
        #expect(EQState(slotID: 3, preGain: 0.0, bands: []).slot == .user1)
        #expect(EQState(slotID: 9, preGain: 0.0, bands: []).slot == nil)
        #expect(Band(index: 0, typeID: 2, frequency: 100, gain: 0.0, q: 1.0).type == .highShelf)
        #expect(Band(index: 0, typeID: 7, frequency: 100, gain: 0.0, q: 1.0).type == nil)
    }

    @Test func reportLinesMatchTheProbeOutputContract() {
        let state = EQState(slotID: 3, preGain: -6.0, bands: [
            Band(index: 0, typeID: 1, frequency: 100, gain: 6.0, q: 0.70),
            Band(index: 1, typeID: 0, frequency: 1000, gain: -3.5, q: 1.41),
        ])
        #expect(state.reportLines() == [
            "slot: 3 (USER1)",
            "pre-gain: -6.0 dB",
            "filters: 2",
            "filter 0: low-shelf 100 Hz +6.0 dB Q 0.70",
            "filter 1: peak 1000 Hz -3.5 dB Q 1.41",
        ])
    }

    @Test func reportLinesKeepAnUnknownSlotVisibleAndShowNoFilters() {
        #expect(EQState(slotID: 9, preGain: 0.0, bands: []).reportLines() == [
            "slot: 9 (unknown)",
            "pre-gain: +0.0 dB",
            "filters: 0",
        ])
    }

    @Test func reportLinesRenderAnUnknownFilterTypeAsItsNumber() {
        let state = EQState(slotID: 3, preGain: 0.0, bands: [Band(index: 0, typeID: 7, frequency: 100, gain: 0.0, q: 1.0)])
        #expect(state.reportLines().last == "filter 0: type-7 100 Hz +0.0 dB Q 1.00")
    }

    // MARK: - Hex

    @Test func hexIsTwoDigitLowercaseSeparatedBySingleSpaces() {
        #expect(FiioFrame.hex([0xBB, 0x0B, 0x00]) == "bb 0b 00")
        #expect(FiioFrame.hex([]) == "")
    }
}
