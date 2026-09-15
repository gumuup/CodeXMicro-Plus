import CoreAudio
import Foundation

struct SystemAudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int
    let transport: UInt32
    // Aggregates may include speakers, so they also require explicit monitoring.
    var isVirtualMixDestination: Bool {
        transport == kAudioDeviceTransportTypeVirtual
            || name.localizedCaseInsensitiveContains("BlackHole")
            || name.localizedCaseInsensitiveContains("vRemote")
    }
    var isLoopback: Bool {
        transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate
            || name.localizedCaseInsensitiveContains("BlackHole") || name.localizedCaseInsensitiveContains("vRemote")
    }
    var kind: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "内置"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "蓝牙"
        case kAudioDeviceTransportTypeVirtual: "虚拟音频"
        case kAudioDeviceTransportTypeAggregate: "聚合设备"
        default: "音频设备"
        }
    }
}

enum SystemAudioDevices {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(_ selector: AudioObjectPropertySelector, input: Bool? = nil, element: UInt32 = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: input.map { $0 ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput } ?? kAudioObjectPropertyScopeGlobal, mElement: element)
    }
    static func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var property = address; var value = initial; var size = UInt32(MemoryLayout<T>.size)
        let result = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0) }
        return result == noErr ? value : nil
    }
    static func write<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, value: T) throws {
        var property = address; var copy = value
        let result = withUnsafePointer(to: &copy) { AudioObjectSetPropertyData(object, &property, 0, nil, UInt32(MemoryLayout<T>.size), $0) }
        guard result == noErr else { throw AudioSettingsError.message("macOS 无法更改音频设置（\(result)）") }
    }
    static func text(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        let result: Unmanaged<CFString>?? = read(object, address(selector), initial: Optional<Unmanaged<CFString>>.none)
        return result.flatMap { $0 }.map { $0.takeUnretainedValue() as String }
    }
    static func devices() -> [SystemAudioDevice] {
        var property = address(kAudioHardwarePropertyDevices); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard read(id, address(kAudioDevicePropertyIsHidden), initial: UInt32(0)) != 1 else { return nil }
            guard let uid = text(id, kAudioDevicePropertyDeviceUID), let name = text(id, kAudioObjectPropertyName) else { return nil }
            // AVCapture creates temporary internal aggregates while opening Bluetooth inputs.
            guard !name.hasPrefix("CADefaultDeviceAggregate-") else { return nil }
            return SystemAudioDevice(id: id, uid: uid, name: name, inputChannels: channels(id, input: true), outputChannels: channels(id, input: false), transport: read(id, address(kAudioDevicePropertyTransportType), initial: UInt32(0)) ?? 0)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func channels(_ id: AudioDeviceID, input: Bool) -> Int {
        var property = address(kAudioDevicePropertyStreamConfiguration, input: input); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr, size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, memory) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
        read(system, address(selector), initial: AudioDeviceID(0)) ?? 0
    }
    static func setDefault(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) throws { try write(system, address(selector), value: id) }
    static func controlElements(_ device: SystemAudioDevice, selector: AudioObjectPropertySelector, input: Bool, writable: Bool) -> [UInt32] {
        let count = input ? device.inputChannels : device.outputChannels
        let elements = (0...max(0, count)).map(UInt32.init).filter { element in
            var property = address(selector, input: input, element: element)
            guard AudioObjectHasProperty(device.id, &property) else { return false }
            guard writable else { return true }
            var settable: DarwinBoolean = false
            return AudioObjectIsPropertySettable(device.id, &property, &settable) == noErr && settable.boolValue
        }
        return elements.contains(0) ? [0] : elements
    }
    static func volume(_ device: SystemAudioDevice, input: Bool) -> Float? {
        let values = controlElements(device, selector: kAudioDevicePropertyVolumeScalar, input: input, writable: false).compactMap { read(device.id, address(kAudioDevicePropertyVolumeScalar, input: input, element: $0), initial: Float(0)) }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }
    static func setVolume(_ value: Float, device: SystemAudioDevice, input: Bool) throws {
        let elements = controlElements(device, selector: kAudioDevicePropertyVolumeScalar, input: input, writable: true)
        guard !elements.isEmpty else { throw AudioSettingsError.message("该设备不支持系统音量调节，请使用设备上的旋钮。") }
        for element in elements { try write(device.id, address(kAudioDevicePropertyVolumeScalar, input: input, element: element), value: min(1, max(0, value))) }
    }
    static func muted(_ device: SystemAudioDevice, input: Bool) -> Bool? {
        let values = controlElements(device, selector: kAudioDevicePropertyMute, input: input, writable: false).compactMap { read(device.id, address(kAudioDevicePropertyMute, input: input, element: $0), initial: UInt32(0)) }
        return values.isEmpty ? nil : values.allSatisfy { $0 != 0 }
    }
    static func setMuted(_ muted: Bool, device: SystemAudioDevice, input: Bool) throws {
        let elements = controlElements(device, selector: kAudioDevicePropertyMute, input: input, writable: true)
        guard !elements.isEmpty else { throw AudioSettingsError.message("该设备不支持系统静音。") }
        for element in elements { try write(device.id, address(kAudioDevicePropertyMute, input: input, element: element), value: UInt32(muted ? 1 : 0)) }
    }
}

enum AudioSettingsError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
