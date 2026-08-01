<div align="center">

<img src="docs/assets/icon.png" width="128" alt="Pixel Audio Bridge">

# Pixel Audio Bridge

**Listen to your Android phone through headphones connected to your Mac.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey)
![Latency: ~191 ms wired](https://img.shields.io/badge/Latency-~191%20ms%20wired-brightgreen)

[Website](https://nicglazkov.github.io/pixel-audio-bridge/) · [How it works](#how-it-works) · [Measurements](#measured-numbers)

</div>

---

AirPods Max have no Bluetooth multipoint. Using them with your phone means
disconnecting them from your Mac, and connecting them back afterwards. This
routes the phone's audio to the Mac instead, so the headphones never move.

Launch the app and audio flows. Quit it and it stops.

## The catch nobody mentions

You cannot do this over Bluetooth. macOS implements the A2DP **source** role
only — it has no **sink**. Your Mac will never appear in a phone's Bluetooth
output list as a speaker, and no setting changes that.

So the audio travels over ADB instead, by USB cable or Wi-Fi.

## Install

```sh
brew install scrcpy
git clone https://github.com/nicglazkov/pixel-audio-bridge.git
cd pixel-audio-bridge
./build.sh
open build/PixelAudioBridge.app
```

You also need `adb`. If you have Android Studio it is already at
`~/Library/Android/sdk/platform-tools`; otherwise install
[platform-tools](https://developer.android.com/tools/releases/platform-tools).

Enable USB debugging on the phone, plug it in, and accept the prompt. For
wireless, run `./bin/pab enable-wireless` once while plugged in.

Because you build it yourself, there is nothing to notarize and no Gatekeeper
prompt to work around.

## Use

| Link | Buffer | Total latency |
|---|---|---|
| **Wired (USB)** | 15 ms | **~191 ms** |
| **Wireless (Wi-Fi)** | 200 ms | ~376 ms |

Pick Automatic, Wired, or Wireless. Automatic uses USB when the phone is plugged
in and Wi-Fi otherwise. Closing the window keeps playback running; the app lives
in the menu bar. Quitting stops everything.

If the headphones are not connected yet, the app waits and starts on its own the
moment they appear. Take them off mid-stream and it goes back to waiting.

## How it works

One process. scrcpy captures the phone's audio and plays it itself, through SDL,
to the macOS default output device:

```
scrcpy --no-video --no-window --no-control
       --audio-source=playback --audio-buffer=N --audio-output-buffer=5
```

Three details matter:

**`--audio-source=playback`** uses Android's `AudioPlaybackCapture`, which taps
each app's PCM *before* stream volume is applied — so the phone's volume slider
is irrelevant. The alternative, `--audio-source=output` (`REMOTE_SUBMIX`),
captures post-volume and records silence whenever the phone's media stream is
muted. Apps can opt out of `playback`; Instagram does not, Spotify does.

**`--no-window`** stops SDL registering scrcpy as a GUI application. Without it
scrcpy appears in the Dock and app switcher despite having nothing to display.
Audio playback still works with it.

**No intermediate player.** An earlier design piped Opus into
`mpv --audio-device=<UID>`, which could pin an output device and refuse to fall
back — a hard guarantee that audio could never reach the speakers. It was
dropped because mpv's `--audio-buffer` defaults to **0.2 s**, and even tuned, the
extra encode → mux → pipe → demux → decode stage costs ~10 ms.

## The output watchdog

scrcpy plays to the default output and **cannot be told to use a specific
device**. So "Stop if the output changes" is a watchdog, not a pin:

1. On start, the chosen device is made the macOS default output. If that fails,
   the bridge refuses to start.
2. While running, the default output is polled twice a second. If it stops being
   the chosen device, scrcpy's process group is killed.

**Exposure is up to ~0.5 s, not zero.** If the headphones disconnect mid-stream,
macOS reassigns default output to the built-in speakers and up to half a second
of audio can play there before the watchdog fires.

Setting the default device is verified by reading the property back rather than
trusting the return code — CoreAudio returns `noErr` for devices that then refuse
to become default, and at least one popular tool reports success in that case.

## Measured numbers

Everything here was measured on real hardware, not estimated.

| Quantity | Value | Method |
|---|---|---|
| Mac → AirPods Max over Bluetooth | **170.7 ms** | CoreAudio reported device latency |
| Wi-Fi jitter to phone | 6–21 ms, σ 3.6 | `ping`, 20 packets |
| Wi-Fi buffer floor | **200 ms** | 50 ms → 4 skips · 150 ms → clean, clean, **29 skips** · 200 ms → clean ×3 |
| mpv default audio buffer | 200 ms | 9600-sample soft buffer |

The Bluetooth hop is ~89% of the wired budget and cannot be reduced by any
software setting. Getting meaningfully below ~190 ms needs a wired output device.

> **The 15 ms USB buffer is not instrumented.** scrcpy's own default is 50 ms; 15
> was chosen for minimum latency on a jitter-free link and validated by listening,
> not by counting sample-skips. If you hear clicks or brief dropouts, that is
> sample-skipping — raise it with `--buffer`. It sounds like glitches, not lag.

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

`pab doctor` is the place to start when something is wrong.

## Limitations

- **Phone calls will not capture.** Android blocks `USAGE_VOICE_COMMUNICATION`
  from playback capture, and there is no return mic path.
- **Video on the phone leads the audio.** The phone does not know its audio was
  captured, so it never delays video to compensate. Mirroring video through
  scrcpy would sync both, at the cost of watching on the Mac.
- **Wireless ADB resets when the phone reboots** and must be re-enabled over USB.
- **Not every app can be captured.** Apps may opt out of `AudioPlaybackCapture`.

## Configuration

`~/.config/pixel-audio-bridge/config`

```sh
AIRPODS_MATCH="AirPods Max"   # substring matched against output device names
PHONE_IP="..."                # learned automatically over USB
OUTPUT_UID=""                 # pin a specific CoreAudio device
PHONE_SERIAL=""               # pin a specific phone
```

`AIRPODS_MATCH` is just a name filter — set it to any output device you own.

## Built with

[scrcpy](https://github.com/Genymobile/scrcpy) does the capture and playback.
This project is the macOS front end, the device logic, and the watchdog.

## License

MIT — see [LICENSE](LICENSE).
