import Foundation

struct AudioMixChannel: Codable, Equatable, Sendable {
    var gain: Float = 1
    var muted = false
    var solo = false
}

struct AudioMixConfiguration: Codable, Equatable, Sendable {
    var inputs: [String: AudioMixChannel] = [:]
    var outputs: [String: AudioMixChannel] = [:]
    func validationError(availableInputs: Set<String>, availableOutputs: Set<String>, feedbackSensitiveUIDs: Set<String> = []) -> String? {
        if inputs.isEmpty { return "请选择至少一个混音输入。" }
        if outputs.isEmpty { return "请选择至少一个混音输出。" }
        if !Set(inputs.keys).intersection(outputs.keys).intersection(feedbackSensitiveUIDs).isEmpty { return "同一虚拟音频设备不能同时作为混音输入和输出，以免形成音频回路。" }
        if !Set(inputs.keys).isSubset(of: availableInputs) { return "选中的输入设备已断开，请重新选择。" }
        if !Set(outputs.keys).isSubset(of: availableOutputs) { return "选中的输出设备已断开，请重新选择。" }
        return nil
    }
    static func remoteUID(_ remote: SupportedRemoteID) -> String { "remote:" + remote.rawValue }
}

/// Bounded FIFO: independent queues let outputs run on different hardware clocks.
/// Overflow drops the oldest audio instead of accumulating delay indefinitely.
struct AudioSampleRing {
    private var storage: [Float]
    private var readIndex = 0
    private(set) var count = 0
    init(capacity: Int = 12_000) { storage = Array(repeating: 0, count: max(1, capacity)) }
    mutating func append(_ samples: [Float]) {
        for sample in samples {
            if count == storage.count { readIndex = (readIndex + 1) % storage.count; count -= 1 }
            storage[(readIndex + count) % storage.count] = sample.isFinite ? sample : 0
            count += 1
        }
    }
    mutating func pop() -> Float {
        guard count > 0 else { return 0 }
        let value = storage[readIndex]; readIndex = (readIndex + 1) % storage.count; count -= 1
        return value
    }
}

/// Streaming linear resampler preserves fractional position between BLE/capture packets.
struct AudioStreamingResampler {
    private var previous: Float?
    private var position: Double = 0
    private var lastRate: Double?
    mutating func convert(_ samples: [Float], from rate: Double, to target: Double = 48_000) -> [Float] {
        guard !samples.isEmpty, rate.isFinite, rate > 0, target > 0 else { return [] }
        if lastRate != rate { previous = nil; position = 0; lastRate = rate }
        if rate == target { return samples }
        let source = previous.map { [$0] + samples } ?? samples
        var result: [Float] = []
        let step = rate / target
        while position < Double(source.count - 1) {
            let index = Int(position); let fraction = Float(position - Double(index))
            result.append(source[index] + (source[index + 1] - source[index]) * fraction)
            position += step
        }
        position -= Double(source.count - 1); previous = source.last
        return result
    }
}
