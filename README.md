<div align="center">

<img src="docs/assets/icon.png" width="104" alt="">

# Pixel Audio Bridge

### Hear your phone through your Mac's headphones.

[![build](https://github.com/nicglazkov/pixel-audio-bridge/actions/workflows/build.yml/badge.svg)](https://github.com/nicglazkov/pixel-audio-bridge/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/licence-MIT-5B3FE0)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-6E7689)
![191 ms wired](https://img.shields.io/badge/latency-191%20ms%20wired-0F8A57)

**[Website](https://nicglazkov.github.io/pixel-audio-bridge/)** ·
[Behaviour](#what-happens-when) ·
[Latency](#where-the-191-milliseconds-go) ·
[Privacy](PRIVACY.md)

<img src="docs/assets/app-streaming.png" width="380" alt="The Pixel Audio Bridge window, streaming from a Pixel 6 Pro over Wi-Fi">

</div>

---

AirPods Max can only hold one connection at a time. Instead of unpairing them
from your Mac every time your phone plays something, this brings the phone's
audio across.

You can't do it over Bluetooth. macOS implements the A2DP **source** role only —
it has no **sink** — so a Mac can never appear in a phone's Bluetooth output list
as a speaker. The audio travels over ADB instead, by USB cable or Wi-Fi.

## What you need

| | | |
|---|---|---|
| **Your Mac** | macOS 14+ | Apple silicon or Intel |
| **Your phone** | Android 11+ | USB debugging enabled |
| **Also needs** | `scrcpy` + `adb` | Both free, both on Homebrew |
| **Costs** | Nothing | MIT, built from source |

## Install

```sh
brew install scrcpy
git clone https://github.com/nicglazkov/pixel-audio-bridge.git
cd pixel-audio-bridge && ./build.sh
open build/PixelAudioBridge.app
```

`adb` comes from the Android SDK. If you have Android Studio it's already at
`~/Library/Android/sdk/platform-tools`; otherwise install
[platform-tools](https://developer.android.com/tools/releases/platform-tools).

Plug the phone in and accept the debugging prompt. For wireless, run
`./bin/pab enable-wireless` once while it's plugged in.

Because you build it yourself there's nothing to notarize and no Gatekeeper
prompt to work around.

## What happens when…

You never start this, stop it, or switch it over. It reacts:

| Situation | What the app does | |
|---|---|---|
| You put your headphones on | Audio starts by itself, within a second | checks the output device twice a second |
| You take your headphones off | Goes quiet and waits; your phone takes its audio back | returns to streaming when they reconnect |
| You unplug the USB cable | Moves to Wi-Fi mid-session | buffer widens 15 ms → 200 ms |
| Your Mac switches to another output | **Playback halts instead of following it** | watchdog responds in ≤ 500 ms |
| Your phone falls asleep | Backs off and waits rather than hammering it | retries at 3 s, 6 s, 9 s, then idles |
| You quit the app | Every child process is torn down | no daemon, no login item |

## Where the 191 milliseconds go

Every figure here was measured on real hardware.

| Stage | Wired | |
|---|---|---|
| Capture buffer | 15 ms | tunable |
| Output buffer | 5 ms | tunable |
| **Bluetooth, inside the headphones** | **170.7 ms** | **fixed — 89% of the budget** |
| **Total** | **191 ms** | |

That last row is not ours to fix. No setting on either machine changes it, so
everything this software controls is the other twenty milliseconds. Over Wi-Fi
the buffer grows to 200 ms and the total reaches 376 ms — fine for music,
noticeable on video.

<details>
<summary>How each number was obtained</summary>

| Quantity | Value | Method |
|---|---|---|
| Mac → AirPods Max, Bluetooth | 170.7 ms | CoreAudio reported device latency |
| Wi-Fi jitter to phone | 6–21 ms, σ 3.6 | 20 ping packets |
| Wi-Fi buffer floor | 200 ms | 50 ms → 4 skips · 150 ms → clean, clean, **29 skips** · 200 ms → clean ×3 |
| Wired buffer | 15 ms | chosen for a jitter-free link; validated by listening, not instrumented |

**The 15 ms wired buffer is the one figure that is not instrumented.** scrcpy's
own default is 50 ms. If you hear clicks or brief dropouts, that's sample
skipping — raise it with `--buffer`. It sounds like glitches, not lag.

</details>

## How it works

One process. scrcpy captures the phone's audio and plays it itself, through SDL,
to the macOS default output device:

```
scrcpy --no-video --no-window --no-control
       --audio-source=playback --audio-buffer=N --audio-output-buffer=5
```

**`--audio-source=playback`** uses Android's `AudioPlaybackCapture`, which taps
each app's PCM *before* stream volume is applied — so the phone's volume slider
is irrelevant. The alternative, `--audio-source=output` (`REMOTE_SUBMIX`),
captures post-volume and records silence whenever the phone's media stream is
muted. Apps can opt out of `playback`; Instagram does not, Spotify does.

**`--no-window`** stops SDL registering scrcpy as a GUI application. Without it,
scrcpy appears in the Dock and app switcher despite having nothing to display.
Audio playback still works with it.

**No intermediate player.** An earlier design piped Opus into
`mpv --audio-device=<UID>`, which could pin an output device and refuse to fall
back. It was dropped for latency: mpv's `--audio-buffer` defaults to 0.2 s, and
even tuned, the extra encode → mux → pipe → demux → decode stage costs ~10 ms.

### The output watchdog

scrcpy plays to the default output and **cannot be told to use a specific
device**. So "Stop if the output changes" is a watchdog, not a pin:

1. On start, the chosen device is made the macOS default output. If that fails,
   the bridge refuses to start.
2. While running, the default output is polled twice a second. If it stops being
   the chosen device, scrcpy's process group is killed.

**Exposure is up to ~0.5 s, not zero.** If your headphones disconnect
mid-stream, macOS reassigns default output to the built-in speakers, and up to
half a second of audio can reach them before the watchdog fires.

Setting the default device is verified by reading the property back rather than
trusting the return code — CoreAudio returns `noErr` for devices that then
refuse to become default, and at least one popular tool reports success in that
case.

Note also that AirPods Max can be *Bluetooth-connected yet absent from CoreAudio*
when idle in standby. Presence is judged by CoreAudio enumeration, never by the
Bluetooth connected list.

## CLI

The app is a wrapper around `bin/pab`, which works standalone:

```sh
pab run [--wired|--wireless]   # stream; blocks until stopped
       [--buffer MS]           # override the buffer
       [--device UID]          # output device; made the system default
       [--serial S]            # which phone
       [--no-guard]            # no device check, no watchdog
pab stop | status | info | doctor | enable-wireless
```

`pab doctor` is the place to start when something is wrong — it reports
dependencies, output devices, adb transports and config in one go.

## Configuration

`~/.config/pixel-audio-bridge/config`

```sh
AIRPODS_MATCH="AirPods Max"   # substring matched against output device names
PHONE_IP="..."                # learned automatically over USB
OUTPUT_UID=""                 # pin a specific CoreAudio device
PHONE_SERIAL=""               # pin a specific phone
```

`AIRPODS_MATCH` is just a name filter — set it to any output device you own.

## Limitations

- **Phone calls won't capture.** Android blocks `USAGE_VOICE_COMMUNICATION` from
  playback capture, and there's no return mic path.
- **Video on the phone leads the audio.** The phone doesn't know its audio was
  captured, so it never delays video to compensate. Mirroring video through
  scrcpy would sync both, at the cost of watching on the Mac.
- **Wireless ADB resets when the phone reboots** and must be re-enabled over USB.
- **Some apps opt out** of `AudioPlaybackCapture` and will be silent.

## Tests

```sh
./tests/run.sh    # 78 tests, no phone or audio hardware required
```

`adb`, `paboutput` and `scrcpy` are replaced with fakes on `PATH`, and the UI
logic lives in `BridgeLogic`, free of `UserDefaults`, timers and processes. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Privacy and security

No accounts, no telemetry, no network calls to anyone but your own phone. The
website loads nothing from third parties — fonts are self-hosted for exactly
that reason. See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Built with

[scrcpy](https://github.com/Genymobile/scrcpy) does the capture and playback.
This project is the macOS front end, the device logic, and the watchdog. See
[NOTICE](NOTICE) for attribution.

## Licence

MIT — see [LICENSE](LICENSE).
