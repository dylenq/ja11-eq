import Testing
@testable import JA11Kit

/// Write-frame encoding and the send gate (CONTEXT D-01 to D-04). No transport of any kind is
/// created here, so these tests pass with the dongle unplugged and cannot send anything.
@Suite struct SetFrameTests {
    // MARK: - Reference frames (D-01)

    static let preGainMinus6: [UInt8] = [0xAA, 0x0A, 0x00, 0x00, 0x17, 0x02, 0xFF, 0xC4, 0x00, 0xEE]
    static let count5: [UInt8] = [0xAA, 0x0A, 0x00, 0x00, 0x18, 0x01, 0x05, 0x00, 0xEE]
    /// Filter 0: low shelf, 100 Hz, +6.0 dB, Q 0.70 — the reference frame of PROJECT.md.
    static let filter0: [UInt8] = [
        0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x00, 0x00, 0x3C, 0x00, 0x64, 0x00, 0x46, 0x01, 0x00, 0xEE,
    ]
    /// Filter 1: peak, 1000 Hz, -3.0 dB, Q 1.00.
    static let filter1: [UInt8] = [
        0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x01, 0xFF, 0xE2, 0x03, 0xE8, 0x00, 0x64, 0x00, 0x00, 0xEE,
    ]
    /// Filter 2: peak, 704 Hz, 0.0 dB, Q 1.20.
    static let filter2: [UInt8] = [
        0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x02, 0x00, 0x00, 0x02, 0xC0, 0x00, 0x78, 0x00, 0x00, 0xEE,
    ]
    /// Filter 3: peak, 7171 Hz, 0.0 dB, Q 1.50.
    static let filter3: [UInt8] = [
        0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x03, 0x00, 0x00, 0x1C, 0x03, 0x00, 0x96, 0x00, 0x00, 0xEE,
    ]
    /// Filter 4: high shelf, 3973 Hz, 0.0 dB, Q 0.40.
    static let filter4: [UInt8] = [
        0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x04, 0x00, 0x00, 0x0F, 0x85, 0x00, 0x28, 0x02, 0x00, 0xEE,
    ]
    static let saveSlot3: [UInt8] = [0xAA, 0x0A, 0x00, 0x00, 0x19, 0x01, 0x03, 0x00, 0xEE]
    static let selectSlot3: [UInt8] = [0xAA, 0x0A, 0x00, 0x00, 0x16, 0x01, 0x03, 0x00, 0xEE]

    static let pinned: [[UInt8]] = [
        preGainMinus6, count5, filter0, filter1, filter2, filter3, filter4, saveSlot3, selectSlot3,
    ].map(padded)

    /// The eight read requests Phase 1 pinned, before padding: slot, count, pre-gain, filters 0 to 4.
    static let getRequests: [[UInt8]] = [
        [0xBB, 0x0B, 0x00, 0x00, 0x16, 0x00, 0x00, 0xEE],
        [0xBB, 0x0B, 0x00, 0x00, 0x18, 0x00, 0x00, 0xEE],
        [0xBB, 0x0B, 0x00, 0x00, 0x17, 0x00, 0x00, 0xEE],
    ] + (0..<5).map { [0xBB, 0x0B, 0x00, 0x00, 0x15, 0x01, UInt8($0), 0x00, 0xEE] }

    /// A frame zero-padded to one full report.
    static func padded(_ frame: [UInt8]) -> [UInt8] {
        frame + [UInt8](repeating: 0x00, count: max(0, JA11.payloadLength - frame.count))
    }

    /// `frame` with one byte replaced.
    static func changing(_ frame: [UInt8], at index: Int, to value: UInt8) -> [UInt8] {
        var copy = frame
        copy[index] = value
        return copy
    }

    /// `frame` with two neighbouring bytes replaced by a 16-bit value, high byte first.
    static func changing(_ frame: [UInt8], at index: Int, toWord value: Int) -> [UInt8] {
        let bits = UInt16(truncatingIfNeeded: value)
        var copy = frame
        copy[index] = UInt8(bits >> 8)
        copy[index + 1] = UInt8(bits & 0xFF)
        return copy
    }

    static func band(
        index: Int = 0, typeID: UInt8 = 0, frequency: Int = 1000, gain: Double = 0.0, q: Double = 1.0
    ) -> Band {
        Band(index: index, typeID: typeID, frequency: frequency, gain: gain, q: q)
    }

    // MARK: - Builders give the reference frames

    @Test func preGainBuilderGivesTheReferenceFrame() {
        #expect(FiioFrame.setPreGain(-6.0) == Self.padded(Self.preGainMinus6))
    }

    @Test func filterCountBuilderGivesTheReferenceFrame() {
        #expect(FiioFrame.setFilterCount(5) == Self.padded(Self.count5))
    }

    @Test func filterBuilderGivesTheProjectReferenceFrameByteForByte() {
        let frame = FiioFrame.setFilter(Self.band(index: 0, typeID: 1, frequency: 100, gain: 6.0, q: 0.70))
        #expect(frame == Self.padded(Self.filter0))
        #expect(Array(frame[16...]) == [0x00, 0x00, 0x00, 0x00])
    }

    @Test func filterBuilderGivesTheOtherFourReferenceFrames() {
        #expect(FiioFrame.setFilter(Self.band(index: 1, typeID: 0, frequency: 1000, gain: -3.0, q: 1.00)) == Self.padded(Self.filter1))
        #expect(FiioFrame.setFilter(Self.band(index: 2, typeID: 0, frequency: 704, gain: 0.0, q: 1.20)) == Self.padded(Self.filter2))
        #expect(FiioFrame.setFilter(Self.band(index: 3, typeID: 0, frequency: 7171, gain: 0.0, q: 1.50)) == Self.padded(Self.filter3))
        #expect(FiioFrame.setFilter(Self.band(index: 4, typeID: 2, frequency: 3973, gain: 0.0, q: 0.40)) == Self.padded(Self.filter4))
    }

    @Test func saveBuilderGivesTheReferenceFrameForSlot3() {
        #expect(FiioFrame.saveToUser1() == Self.padded(Self.saveSlot3))
    }

    @Test func selectBuilderGivesTheReferenceFrameForSlot3() {
        #expect(FiioFrame.selectSlot(.user1) == Self.padded(Self.selectSlot3))
    }

    @Test func everyBuilderReturnsExactlyTwentyBytes() {
        #expect(Self.pinned.allSatisfy { $0.count == 20 })
        #expect(FiioFrame.setPreGain(0).count == 20)
        #expect(FiioFrame.setFilter(Self.band()).count == 20)
    }

    // MARK: - Negative values and limits on the wire

    @Test func preGainEncodesAsTwosComplementBigEndian() {
        #expect(Array(FiioFrame.setPreGain(-12.0)[6...7]) == [0xFF, 0x88])
        #expect(Array(FiioFrame.setPreGain(12.0)[6...7]) == [0x00, 0x78])
        #expect(Array(FiioFrame.setPreGain(-0.1)[6...7]) == [0xFF, 0xFF])
        #expect(Array(FiioFrame.setPreGain(-6.0)[6...7]) == [0xFF, 0xC4])
    }

    @Test func negativeFilterGainEncodesAsTwosComplementBigEndian() {
        #expect(Array(FiioFrame.setFilter(Self.band(gain: -3.0))[7...8]) == [0xFF, 0xE2])
        #expect(Array(FiioFrame.setFilter(Self.band(gain: -0.1))[7...8]) == [0xFF, 0xFF])
    }

    @Test func frequencyAndQLimitsEncodeAsUnsignedBigEndian() {
        #expect(Array(FiioFrame.setFilter(Self.band(frequency: 20_000))[9...10]) == [0x4E, 0x20])
        #expect(Array(FiioFrame.setFilter(Self.band(q: 10.0))[11...12]) == [0x03, 0xE8])
        #expect(Array(FiioFrame.setFilter(Self.band(q: 0.1))[11...12]) == [0x00, 0x0A])
    }

    // MARK: - Builders clamp

    @Test func preGainBuilderClamps() {
        #expect(FiioFrame.setPreGain(-20) == FiioFrame.setPreGain(-12))
        #expect(FiioFrame.setPreGain(20) == FiioFrame.setPreGain(12))
    }

    @Test func filterCountBuilderClamps() {
        #expect(FiioFrame.setFilterCount(9) == FiioFrame.setFilterCount(5))
        #expect(FiioFrame.setFilterCount(-1) == FiioFrame.setFilterCount(0))
    }

    @Test func filterBuilderClampsGainFrequencyAndQ() {
        let frame = FiioFrame.setFilter(Self.band(frequency: 5, gain: 40, q: 99))
        #expect(Array(frame[7...8]) == [0x00, 0x78])
        #expect(Array(frame[9...10]) == [0x00, 0x14])
        #expect(Array(frame[11...12]) == [0x03, 0xE8])
        #expect(FiioFrame.isSetRequest(frame))
    }

    // MARK: - The gate accepts (D-02)

    @Test func gateAcceptsAPresetSwitchToEachOfTheFiveSlots() {
        for slot in PresetSlot.allCases {
            #expect(FiioFrame.isSetRequest(FiioFrame.selectSlot(slot)))
            #expect(FiioFrame.isPermittedFrame(FiioFrame.selectSlot(slot)))
        }
    }

    @Test func gateAcceptsFilterCountsZeroToFive() {
        for count in 0...5 {
            #expect(FiioFrame.isPermittedFrame(FiioFrame.setFilterCount(count)))
        }
    }

    @Test func gateAcceptsEveryFilterIndexWithEveryType() {
        for index in 0..<5 {
            for typeID in UInt8(0)...2 {
                #expect(FiioFrame.isPermittedFrame(FiioFrame.setFilter(Self.band(index: index, typeID: typeID))))
            }
        }
    }

    @Test func gateAcceptsPreGainAtBothLimitsAndTheSave() {
        #expect(FiioFrame.isPermittedFrame(FiioFrame.setPreGain(-12)))
        #expect(FiioFrame.isPermittedFrame(FiioFrame.setPreGain(12)))
        #expect(FiioFrame.isPermittedFrame(FiioFrame.saveToUser1()))
    }

    @Test func gateAcceptsEveryPinnedWriteFrame() {
        #expect(Self.pinned.allSatisfy(FiioFrame.isSetRequest))
        #expect(Self.pinned.allSatisfy(FiioFrame.isPermittedFrame))
    }

    @Test func gateStillAcceptsTheEightReadRequestsInBothForms() {
        #expect(Self.getRequests.count == 8)
        for request in Self.getRequests {
            #expect(FiioFrame.isPermittedFrame(request))
            #expect(FiioFrame.isPermittedFrame(Self.padded(request)))
        }
    }

    @Test func aReadRequestIsNotAWriteFrameAndAWriteFrameIsNotAReadRequest() {
        for request in Self.getRequests {
            #expect(!FiioFrame.isSetRequest(request))
            #expect(!FiioFrame.isSetRequest(Self.padded(request)))
        }
        for frame in Self.pinned {
            #expect(!FiioFrame.isGetRequest(frame))
        }
    }

    // MARK: - The gate refuses (D-02, D-03, D-04)

    @Test func gateRefusesASaveToAnySlotButThree() {
        let save = FiioFrame.saveToUser1()
        for slot: UInt8 in [0, 1, 2, 4, 5, 255] {
            #expect(!FiioFrame.isPermittedFrame(Self.changing(save, at: 6, to: slot)))
        }
        #expect(FiioFrame.isPermittedFrame(Self.changing(save, at: 6, to: 3)))
    }

    @Test func gateRefusesAPresetSwitchOutsideZeroToFour() {
        let select = FiioFrame.selectSlot(.user1)
        #expect(!FiioFrame.isPermittedFrame(Self.changing(select, at: 6, to: 5)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(select, at: 6, to: 255)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(select, at: 6, to: 0)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(select, at: 6, to: 4)))
    }

    @Test func gateRefusesAFilterCountAboveFive() {
        let count = FiioFrame.setFilterCount(5)
        #expect(!FiioFrame.isPermittedFrame(Self.changing(count, at: 6, to: 6)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(count, at: 6, to: 255)))
    }

    @Test func gateRefusesAFilterIndexOutsideZeroToFour() {
        let filter = Self.padded(Self.filter0)
        #expect(!FiioFrame.isPermittedFrame(Self.changing(filter, at: 6, to: 5)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(filter, at: 6, to: 255)))
    }

    @Test func gateRefusesAnUnknownFilterType() {
        #expect(!FiioFrame.isPermittedFrame(Self.changing(Self.padded(Self.filter0), at: 13, to: 3)))
    }

    @Test func gateRefusesAFilterGainOneStepOutsideTheLimits() {
        let filter = Self.padded(Self.filter0)
        #expect(!FiioFrame.isPermittedFrame(Self.changing(filter, at: 7, toWord: 121)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(filter, at: 7, toWord: -121)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(filter, at: 7, toWord: 120)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(filter, at: 7, toWord: -120)))
    }

    @Test func gateRefusesAFilterFrequencyOneStepOutsideTheLimits() {
        let filter = Self.padded(Self.filter0)
        #expect(!FiioFrame.isPermittedFrame(Self.changing(filter, at: 9, toWord: 19)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(filter, at: 9, toWord: 20_001)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(filter, at: 9, toWord: 20)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(filter, at: 9, toWord: 20_000)))
    }

    @Test func gateRefusesAFilterQOneStepOutsideTheLimits() {
        let filter = Self.padded(Self.filter0)
        #expect(!FiioFrame.isPermittedFrame(Self.changing(filter, at: 11, toWord: 9)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(filter, at: 11, toWord: 1001)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(filter, at: 11, toWord: 10)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(filter, at: 11, toWord: 1000)))
    }

    @Test func gateRefusesAPreGainOneStepOutsideTheLimits() {
        let preGain = FiioFrame.setPreGain(0)
        #expect(!FiioFrame.isPermittedFrame(Self.changing(preGain, at: 6, toWord: 121)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(preGain, at: 6, toWord: -121)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(preGain, at: 6, toWord: 120)))
        #expect(FiioFrame.isPermittedFrame(Self.changing(preGain, at: 6, toWord: -120)))
    }

    @Test func gateAcceptsNoCommandByteOutsideTheFiveWriteCommands() {
        // An otherwise valid frame with one data byte (3), under every possible command byte.
        let base = FiioFrame.selectSlot(.user1)
        var accepted: [Int] = []
        for value in 0...255 {
            let frame = Self.changing(base, at: 4, to: UInt8(value))
            if FiioFrame.isPermittedFrame(frame) { accepted.append(value) }
            if !(0x15...0x19).contains(value) {
                #expect(!FiioFrame.isSetRequest(frame), "command byte \(value) was accepted")
                #expect(!FiioFrame.isPermittedFrame(frame), "command byte \(value) was accepted")
            }
        }
        // Of the five, only the three that carry one data byte fit this frame.
        #expect(accepted == [0x16, 0x18, 0x19])
    }

    @Test func gateRefusesALengthByteOneOffForEachCommand() {
        let frames = [
            FiioFrame.setFilter(Self.band()),
            FiioFrame.selectSlot(.user1),
            FiioFrame.setPreGain(0),
            FiioFrame.setFilterCount(5),
            FiioFrame.saveToUser1(),
        ]
        for frame in frames {
            #expect(FiioFrame.isPermittedFrame(frame))
            #expect(!FiioFrame.isPermittedFrame(Self.changing(frame, at: 5, to: frame[5] + 1)))
            #expect(!FiioFrame.isPermittedFrame(Self.changing(frame, at: 5, to: frame[5] - 1)))
        }
    }

    @Test func gateRefusesAWriteFrameThatIsNotExactlyTwentyBytes() {
        // Cut to its unpadded length, one byte too long, one byte too short, and empty.
        #expect(!FiioFrame.isPermittedFrame(Self.saveSlot3))
        #expect(!FiioFrame.isPermittedFrame(Self.filter0))
        #expect(!FiioFrame.isPermittedFrame(Self.padded(Self.saveSlot3) + [0x00]))
        #expect(!FiioFrame.isPermittedFrame(Array(Self.padded(Self.saveSlot3).dropLast())))
        #expect(!FiioFrame.isPermittedFrame([]))
        #expect(!FiioFrame.isSetRequest([]))
    }

    @Test func gateRefusesANonZeroPaddingByte() {
        let select = FiioFrame.selectSlot(.user1)
        for index in 9..<20 {
            #expect(!FiioFrame.isPermittedFrame(Self.changing(select, at: index, to: 0x01)))
        }
    }

    @Test func gateRefusesANonZeroByteBeforeTheEndByte() {
        #expect(!FiioFrame.isPermittedFrame(Self.changing(FiioFrame.selectSlot(.user1), at: 7, to: 0x5A)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(Self.padded(Self.filter0), at: 14, to: 0x5A)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(FiioFrame.setPreGain(-6), at: 8, to: 0x5A)))
    }

    @Test func gateRefusesAFrameWithoutItsEndByte() {
        #expect(!FiioFrame.isPermittedFrame(Self.changing(FiioFrame.selectSlot(.user1), at: 8, to: 0x00)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(Self.padded(Self.filter0), at: 15, to: 0x00)))
    }

    @Test func gateRefusesAnyOtherHeader() {
        let select = FiioFrame.selectSlot(.user1)
        #expect(!FiioFrame.isPermittedFrame(Self.changing(select, at: 1, to: 0x0B)))   // AA 0B
        #expect(!FiioFrame.isPermittedFrame(Self.changing(select, at: 0, to: 0xBB)))   // BB 0A
        #expect(!FiioFrame.isPermittedFrame(Self.changing(select, at: 2, to: 0x01)))
        #expect(!FiioFrame.isPermittedFrame(Self.changing(select, at: 3, to: 0x01)))
    }

    @Test func gateRefusesASaveDressedAsAReadRequest() {
        let dressed: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x19, 0x01, 0x03, 0x00, 0xEE]
        let bare: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x19, 0x00, 0x00, 0xEE]
        for frame in [dressed, bare] {
            #expect(!FiioFrame.isPermittedFrame(frame))
            #expect(!FiioFrame.isPermittedFrame(Self.padded(frame)))
        }
    }
}
