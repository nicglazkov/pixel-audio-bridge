import Foundation
import CoreAudio

// paboutput — read and set the macOS default output device.
//
// scrcpy plays through SDL to whatever macOS calls the default output, and has
// no way to target a device. So the bridge's safety check becomes "is the
// default output still the device we want?", which has to be cheap enough to
// poll twice a second. `system_profiler` takes about a second; this takes
// microseconds.
//
//   paboutput get          -> "<uid>\t<name>"
//   paboutput set <uid>    -> exit 0 on success
//   paboutput list         -> JSON array of {uid, name, default}

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector,
                               mScope: scope,
                               mElement: kAudioObjectPropertyElementMain)
}

func defaultOutputDevice() -> AudioDeviceID? {
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    let status = AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &id)
    return status == noErr && id != 0 ? id : nil
}

func stringProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) {
        $0.withMemoryRebound(to: UInt8.self, capacity: Int(size)) { raw in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw)
        }
    }
    guard status == noErr, let cf = value else { return nil }
    return cf as String
}

func deviceUID(_ device: AudioDeviceID) -> String? {
    stringProperty(device, kAudioDevicePropertyDeviceUID)
}

func deviceName(_ device: AudioDeviceID) -> String? {
    stringProperty(device, kAudioObjectPropertyName)
}

/// A device counts as an output only if it actually has output channels —
/// microphones and input-only aggregates otherwise show up in the list.
func hasOutputChannels(_ device: AudioDeviceID) -> Bool {
    var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return false }

    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return false }

    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.contains { $0.mNumberChannels > 0 }
}

func allDevices() -> [AudioDeviceID] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func setDefaultOutput(uid: String) -> Bool {
    guard let target = allDevices().first(where: { deviceUID($0) == uid && hasOutputChannels($0) }) else {
        FileHandle.standardError.write("no output device with UID \(uid)\n".data(using: .utf8)!)
        return false
    }
    var id = target
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    let status = AudioObjectSetPropertyData(systemObject, &addr, 0, nil,
                                            UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    if status != noErr {
        FileHandle.standardError.write("AudioObjectSetPropertyData failed: OSStatus \(status)\n".data(using: .utf8)!)
        return false
    }
    // CoreAudio can report success without the change taking effect, so confirm
    // by reading the property back rather than trusting the status code.
    usleep(200_000)
    guard let now = defaultOutputDevice(), now == target else {
        FileHandle.standardError.write("set reported success but default is still \(deviceUID(defaultOutputDevice() ?? 0) ?? "?")\n".data(using: .utf8)!)
        return false
    }
    return true
}

func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

// MARK: - main

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "get"

switch command {
case "get":
    guard let dev = defaultOutputDevice(), let uid = deviceUID(dev) else {
        FileHandle.standardError.write("no default output device\n".data(using: .utf8)!)
        exit(1)
    }
    print("\(uid)\t\(deviceName(dev) ?? uid)")

case "set":
    guard args.count > 2 else {
        FileHandle.standardError.write("usage: paboutput set <uid>\n".data(using: .utf8)!)
        exit(2)
    }
    exit(setDefaultOutput(uid: args[2]) ? 0 : 1)

case "list":
    let current = defaultOutputDevice()
    let entries = allDevices().filter(hasOutputChannels).compactMap { dev -> String? in
        guard let uid = deviceUID(dev) else { return nil }
        let name = deviceName(dev) ?? uid
        return "{\"uid\":\"\(escape(uid))\",\"name\":\"\(escape(name))\",\"default\":\(dev == current)}"
    }
    print("[\(entries.joined(separator: ","))]")

default:
    FileHandle.standardError.write("usage: paboutput get|set <uid>|list\n".data(using: .utf8)!)
    exit(2)
}
