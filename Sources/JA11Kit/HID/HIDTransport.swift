import Foundation
import IOKit
import IOKit.hid

/// What can go wrong between this process and the JA11's HID interface.
public enum HIDTransportError: Error, Equatable, Sendable, CustomStringConvertible {
    /// macOS refused the open with a not-permitted or not-privileged result.
    case accessDenied(code: Int32)
    /// The open failed for any other reason.
    case openFailed(code: Int32)
    /// The output report was not accepted.
    case sendFailed(code: Int32)
    /// No JA11 is held open.
    case notConnected
    /// The payload is not one of the frames the transport is allowed to send: a read request, or a
    /// write frame that `FiioFrame.isPermittedFrame` accepts.
    case refusedFrame

    /// Classifies the result of an open call: a refusal by macOS gets its own case.
    public static func forOpenResult(_ code: Int32) -> HIDTransportError {
        switch code {
        case kIOReturnNotPermitted, kIOReturnNotPrivileged: .accessDenied(code: code)
        default: .openFailed(code: code)
        }
    }

    public var description: String {
        switch self {
        case .accessDenied(let code):
            "macOS refused access to the JA11 (IOKit \(Self.hex(code))). Enable this program under System Settings → Privacy & Security → Input Monitoring, then run it again. If you started it from a terminal, the entry to enable is that terminal app."
        case .openFailed(let code):
            "Could not open the JA11 (IOKit \(Self.hex(code)))."
        case .sendFailed(let code):
            "Could not send to the JA11 (IOKit \(Self.hex(code)))."
        case .notConnected:
            "The JA11 is not connected."
        case .refusedFrame:
            "Refused to send a frame that is not a permitted JA11 request."
        }
    }

    /// An IOKit result as `0x` plus eight uppercase hex digits.
    private static func hex(_ code: Int32) -> String {
        let digits = String(UInt32(bitPattern: code), radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: max(0, 8 - digits.count)) + digits
    }
}

/// A change in the link to the JA11.
public enum ConnectionEvent: Sendable, Equatable {
    case connected
    case disconnected
    case openFailed(HIDTransportError)
}

/// The seam between the device logic and the HID system, so the logic can be tested without hardware.
public protocol ReportTransport: AnyObject, Sendable {
    /// Link changes, in the order they happened.
    var events: AsyncStream<ConnectionEvent> { get }
    /// Input reports on the EQ command channel, bytes exactly as macOS delivered them.
    var reports: AsyncStream<[UInt8]> { get }
    /// Starts looking for the JA11. Later calls do nothing.
    func start()
    /// Sends one permitted frame — a read request or a write frame that passes
    /// `FiioFrame.isPermittedFrame` — as an output report on the EQ command channel.
    func send(_ payload: [UInt8]) throws
}

/// The JA11's HID interface through IOKit: found by vendor and product ID, opened without taking
/// it away from macOS, followed across unplug and replug.
///
/// One manager lives for the life of the process, so a replugged dongle arrives through the same
/// callbacks with nothing recreated. The held device is read and written only on `queue`, which is
/// what makes the class safe to share.
public final class HIDTransport: ReportTransport, @unchecked Sendable {
    public let events: AsyncStream<ConnectionEvent>
    public let reports: AsyncStream<[UInt8]>

    private let eventsContinuation: AsyncStream<ConnectionEvent>.Continuation
    private let reportsContinuation: AsyncStream<[UInt8]>.Continuation
    private let manager: IOHIDManager
    private let queue = DispatchQueue(label: "ja11kit.hid-transport")

    /// The opened JA11, or nil. Touched only on `queue`.
    private var device: IOHIDDevice?
    /// Whether `start()` has run. Touched only on `queue`.
    private var started = false

    public init() {
        // Streams are created here, so anything raised before a consumer iterates is buffered.
        (events, eventsContinuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
        (reports, reportsContinuation) = AsyncStream.makeStream(of: [UInt8].self)
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func start() {
        let firstCall = queue.sync { () -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard firstCall else { return }

        // Both keys, always: the manager must never see any other HID device.
        let matching: [String: Int] = [
            kIOHIDVendorIDKey: JA11.vendorID,
            kIOHIDProductIDKey: JA11.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // C callbacks cannot capture, so `self` travels as the context pointer. The manager lives
        // as long as this object, and neither is torn down before the process ends.
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, _, _, reportID, report, reportLength in
            guard let context else { return }
            Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
                .inputReport(reportID: reportID, report: report, length: reportLength)
        }, context)

        // Observed with the JA11 on macOS 27: while only the device is opened, the manager-level
        // input-report callback never fires; it fires once the manager itself is opened. So the
        // manager is opened too, non-exclusively like the device. It comes before activation
        // because it attaches the report callback to a dongle that is already plugged in, and
        // IOHIDDevice.h wants that done before a device is activated. Its result is not used:
        // the matching callback opens each device and classifies that result, which also covers
        // a dongle plugged in later.
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // Every registration has to precede activation.
        IOHIDManagerSetDispatchQueue(manager, queue)
        IOHIDManagerActivate(manager)
    }

    public func send(_ payload: [UInt8]) throws {
        // The gate: an explicit allow-list. Read requests, and write frames for USER1 with values
        // inside the device limits; everything else stops here, before IOKit.
        guard FiioFrame.isPermittedFrame(payload) else { throw HIDTransportError.refusedFrame }

        // macOS expects the report-ID byte first for a device with numbered reports.
        let buffer = [JA11.reportID] + payload
        let result: IOReturn? = queue.sync {
            guard let device else { return nil }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(JA11.reportID), buffer, buffer.count)
        }

        guard let result else { throw HIDTransportError.notConnected }
        guard result == kIOReturnSuccess else { throw HIDTransportError.sendFailed(code: result) }
    }

    // MARK: - Callbacks (all on `queue`)

    private func deviceMatched(_ candidate: IOHIDDevice) {
        guard device == nil else { return }

        // Non-exclusive open: the dongle's buttons keep reaching macOS. This per-device call is
        // what yields a result to classify, for a dongle present at start and one plugged in later.
        let result = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            eventsContinuation.yield(.openFailed(HIDTransportError.forOpenResult(result)))
            return
        }
        device = candidate
        eventsContinuation.yield(.connected)
    }

    private func deviceRemoved(_ removed: IOHIDDevice) {
        guard let held = device, CFEqual(held, removed) else { return }
        device = nil
        eventsContinuation.yield(.disconnected)
    }

    private func inputReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        // Other reports, such as the buttons report, are none of this transport's business.
        guard reportID == UInt32(JA11.reportID), length >= 0 else { return }
        reportsContinuation.yield(Array(UnsafeBufferPointer(start: report, count: length)))
    }
}
