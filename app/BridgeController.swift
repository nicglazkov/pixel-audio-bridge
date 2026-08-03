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
        case .usb:  return "USB cable, 15 ms buffer, lowest latency"
        case .wifi: return "Wi-Fi, 200 ms buffer, good for music and podcasts"
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

// Swift's synthesised Decodable ignores a property's default value and throws on
// a missing key. Since `pab` ships inside the bundle but can be replaced, any
// version skew would fail the whole decode, and refresh() discards decode
// errors, so the UI would silently go blank. Optional fields are therefore
// decoded explicitly with decodeIfPresent.

struct AudioOutput: Codable, Hashable, Identifiable {
    let uid: String
    let name: String
    /// Whether this is currently the macOS default output. scrcpy plays to the
    /// default, so this is what actually determines where audio lands.
    var `default`: Bool = false
    var id: String { uid }

    init(uid: String, name: String, default isDefault: Bool = false) {
        self.uid = uid; self.name = name; self.default = isDefault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(String.self, forKey: .uid)
        name = try c.decode(String.self, forKey: .name)
        `default` = try c.decodeIfPresent(Bool.self, forKey: .default) ?? false
    }
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

    init(serial: String, model: String, kind: String, serialno: String = "") {
        self.serial = serial; self.model = model; self.kind = kind; self.serialno = serialno
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serial = try c.decode(String.self, forKey: .serial)
        model  = try c.decode(String.self, forKey: .model)
        kind   = try c.decode(String.self, forKey: .kind)
        serialno = try c.decodeIfPresent(String.self, forKey: .serialno) ?? ""
    }
}

/// Where each external tool was found. An empty path means it is not installed,
/// which is the single most common reason a fresh install does nothing useful.
struct Dependencies: Codable {
    var scrcpy: String = ""
    var adb: String = ""
    var paboutput: String = ""

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scrcpy    = try c.decodeIfPresent(String.self, forKey: .scrcpy) ?? ""
        adb       = try c.decodeIfPresent(String.self, forKey: .adb) ?? ""
        paboutput = try c.decodeIfPresent(String.self, forKey: .paboutput) ?? ""
    }

    var missing: [Tool] { Tool.allCases.filter { path(for: $0).isEmpty } }
    var isSatisfied: Bool { missing.isEmpty }

    func path(for tool: Tool) -> String {
        switch tool {
        case .scrcpy: return scrcpy
        case .adb:    return adb
        }
    }

    /// paboutput ships inside the bundle, so it is deliberately not offered as
    /// something the user could install. Its absence is a broken build.
    enum Tool: String, CaseIterable, Identifiable {
        case scrcpy, adb
        var id: String { rawValue }

        var title: String {
            switch self {
            case .scrcpy: return "scrcpy"
            case .adb:    return "adb"
            }
        }
        var why: String {
            switch self {
            case .scrcpy: return "Captures the audio and plays it"
            case .adb:    return "Talks to the phone, from the Android SDK"
            }
        }
        var installCommand: String {
            switch self {
            case .scrcpy: return "brew install scrcpy"
            case .adb:    return "brew install --cask android-platform-tools"
            }
        }
    }
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
    var deps: Dependencies = Dependencies()
    var outputs: [AudioOutput] = []
    var phones: [PhoneDevice] = []

    var headphonesConnected: Bool { !device.isEmpty }
    var phoneReachable: Bool { !usb.isEmpty || !tcp.isEmpty }
    var isWired: Bool { !usb.isEmpty }

    init() {}

    /// Every field is optional on the wire. A `pab` that predates or postdates
    /// this binary should degrade to defaults, never blank the UI.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: k) ?? "" }
        device        = try str(.device)
        device_name   = try str(.device_name)
        device_match  = try str(.device_match)
        output_uid    = try str(.output_uid)
        default_uid   = try str(.default_uid)
        default_name  = try str(.default_name)
        phone_serial  = try str(.phone_serial)
        usb           = try str(.usb)
        tcp           = try str(.tcp)
        phone_ip      = try str(.phone_ip)
        pgid          = try str(.pgid)
        buffer_usb    = try c.decodeIfPresent(Int.self,  forKey: .buffer_usb)    ?? 15
        buffer_wifi   = try c.decodeIfPresent(Int.self,  forKey: .buffer_wifi)   ?? 200
        output_buffer = try c.decodeIfPresent(Int.self,  forKey: .output_buffer) ?? 5
        running       = try c.decodeIfPresent(Bool.self, forKey: .running)       ?? false
        deps          = try c.decodeIfPresent(Dependencies.self,   forKey: .deps)    ?? Dependencies()
        outputs       = try c.decodeIfPresent([AudioOutput].self, forKey: .outputs) ?? []
        phones        = try c.decodeIfPresent([PhoneDevice].self, forKey: .phones) ?? []
    }
}

// MARK: - Pure logic
//
// Kept free of UserDefaults, timers and processes so it can be tested directly.
// The controller below is a thin stateful wrapper over these.

enum BridgeLogic {

    /// Measured, not estimated: CoreAudio reported this device latency for the
    /// Bluetooth headphones it was timed on. It dominates the budget, no setting
    /// changes it, and it differs between models, so treat it as indicative.
    static let bluetoothMs = 171

    /// Phones reachable over the chosen link, one entry per physical handset.
    /// The same phone appears twice when USB and wireless ADB are both live, so
    /// entries are collapsed by hardware serial, keeping the USB one, which is
    /// what `auto` would pick anyway.
    static func availablePhones(_ phones: [PhoneDevice], transport: Transport) -> [PhoneDevice] {
        let onThisLink: [PhoneDevice]
        switch transport {
        case .auto: onThisLink = phones
        case .usb:  onThisLink = phones.filter { $0.isWired }
        case .wifi: onThisLink = phones.filter { !$0.isWired }
        }
        var seen = Set<String>()
        return onThisLink
            .sorted { $0.isWired && !$1.isWired }
            .filter { seen.insert($0.hardwareID).inserted }
    }

    /// A phone selection applies only while it matches the chosen transport;
    /// otherwise fall back to automatic rather than contradicting the transport.
    static func effectiveSelectedPhone(_ selected: String, available: [PhoneDevice]) -> String {
        available.contains { $0.serial == selected } ? selected : ""
    }

    /// An explicitly chosen phone decides the link on its own, since its serial
    /// already encodes whether it is USB or Wi-Fi.
    static func resolvedWired(selectedPhone: String, transport: Transport, usbPresent: Bool) -> Bool {
        if !selectedPhone.isEmpty { return !selectedPhone.contains(":") }
        switch transport {
        case .usb:  return true
        case .wifi: return false
        case .auto: return usbPresent
        }
    }

    static func buffer(wired: Bool, info: BridgeInfo) -> Int {
        wired ? info.buffer_usb : info.buffer_wifi
    }

    static func latencyMs(buffer: Int, outputBuffer: Int) -> Int {
        buffer + outputBuffer + bluetoothMs
    }
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

    /// CoreAudio UID to route to. Empty means follow the configured name match,
    /// or the current system default output when no name is configured.
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

    // MARK: Updates

    /// Version string of a newer release, once one has been seen. Nil the rest of
    /// the time, including on every kind of failure.
    @Published var availableUpdate: String?

    /// False until `pab info` has been read once. Until then `info` holds its
    /// defaults, where every dependency path is empty, and treating that as
    /// "nothing is installed" would flash a setup screen on every launch and
    /// would stick permanently if a decode ever failed.
    @Published private(set) var hasLoadedInfo = false

    /// Unasked until the user answers the first-launch prompt. Nothing touches
    /// the network while this is .unasked, which is what lets the privacy policy
    /// keep saying the app makes no requests you did not agree to.
    @Published var updateConsent: UpdateConsent = .unasked {
        didSet {
            guard updateConsent != oldValue else { return }
            UserDefaults.standard.set(updateConsent.rawValue, forKey: "updateConsent")
            if updateConsent == .granted { checkForUpdates(force: true) }
            if updateConsent == .declined { availableUpdate = nil }
        }
    }

    func checkForUpdates(force: Bool = false) {
        guard updateConsent == .granted else { return }
        let d = UserDefaults.standard
        if !force {
            let last = d.double(forKey: "lastUpdateCheck")
            guard Date().timeIntervalSince1970 - last > UpdateCheck.interval else { return }
        }
        d.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        UpdateCheck.latestVersion { [weak self] newer in
            DispatchQueue.main.async {
                // A version the user already dismissed stays dismissed, but only
                // that one: anything later is announced again.
                guard let newer else {
                    self?.availableUpdate = nil
                    return
                }
                let dismissed = UserDefaults.standard.string(forKey: "dismissedUpdate") ?? ""
                self?.availableUpdate = (newer == dismissed) ? nil : newer
            }
        }
    }

    /// Dismissing hides the banner for that version only, so the next release
    /// says so again rather than being swallowed forever.
    func dismissUpdate() {
        if let v = availableUpdate { UserDefaults.standard.set(v, forKey: "dismissedUpdate") }
        availableUpdate = nil
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
        updateConsent = UpdateConsent(rawValue: d.string(forKey: "updateConsent") ?? "") ?? .unasked
        checkForUpdates()
    }

    // MARK: Paths

    /// `pab` ships in the bundle's Resources. There is no meaningful fallback: if
    /// it is missing the build is broken, and guessing at a path on disk would only
    /// turn that into a confusing runtime failure somewhere else.
    private var pabPath: String {
        Bundle.main.resourceURL?.appendingPathComponent("pab").path ?? "pab"
    }

    var helperMissing: Bool {
        !FileManager.default.isExecutableFile(atPath: pabPath)
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
        BridgeLogic.availablePhones(info.phones, transport: transport)
    }

    var effectiveSelectedPhone: String {
        BridgeLogic.effectiveSelectedPhone(selectedPhone, available: availablePhones)
    }

    var resolvedWired: Bool {
        BridgeLogic.resolvedWired(selectedPhone: effectiveSelectedPhone,
                                  transport: transport,
                                  usbPresent: info.isWired)
    }

    var effectiveBuffer: Int { BridgeLogic.buffer(wired: resolvedWired, info: info) }

    var estimatedLatencyMs: Int {
        BridgeLogic.latencyMs(buffer: effectiveBuffer, outputBuffer: info.output_buffer)
    }

    /// True when the output that would actually be used is present. A remembered
    /// selection that has been disconnected counts as unavailable, so the bridge
    /// waits rather than routing somewhere else.
    var outputAvailable: Bool {
        if !guardOutput { return true }        // no specific device to wait for
        if !selectedOutput.isEmpty { return info.outputs.contains { $0.uid == selectedOutput } }
        return info.headphonesConnected
    }

    /// What the bridge is waiting for, named even when it is absent.
    var pinnedDeviceLabel: String {
        if !selectedOutput.isEmpty {
            return info.outputs.first { $0.uid == selectedOutput }?.name ?? "the selected output"
        }
        // No name configured means the bridge follows whatever this Mac is
        // playing through, so there is no absent device to name.
        if info.device_match.isEmpty {
            return info.default_name.isEmpty ? "your output device" : info.default_name
        }
        return info.device_match
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

    /// Names the phone the way its owner would, model and link, rather than by
    /// its adb serial, which is an IP address over Wi-Fi and means nothing to a
    /// person reading it.
    var phoneDescription: String {
        let serial = effectiveSelectedPhone.isEmpty
            ? (resolvedWired && !info.usb.isEmpty ? info.usb : (info.tcp.isEmpty ? info.usb : info.tcp))
            : effectiveSelectedPhone
        guard !serial.isEmpty else { return "Not reachable" }
        let link = serial.contains(":") ? "Wi-Fi" : "USB"
        let model = info.phones.first { $0.serial == serial }?.model
        return "\(model ?? serial) on \(link)"
    }

    var statusText: String {
        switch state {
        case .off:              return "Off"
        case .waiting:          return "Waiting for \(pinnedDeviceLabel)"
        case .starting:         return "Connecting"
        case .streaming:        return guardOutput ? "Streaming" : "Streaming to \(info.default_name)"
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
        // audio device. Clear them before claiming it, off the main thread so
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
                self.hasLoadedInfo = true
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
        guard !helperMissing else {
            state = .failed("Bridge helper missing from the app bundle. Rebuild with ./build.sh")
            return
        }
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
        // standby). That is expected, not a failure, so wait for it to return
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

        state = .failed(lastError.isEmpty ? "Reconnecting" : lastError)
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
