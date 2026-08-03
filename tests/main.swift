import Foundation

// Tests for BridgeLogic and the JSON contract with `pab`.
// Compiled together with app/BridgeController.swift; see tests/run.sh.

var passed = 0, failed = 0

func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    if condition { passed += 1; print("  \u{001B}[32mok\u{001B}[0m   \(name)") }
    else { failed += 1; print("  \u{001B}[31mFAIL\u{001B}[0m \(name)\n     \(detail())") }
}

func eq<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    check(name, actual == expected, "expected \(expected), got \(actual)")
}

func phone(_ serial: String, _ kind: String, hw: String, model: String = "Pixel 9") -> PhoneDevice {
    PhoneDevice(serial: serial, model: model, kind: kind, serialno: hw)
}

print("BridgeLogic")

// ------------------------------------------------------------- phone listing

// One handset reachable over both links is still one handset.
let bothLinks = [phone("ABC123", "usb", hw: "ABC123"),
                 phone("10.0.0.5:5555", "wifi", hw: "ABC123")]

eq("one handset on two links collapses to one entry",
   BridgeLogic.availablePhones(bothLinks, transport: .auto).count, 1)
eq("the surviving entry is the USB one",
   BridgeLogic.availablePhones(bothLinks, transport: .auto).first?.serial, "ABC123")
eq("wired transport keeps only the cabled entry",
   BridgeLogic.availablePhones(bothLinks, transport: .usb).map(\.serial), ["ABC123"])
eq("wireless transport keeps only the wireless entry",
   BridgeLogic.availablePhones(bothLinks, transport: .wifi).map(\.serial), ["10.0.0.5:5555"])

// Order must not matter: the USB entry wins even when listed second.
let reversed = [bothLinks[1], bothLinks[0]]
eq("dedupe prefers USB regardless of input order",
   BridgeLogic.availablePhones(reversed, transport: .auto).first?.serial, "ABC123")

// Two genuinely different handsets must both survive.
let twoPhones = [phone("ABC123", "usb", hw: "ABC123"),
                 phone("XYZ789", "usb", hw: "XYZ789", model: "Pixel 7")]
eq("two distinct handsets both remain",
   BridgeLogic.availablePhones(twoPhones, transport: .auto).count, 2)

// Missing hardware serial falls back to the adb serial rather than collapsing
// unrelated devices into one.
let noHW = [phone("ABC123", "usb", hw: ""), phone("XYZ789", "usb", hw: "")]
eq("absent hardware serial does not merge different phones",
   BridgeLogic.availablePhones(noHW, transport: .auto).count, 2)

eq("no phones yields no entries",
   BridgeLogic.availablePhones([], transport: .auto).count, 0)

// ---------------------------------------------------------- phone selection

let wiredOnly = BridgeLogic.availablePhones(bothLinks, transport: .usb)
eq("a selection matching the transport is kept",
   BridgeLogic.effectiveSelectedPhone("ABC123", available: wiredOnly), "ABC123")
eq("a selection contradicting the transport falls back to automatic",
   BridgeLogic.effectiveSelectedPhone("10.0.0.5:5555", available: wiredOnly), "")
eq("an empty selection stays empty",
   BridgeLogic.effectiveSelectedPhone("", available: wiredOnly), "")
eq("a stale serial falls back to automatic",
   BridgeLogic.effectiveSelectedPhone("GONE", available: wiredOnly), "")

// ------------------------------------------------------------- link resolution

check("an explicit wired serial resolves to wired",
      BridgeLogic.resolvedWired(selectedPhone: "ABC123", transport: .wifi, usbPresent: false))
check("an explicit wireless serial resolves to wireless",
      !BridgeLogic.resolvedWired(selectedPhone: "10.0.0.5:5555", transport: .usb, usbPresent: true))
check("wired transport resolves to wired",
      BridgeLogic.resolvedWired(selectedPhone: "", transport: .usb, usbPresent: false))
check("wireless transport resolves to wireless",
      !BridgeLogic.resolvedWired(selectedPhone: "", transport: .wifi, usbPresent: true))
check("auto follows the cable when present",
      BridgeLogic.resolvedWired(selectedPhone: "", transport: .auto, usbPresent: true))
check("auto falls back to wireless without a cable",
      !BridgeLogic.resolvedWired(selectedPhone: "", transport: .auto, usbPresent: false))

// ------------------------------------------------------------------ latency

var info = BridgeInfo()
info.buffer_usb = 15; info.buffer_wifi = 200; info.output_buffer = 5

eq("wired uses the USB buffer",     BridgeLogic.buffer(wired: true,  info: info), 15)
eq("wireless uses the Wi-Fi buffer", BridgeLogic.buffer(wired: false, info: info), 200)
eq("wired latency is buffer + output + bluetooth",
   BridgeLogic.latencyMs(buffer: 15, outputBuffer: 5), 191)
eq("wireless latency is buffer + output + bluetooth",
   BridgeLogic.latencyMs(buffer: 200, outputBuffer: 5), 376)

// The Bluetooth hop should dominate a wired budget; if this ever stops being
// true the README's central claim needs revisiting.
let wiredTotal = BridgeLogic.latencyMs(buffer: 15, outputBuffer: 5)
check("bluetooth is the majority of the wired budget",
      Double(BridgeLogic.bluetoothMs) / Double(wiredTotal) > 0.85,
      "bluetooth share was \(Double(BridgeLogic.bluetoothMs) / Double(wiredTotal))")

// -------------------------------------------------------------- JSON contract

print("\nJSON contract with pab")

let full = """
{"device":"AA:output","device_name":"Some Max","device_match":"AirPods Max",
 "output_uid":"","default_uid":"AA:output","default_name":"Some Max",
 "phone_serial":"","usb":"ABC123","tcp":"10.0.0.5:5555","phone_ip":"10.0.0.5",
 "buffer_usb":15,"buffer_wifi":200,"output_buffer":5,"running":true,"pgid":"42",
 "outputs":[{"uid":"AA:output","name":"Some Max","default":true}],
 "phones":[{"serial":"ABC123","model":"Pixel 9","kind":"usb","serialno":"ABC123"}]}
"""
if let decoded = try? JSONDecoder().decode(BridgeInfo.self, from: Data(full.utf8)) {
    check("a complete pab payload decodes", true)
    eq("buffer_usb survives decoding", decoded.buffer_usb, 15)
    eq("outputs survive decoding", decoded.outputs.count, 1)
    eq("phones survive decoding", decoded.phones.count, 1)
    eq("hardware serial survives decoding", decoded.phones.first?.serialno, "ABC123")
    check("a present device reads as connected", decoded.headphonesConnected)
    check("a USB serial reads as wired", decoded.isWired)
} else {
    check("a complete pab payload decodes", false, "decode threw")
}

// Fields with Swift defaults must tolerate absence. An older or partial payload
// should not take the whole UI down.
let minimal = """
{"device":"","device_name":"","device_match":"AirPods Max","output_uid":"",
 "default_uid":"","default_name":"","phone_serial":"","usb":"","tcp":"",
 "phone_ip":"","buffer_usb":15,"buffer_wifi":200,"output_buffer":5,
 "running":false,"pgid":"",
 "outputs":[{"uid":"A","name":"A"}],
 "phones":[{"serial":"S","model":"M","kind":"usb"}]}
"""
do {
    let decoded = try JSONDecoder().decode(BridgeInfo.self, from: Data(minimal.utf8))
    check("a payload omitting optional keys still decodes", true)
    eq("omitted serialno defaults to empty", decoded.phones.first?.serialno, "")
    eq("omitted default flag defaults to false", decoded.outputs.first?.default, false)
    eq("a phone without a hardware serial falls back to its adb serial",
       decoded.phones.first?.hardwareID, "S")
} catch {
    check("a payload omitting optional keys still decodes", false, "\(error)")
}

// An empty object must degrade to defaults rather than throwing, which is the
// whole point of the tolerant decoder.
if let empty = try? JSONDecoder().decode(BridgeInfo.self, from: Data("{}".utf8)) {
    check("an empty payload degrades to defaults", true)
    eq("empty payload keeps the default USB buffer", empty.buffer_usb, 15)
    check("empty payload reports nothing connected", !empty.headphonesConnected)
} else {
    check("an empty payload degrades to defaults", false, "decode threw")
}

// ---- version comparison ---------------------------------------------------
// This decides whether anyone ever sees an update banner, and the failure that
// matters is the string compare that thinks 1.10 is older than 1.9.

check("a higher patch is newer",            Version.isNewer("1.1.2", than: "1.1.1"))
check("a higher minor is newer",            Version.isNewer("1.2.0", than: "1.1.9"))
check("a higher major is newer",            Version.isNewer("2.0.0", than: "1.9.9"))
check("10 beats 9 numerically, not by string",
      Version.isNewer("1.10.0", than: "1.9.0"))
check("the same version is not newer",     !Version.isNewer("1.1.1", than: "1.1.1"))
check("an older version is not newer",     !Version.isNewer("1.0.0", than: "1.1.1"))
check("a v prefix is tolerated",            Version.isNewer("v1.2.0", than: "1.1.0"))
check("a missing component counts as zero", !Version.isNewer("1.2", than: "1.2.0"))
check("a longer equal version is not newer", !Version.isNewer("1.2.0.0", than: "1.2"))
check("trailing text does not inflate a component",
      !Version.isNewer("1.2.0-beta", than: "1.2.0"))
eq("parts splits numerically", Version.parts("v1.10.3"), [1, 10, 3])

// ---- dependency reporting -------------------------------------------------

if let d = try? JSONDecoder().decode(BridgeInfo.self, from: Data(
    #"{"deps":{"scrcpy":"/opt/homebrew/bin/scrcpy","adb":"","paboutput":"/x"}}"#.utf8)) {
    check("a missing tool is reported missing", d.deps.missing.map(\.rawValue) == ["adb"])
    check("dependencies are not satisfied when one is absent", !d.deps.isSatisfied)
    eq("a found tool keeps its path", d.deps.scrcpy, "/opt/homebrew/bin/scrcpy")
} else {
    check("dependency payload decodes", false, "decode threw")
}

// A default BridgeInfo reports both tools missing, which is exactly why the
// view must not act on it before the first successful read. The controller
// gates on hasLoadedInfo; this records why that gate has to exist.
if let old = try? JSONDecoder().decode(BridgeInfo.self, from: Data("{}".utf8)) {
    check("defaults look like nothing is installed, hence the load gate",
          old.deps.missing.count == 2 && !old.deps.isSatisfied)
}

print("\n  \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
