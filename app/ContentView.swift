import SwiftUI

// MARK: - Palette

private extension BridgeState {
    var tint: Color {
        switch self {
        case .streaming: return .green
        case .starting:  return .blue
        case .waiting:   return .yellow
        case .failed:    return .orange
        case .off:       return .secondary
        }
    }
}

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject private var bridge: BridgeController

    var body: some View {
        VStack(spacing: 18) {
            hero
            transportPicker
            devicePickers
            details
            actions
        }
        .padding(22)
        // Width is fixed; height follows content, so the window tightens up when
        // the "connect your headphones" banner is hidden and grows when it is not.
        .frame(width: 420)
        .background(
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                    bridge.state.tint.opacity(0.07)],
                           startPoint: .top, endPoint: .bottom)
        )
        .onAppear { bridge.refresh() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                // Concentric rings, brightest while audio is actually flowing.
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(bridge.state.tint.opacity(bridge.state == .streaming ? 0.30 - Double(i) * 0.08
                                                                                     : 0.10),
                                lineWidth: 1.5)
                        .frame(width: 96 + CGFloat(i) * 26, height: 96 + CGFloat(i) * 26)
                }

                Circle()
                    .fill(bridge.state.tint.opacity(0.14))
                    .frame(width: 96, height: 96)

                if bridge.state == .streaming {
                    waveform
                } else {
                    Image(systemName: heroSymbol)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(bridge.state.tint)
                        .symbolEffect(.pulse, isActive: bridge.state == .starting || bridge.state == .waiting)
                }
            }
            .frame(height: 150)

            statusPill
        }
    }

    private var heroSymbol: String {
        switch bridge.state {
        case .starting: return "arrow.triangle.2.circlepath"
        case .waiting:  return "hourglass"
        case .failed:   return "exclamationmark.triangle"
        default:        return "headphones"
        }
    }

    /// Live bars while streaming. Driven by TimelineView so it animates
    /// continuously without a Timer or per-frame state churn.
    private var waveform: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule()
                        .fill(bridge.state.tint)
                        .frame(width: 5, height: barHeight(i, t))
                }
            }
        }
    }

    private func barHeight(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let a = sin(t * 3.1 + Double(i) * 0.9)
        let b = sin(t * 1.7 + Double(i) * 0.45)
        let v = ((a * 0.6 + b * 0.4) + 1) / 2          // normalise to 0 through 1
        return 10 + CGFloat(v) * 34
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(bridge.state.tint)
                .frame(width: 7, height: 7)
            Text(bridge.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(bridge.state == .off ? .secondary : .primary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Capsule().fill(bridge.state.tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(bridge.state.tint.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: Transport

    private var transportPicker: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                ForEach(Transport.allCases) { t in
                    Button {
                        bridge.transport = t
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: t.symbol).font(.system(size: 15))
                            Text(t.label).font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(bridge.transport == t ? Color.accentColor.opacity(0.16)
                                                            : Color.secondary.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(bridge.transport == t ? Color.accentColor.opacity(0.5)
                                                                    : .clear,
                                              lineWidth: 1)
                        )
                        .foregroundStyle(bridge.transport == t ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(bridge.transport.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: Device selection

    private var devicePickers: some View {
        VStack(spacing: 9) {
            Picker(selection: $bridge.selectedOutput) {
                Text("\(bridge.info.device_match) (automatic)").tag("")
                Divider()
                ForEach(bridge.info.outputs) { out in
                    Text(out.name).tag(out.uid)
                }
            } label: {
                Label("Output", systemImage: "headphones")
            }
            .pickerStyle(.menu)
            .disabled(!bridge.guardOutput)     // irrelevant when following system output

            // Only worth showing when the chosen transport leaves an actual
            // choice. Under "Wired" or "Wireless" the list is already narrowed to
            // one link, so it usually collapses to nothing.
            if bridge.availablePhones.count > 1 {
                Picker(selection: Binding(get: { bridge.effectiveSelectedPhone },
                                          set: { bridge.selectedPhone = $0 })) {
                    Text("Automatic").tag("")
                    Divider()
                    ForEach(bridge.availablePhones) { p in
                        Text(p.display).tag(p.serial)
                    }
                } label: {
                    Label("Phone", systemImage: "iphone")
                }
                .pickerStyle(.menu)
            }

            Divider()

            Toggle(isOn: $bridge.guardOutput) {
                HStack(spacing: 5) {
                    Text("Stop if the output changes")
                    Image(systemName: bridge.guardOutput ? "lock.fill" : "lock.open")
                        .foregroundStyle(bridge.guardOutput ? .green : .orange)
                }
                .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("On: the chosen device is made your system output, and playback stops within ~0.5s if that ever changes. Off: audio follows the system output wherever it goes, including the built-in speakers.")

            Text(bridge.guardOutput
                 ? "scrcpy plays to the system output and cannot be pinned, so this is a watchdog, and up to about 0.5 s of audio can reach another device if it drops mid-stream."
                 : "Audio will follow your system output, including the built-in speakers.")
                .font(.system(size: 10.5))
                .foregroundStyle(bridge.guardOutput ? Color.secondary.opacity(0.7) : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.secondary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5))
    }

    // MARK: Details

    private var details: some View {
        VStack(spacing: 0) {
            DetailRow(icon: "headphones", label: "Output",
                      value: bridge.outputDeviceName,
                      ok: bridge.outputAvailable)
            Divider().padding(.leading, 34)
            DetailRow(icon: "iphone", label: "Phone",
                      value: bridge.phoneDescription,
                      ok: bridge.info.phoneReachable)
            Divider().padding(.leading, 34)
            DetailRow(icon: "timer", label: "Buffer",
                      value: "\(bridge.effectiveBuffer) ms", ok: nil)
            Divider().padding(.leading, 34)
            DetailRow(icon: "waveform.path", label: "Est. latency",
                      value: "~\(bridge.estimatedLatencyMs) ms", ok: nil)
        }
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.secondary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5))
    }

    // MARK: Actions

    // The primary button always toggles on/off, but its label reflects what the
    // bridge is actually doing. "Turn Off" while it is visibly idle waiting for
    // a device reads as though something is wrong.
    private var actionLabel: String {
        guard bridge.enabled else { return "Turn On" }
        switch bridge.state {
        case .waiting:  return "Waiting for \(bridge.pinnedDeviceLabel)"
        case .starting: return "Connecting"
        default:        return "Turn Off"
        }
    }

    private var actionIcon: String {
        guard bridge.enabled else { return "play.fill" }
        switch bridge.state {
        case .waiting:  return "hourglass"
        case .starting: return "arrow.triangle.2.circlepath"
        default:        return "stop.fill"
        }
    }

    private var actionTint: Color {
        guard bridge.enabled else { return .accentColor }
        switch bridge.state {
        // Grey rather than yellow: a prominent yellow button renders white-on-
        // yellow, which is barely legible.
        case .waiting, .starting: return .gray
        default:                  return .red
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            // Never disabled: the app must always be usable, whatever is plugged in.
            Button {
                bridge.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: actionIcon)
                    Text(actionLabel)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(actionTint)
            .help(bridge.enabled ? "Click to turn the bridge off" : "Click to turn the bridge on")

            HStack {
                Button("Open Log") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: bridge.logPath))
                }
                .buttonStyle(.link)
                .font(.system(size: 11))

                Spacer()

                Text(bridge.state == .waiting
                     ? "Starts automatically when it connects"
                     : "Quitting stops playback")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Row

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    /// nil renders neutrally; true/false add a green or orange status dot.
    let ok: Bool?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if let ok {
                Circle()
                    .fill(ok ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)
            }
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject private var bridge: BridgeController
    @Environment(\.openWindow) private var openWindow

    private var menuActionLabel: String {
        guard bridge.enabled else { return "Turn On" }
        return bridge.state == .waiting ? "Turn Off (waiting)" : "Turn Off"
    }

    var body: some View {
        Text(bridge.statusText)

        Divider()

        ForEach(Transport.allCases) { t in
            Button {
                bridge.transport = t
            } label: {
                HStack {
                    Text(t.label)
                    if bridge.transport == t { Image(systemName: "checkmark") }
                }
            }
        }

        Divider()

        Button(menuActionLabel) { bridge.toggle() }
        Toggle("Only play to selected output", isOn: $bridge.guardOutput)
        Button("Open Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit Pixel Audio Bridge") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
