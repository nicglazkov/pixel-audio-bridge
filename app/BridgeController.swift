import SwiftUI
import Combine

// MARK: - Model

enum Transport: String, CaseIterable, Identifiable {
    case auto, usb, wifi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .usb:  return "Wired"
        case .wifi: return "Wireless"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "USB when plugged in, otherwise Wi-Fi"
        case .usb:  return "USB cable · 50 ms buffer · stays in sync with video"
        case .wifi: return "Wi-Fi · 200 ms buffer · best for music and podcasts"
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .usb:  return "cable.connector"
        case .wifi: return "wifi"
        }
    }
}

enum BridgeState: Equatable {
    /// Not enabled by the user.
    case off
    /// Enabled, but the guarded output device is not present yet. The bridge
    /// starts by itself as soon as it appears.
    case waiting
    case starting
    case streaming
    case failed(String)

    /// Whether the user has switched the bridge on, regardless of whether audio
    /// is actually flowing right now.
    var isActive: Bool { self != .off }
}

struct AudioOutput: Codable, Hashable, Identifiable {
    let uid: String
    let name: String
    /// Whether this is currently the macOS default output. scrcpy plays to the
    /// default, so this is what actually determines where audio lands.
    var `default`: Bool = false
    var id: String { uid }
}

struct PhoneDevice: Codable, Hashable, Identifiable {
    let serial: String
    let model: String
    let kind: String
    /// Hardware serial. The adb serial differs per link, so this is what
    /// identifies one physical handset present on both USB and Wi-Fi.
    var serialno: String = ""
    var id: String { serial }

    var isWired: Bool { kind == "usb" }
    var hardwareID: String { serialno.isEmpty ? serial : serialno }
    var display: String { model }
}

struct BridgeInfo: Codable {
    var device: String = ""
    var device_name: String = ""
    var device_match: String = ""
    var output_uid: String = ""
    var default_uid: String = ""
    var default_name: String = ""
    var phone_serial: String = ""
    var usb: String = ""
    var tcp: String = ""
    var phone_ip: String = ""
    var buffer_usb: Int = 15
    var buffer_wifi: Int = 200
    var output_buffer: Int = 5
    var running: Bool = false
    var pgid: String = ""
    var outputs: [AudioOutput] = []
    var phones: [PhoneDevice] = []

    var headphonesConnected: Bool { !device.isEmpty }
    var phoneReachable: Bool { !usb.isEmpty || !tcp.isEmpty }
    var isWired: Bool { !usb.isEmpty }
}

// MARK: - Controller

/// Owns the `pab` process and mirrors its state for the UI.
/// Shared as a singleton so the app delegate can tear the bridge down on quit
/// without threading a reference through the SwiftUI scene graph.
final class BridgeController: ObservableObject {

    static let shared = BridgeController()

    @Published private(set) var state: BridgeState = .off
    @Published private(set) var info = BridgeInfo()

    /// User's on/off intent. Persisted, so relaunching resumes where you left off.
    @Published var enabled: Bool = true {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: "enabled")
            enabled ? evaluate() : stop()
        }
    }

    /// The kill switch. On: only ever play to the pinned device, waiting for it
    /// to appear. Off: play to whatever macOS currently calls the default output,
    /// which includes the built-in speakers.
    @Published var guardOutput: Bool = true {
        didSet { persistAndReload(guardOutput != oldValue, guardOutput, "guardOutput") }
    }

    @Published var transport: Transport = .auto {
        didSet { persistAndReload(transport != oldValue, transport.rawValue, "transport") }
    }

    /// CoreAudio UID to route to. Empty means "match by name" (the AirPods Max).
    @Published var selectedOutput: String = "" {
        didSet { persistAndReload(selectedOutput != oldValue, selectedOutput, "selectedOutput") }
    }

    /// adb serial to use. Empty means auto-select by transport.
    @Published var selectedPhone: String = "" {
        didSet { persistAndReload(selectedPhone != oldValue, selectedPhone, "selectedPhone") }
    }

    private func persistAndReload(_ changed: Bool, _ value: Any, _ key: String) {
        guard changed else { return }
        UserDefaults.standard.set(value, forKey: key)
        guard enabled else { return }
        if process != nil {
            stop { [weak self] in self?.evaluate() }
        } else {
            evaluate()
        }
    }

    private var process: Process?
    private var stoppingIntentionally = false
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 4
    private var pollTimer: Timer?
    private var lastError = ""

    private init() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "transport"), let t = Transport(rawValue: raw) {
            transport = t
        }
        selectedOutput = d.string(forKey: "selectedOutput") ?? ""
        selectedPhone  = d.string(forKey: "selectedPhone") ?? ""
        // Both default to true on a fresh install, where object(forKey:) is nil.
        enabled     = (d.object(forKey: "enabled") as? Bool) ?? true
        guardOutput = (d.object(forKey: "guardOutput") as? Bool) ?? true
    }

    // MARK: Paths

    private var pabPath: String {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("pab").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        return NSString(string: "~/dev/pixel-audio-bridge/bin/pab").expandingTildeInPath
    }

    var logPath: String {
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        return (tmp as NSString).appendingPathComponent("pixel-audio-bridge/bridge.log")
    }

    // MARK: Derived display values

    /// Phones reachable over the chosen link. The same handset appears twice when
    /// both USB and wireless ADB are live, so listing both under an explicit
    /// "Wired" or "Wireless" choice offers a selection that contradicts it.
    var availablePhones: [PhoneDevice] {
        let onThisLink: [PhoneDevice]
        switch transport {
        case .auto: onThisLink = info.phones
        case .usb:  onThisLink = info.phones.filter { $0.isWired }
        case .wifi: onThisLink = info.phones.filter { !$0.isWired }
        }

        // One handset on both links is still one handset. Collapse by hardware
        // serial, keeping the USB entry, which is what `auto` would pick anyway.
        var seen = Set<String>()
        return onThisLink
            .sorted { $0.isWired && !$1.isWired }
            .filter { seen.insert($0.hardwareID).inserted }
    }

    /// A phone selection applies only while it matches the chosen transport.
    /// Falling back to automatic avoids a stale selection fighting the transport,
    /// and avoids mutating state (and restarting) whenever transport changes.
    var effectiveSelectedPhone: String {
        availablePhones.contains { $0.serial == selectedPhone } ? selectedPhone : ""
    }

    /// Whether the resolved link is USB. An explicitly chosen phone decides this
    /// on its own, since its serial already encodes the link type.
    var resolvedWired: Bool {
        let phone = effectiveSelectedPhone
        if !phone.isEmpty { return !phone.contains(":") }
        switch transport {
        case .usb:  return true
        case .wifi: return false
        case .auto: return info.isWired
        }
    }

    var effectiveBuffer: Int { resolvedWired ? info.buffer_usb : info.buffer_wifi }

    /// Capture buffer + SDL output buffer + the AirPods Max Bluetooth hop. The
    /// 171 ms is measured, not guessed — CoreAudio reports it for that device —
    /// and it dominates everything else here.
    var estimatedLatencyMs: Int { effectiveBuffer + info.output_buffer + 171 }

    /// True when the output that would actually be pinned is present. A remembered
    /// selection that has been disconnected counts as unavailable — the bridge
    /// must refuse rather than fall back to some other device.
    var outputAvailable: Bool {
        if !guardOutput { return true }        // no pinned device to wait for
        if !selectedOutput.isEmpty { return info.outputs.contains { $0.uid == selectedOutput } }
        return info.headphonesConnected
    }

    /// What the bridge is waiting for, named even when it is absent.
    var pinnedDeviceLabel: String {
        if !selectedOutput.isEmpty {
            return info.outputs.first { $0.uid == selectedOutput }?.name ?? "the selected output"
        }
        return info.device_match.isEmpty ? "AirPods Max" : info.device_match
    }

    var outputDeviceName: String {
        guard guardOutput else { return info.default_name.isEmpty ? "System default" : info.default_name }
        if !selectedOutput.isEmpty {
            return info.outputs.first { $0.uid == selectedOutput }?.name ?? "Selected device unavailable"
        }
        if info.headphonesConnected {
            return info.device_name.isEmpty ? info.device_match : info.device_name
        }
        return "Not connected"
    }

    var phoneDescription: String {
        let phone = effectiveSelectedPhone
        if !phone.isEmpty {
            return info.phones.first { $0.serial == phone }?.display ?? "Selected phone unavailable"
        }
        if resolvedWired, !info.usb.isEmpty { return "\(info.usb) · USB" }
        if !info.tcp.isEmpty { return "\(info.tcp) · Wi-Fi" }
        if !info.usb.isEmpty { return "\(info.usb) · USB" }
        return "Not reachable"
    }

    var statusText: String {
        switch state {
        case .off:              return "Off"
        case .waiting:          return "Waiting for \(pinnedDeviceLabel)"
        case .starting:         return "Connecting…"
        case .streaming:        return guardOutput ? "Streaming" : "Streaming — \(info.default_name)"
        case .failed(let msg):  return msg
        }
    }

    var menuBarSymbol: String {
        switch state {
        case .streaming:  return "headphones.circle.fill"
        case .starting:   return "headphones.circle"
        case .waiting:    return "headphones.circle.fill"
        case .failed:     return "exclamationmark.triangle.fill"
        case .off:        return "headphones"
        }
    }

    // MARK: Lifecycle

    func onLaunch() {
        // A previous run may have been force-quit, leaving orphans holding the
        // audio device. Clear them before claiming it — off the main thread, so
        // the window paints immediately instead of waiting on a subprocess.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runSync(["stop"])
            DispatchQueue.main.async {
                guard let self else { return }
                self.refresh()
                self.pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                    self?.refresh()
                }
                self.evaluate()
            }
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let data = self.runCapture(["info"]) else { return }
            guard let decoded = try? JSONDecoder().decode(BridgeInfo.self, from: data) else { return }
            DispatchQueue.main.async {
                self.info = decoded
                // Device availability may have just changed; that is the trigger
                // for leaving (or entering) the waiting state.
                self.evaluate()
            }
        }
    }

    /// The single decision point: given the user's intent and what is currently
    /// connected, should the bridge be running? Called on every poll, so a device
    /// appearing or vanishing is picked up without any explicit event plumbing.
    func evaluate() {
        guard enabled else {
            if process != nil { stop() } else { state = .off }
            return
        }

        // Kill switch on and the pinned device is missing: wait for it rather
        // than fail. This is what lets the app launch and idle harmlessly.
        if guardOutput && !outputAvailable {
            if process != nil {
                stop { [weak self] in self?.state = .waiting }
            } else if state != .waiting {
                state = .waiting
            }
            return
        }

        if process == nil, state != .starting {
            consecutiveFailures = 0
            start()
        }
    }

    func start() {
        guard process == nil else { return }
        stoppingIntentionally = false
        state = .starting

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pabPath)
        var args = ["run", "--transport", transport.rawValue]
        if !guardOutput { args.append("--no-guard") }
        if guardOutput, !selectedOutput.isEmpty { args += ["--device", selectedOutput] }
        if !effectiveSelectedPhone.isEmpty { args += ["--serial", effectiveSelectedPhone] }
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice

        let errPipe = Pipe()
        proc.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                let s = line.trimmingCharacters(in: .whitespaces)
                guard !s.isEmpty else { continue }
                DispatchQueue.main.async { self?.consume(s) }
            }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async { self?.exited(status: p.terminationStatus) }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            state = .failed("Could not launch pab")
        }
    }

    /// Tear the bridge down without blocking the main thread. Waiting on process
    /// termination inline froze the UI long enough for macOS to show the app as
    /// unresponsive, which looked like a crash when switching transport.
    func stop(then completion: (() -> Void)? = nil) {
        stoppingIntentionally = true
        state = enabled ? .waiting : .off
        let doomed = process
        process = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let doomed, doomed.isRunning {
                doomed.terminate()                 // pab traps TERM and kills its process group
                let deadline = Date().addingTimeInterval(5)
                while doomed.isRunning && Date() < deadline { usleep(100_000) }
            }
            self?.runSync(["stop"])                // backstop if the trap did not fire
            DispatchQueue.main.async {
                self?.refresh()
                completion?()
            }
        }
    }

    /// Blocking teardown, for `applicationWillTerminate` only: the app must not
    /// exit until the children are actually dead, or audio outlives the app.
    func stopBlocking() {
        stoppingIntentionally = true
        pollTimer?.invalidate()
        if let proc = process, proc.isRunning {
            proc.terminate()
            let deadline = Date().addingTimeInterval(5)
            while proc.isRunning && Date() < deadline { usleep(100_000) }
        }
        process = nil
        runSync(["stop"])
        state = .off
    }

    func restart() {
        stop { [weak self] in
            self?.consecutiveFailures = 0
            self?.evaluate()
        }
    }

    func toggle() { enabled.toggle() }

    // MARK: Internals

    private func consume(_ line: String) {
        if let r = line.range(of: "ERROR: ") {
            lastError = String(line[r.upperBound...])
        }
        if line.contains("bridge running") {
            consecutiveFailures = 0
            lastError = ""
            state = .streaming
            refresh()
        }
    }

    private func exited(status: Int32) {
        process = nil
        if stoppingIntentionally {
            return                                  // stop() already set .waiting or .off
        }
        guard enabled else { state = .off; return }

        // The pinned device vanished mid-stream (headphones removed, or gone to
        // standby). That is expected, not a failure — wait for it to return
        // instead of burning retries and surfacing an error.
        if guardOutput && !outputAvailable {
            state = .waiting
            refresh()
            return
        }

        // A refusal (no headphones, unreachable phone) is a standing condition
        // rather than a blip, so back off and eventually surface it instead of
        // retrying forever.
        consecutiveFailures += 1
        if consecutiveFailures >= maxConsecutiveFailures {
            state = .failed(lastError.isEmpty ? "Bridge exited (\(status))" : lastError)
            refresh()
            return
        }

        state = .failed(lastError.isEmpty ? "Reconnecting…" : lastError)
        let delay = Double(consecutiveFailures) * 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.process == nil, !self.stoppingIntentionally else { return }
            self.start()
        }
    }

    @discardableResult
    private func runSync(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pabPath)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus }
        catch { return -1 }
    }

    private func runCapture(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pabPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return data
        } catch { return nil }
    }
}
