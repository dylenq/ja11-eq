import CoreAudio
import Foundation

/// Where the app learns the DAC's output sample rate. The first value is the current one.
public protocol OutputSampleRateSource: Sendable {
    func rates() -> AsyncStream<Double?>
}

/// Sample rate as text such as `352.8 kHz`, independent of the user's locale.
public enum SampleRateFormat {
    public static func text(_ hertz: Double?) -> String {
        guard let hertz, hertz.isFinite, hertz > 0 else { return missingValueText }
        // Tenths of a kHz, rounded half away from zero.
        let tenths = Int((hertz / 100).rounded(.toNearestOrAwayFromZero))
        let whole = tenths / 10
        let fraction = tenths % 10
        return fraction == 0 ? "\(whole) kHz" : "\(whole).\(fraction) kHz"
    }
}

/// Reads the nominal sample rate of the audio device named `JadeAudio JA11`. Reads only: no
/// CoreAudio property is ever set.
public struct CoreAudioSampleRate: OutputSampleRateSource {
    public static let deviceName = "JadeAudio JA11"

    public init() {}

    public func currentRate() -> Double? {
        guard let id = Self.findDevice() else { return nil }
        return Self.rate(of: id)
    }

    public func rates() -> AsyncStream<Double?> {
        let (stream, continuation) = AsyncStream.makeStream(of: Double?.self, bufferingPolicy: .bufferingNewest(8))
        let watcher = Watcher(continuation: continuation)
        continuation.onTermination = { _ in watcher.stop() }
        watcher.start()
        return stream
    }

    // MARK: - CoreAudio reads

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func findDevice() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return nil }
        return ids.first { name(of: $0) == deviceName }
    }

    static func name(of id: AudioObjectID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func rate(of id: AudioObjectID) -> Double? {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr,
              value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Owns the listeners behind one `rates()` stream. All state is touched under the queue.
    private final class Watcher: @unchecked Sendable {
        private let continuation: AsyncStream<Double?>.Continuation
        private let queue = DispatchQueue(label: "ja11eq.coreaudio-rate")
        private var deviceID: AudioObjectID?
        private var lastRate: Double?
        private var stopped = false
        private var block: AudioObjectPropertyListenerBlock?

        init(continuation: AsyncStream<Double?>.Continuation) {
            self.continuation = continuation
        }

        func start() {
            queue.async { [self] in
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
                self.block = block
                var devices = CoreAudioSampleRate.address(kAudioHardwarePropertyDevices)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, queue, block)
                bind(to: CoreAudioSampleRate.findDevice())
                lastRate = deviceID.flatMap(CoreAudioSampleRate.rate(of:))
                continuation.yield(lastRate)
            }
        }

        func stop() {
            queue.async { [self] in
                stopped = true
                guard let block else { return }
                var devices = CoreAudioSampleRate.address(kAudioHardwarePropertyDevices)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, queue, block)
                bind(to: nil)
                self.block = nil
            }
        }

        private func refresh() {
            guard !stopped else { return }
            let found = CoreAudioSampleRate.findDevice()
            if found != deviceID { bind(to: found) }
            let rate = deviceID.flatMap(CoreAudioSampleRate.rate(of:))
            if rate != lastRate {
                lastRate = rate
                continuation.yield(rate)
            }
        }

        /// Moves the rate listener to another device object (or removes it).
        private func bind(to id: AudioObjectID?) {
            guard let block else { deviceID = id; return }
            var rateAddr = CoreAudioSampleRate.address(kAudioDevicePropertyNominalSampleRate)
            if let old = deviceID {
                AudioObjectRemovePropertyListenerBlock(old, &rateAddr, queue, block)
            }
            deviceID = id
            if let id, !stopped {
                AudioObjectAddPropertyListenerBlock(id, &rateAddr, queue, block)
            }
        }
    }
}
