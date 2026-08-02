<div align="center">

<img src="docs/assets/icon.png" width="112" alt="">

<h1>Pixel Audio Bridge</h1>

<p><strong>Hear your phone through your Mac's headphones.</strong></p>

[![build](https://github.com/nicglazkov/pixel-audio-bridge/actions/workflows/build.yml/badge.svg)](https://github.com/nicglazkov/pixel-audio-bridge/actions/workflows/build.yml)
[![licence: MIT](https://img.shields.io/badge/licence-MIT-5B3FE0)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-6E7689)](#what-you-need)
[![latency: 191 ms wired](https://img.shields.io/badge/latency-191%20ms%20wired-0F8A57)](#where-the-191-milliseconds-go)
[![tests: 78](https://img.shields.io/badge/tests-78-6E7689)](#tests)

<a href="https://nicglazkov.github.io/pixel-audio-bridge/"><strong>Website</strong></a> &nbsp;
<a href="#quick-start">Quick start</a> &nbsp;
<a href="#how-it-reacts">Behaviour</a> &nbsp;
<a href="#where-the-191-milliseconds-go">Latency</a> &nbsp;
<a href="#troubleshooting">Troubleshooting</a>

<br>

<img src="docs/assets/app-streaming.png" width="360" alt="The Pixel Audio Bridge window, streaming from a Pixel 6 Pro over Wi-Fi">

</div>

---

Plays your Android phone's audio out of whatever your Mac is already playing to.
Put your headphones on and it starts by itself. Take them off and it stops. There
is nothing to press.

## Why this exists

Most good headphones hold one Bluetooth connection at a time. AirPods Max are the
obvious example: using them with your phone means unpairing them from your Mac,
and using them with your Mac again means pairing them back. Doing that a dozen
times a day is miserable.

The obvious fix does not exist. **macOS implements the Bluetooth A2DP source role
only and has no sink**, so your Mac can never appear in a phone's Bluetooth output
list as a speaker. No setting changes this, on any macOS version.

So this moves the audio instead of the headphones. The phone's audio travels over
ADB, by USB cable or over your own network, and comes out of whatever your Mac is
already playing to.

## What you need

| | | |
|---|---|---|
| **Your Mac** | macOS 14 or newer | Apple silicon or Intel |
| **Your phone** | Android 11 or newer | USB debugging enabled |
| **Your output** | Any device | Headphones, a USB DAC, or speakers |
| **Also needs** | `scrcpy` and `adb` | Both free, both on Homebrew |

## Quick start

```sh
brew install scrcpy
git clone https://github.com/nicglazkov/pixel-audio-bridge.git
cd pixel-audio-bridge && ./build.sh
open build/PixelAudioBridge.app
```

`adb` comes from the Android SDK. If you have Android Studio it is already at
`~/Library/Android/sdk/platform-tools`; otherwise install
[platform-tools](https://developer.android.com/tools/releases/platform-tools).

Plug the phone in and accept the debugging prompt. For wireless, run
`./bin/pab enable-wireless` once while it is plugged in.

Because you build it yourself there is nothing to notarize and no Gatekeeper
prompt to work around.

## How it reacts

You never start this, stop it, or switch it over.

| Situation | What the app does |
|---|---|
| You put your headphones on | Audio starts by itself, within about a second |
| You take your headphones off | Goes quiet and waits, then resumes when they return |
| You unplug the USB cable | Moves to Wi-Fi mid-session and widens the buffer |
| Your Mac switches to another output | **Playback halts instead of following it** |
| Your phone falls asleep | Backs off, retries at 3, 6 and 9 seconds, then idles |
| You quit the app | Every child process is torn down, nothing left running |

Closing the window does not stop playback. The app lives in the menu bar, and
quitting is what stops it.

## Where the 191 milliseconds go

Every figure here was measured on real hardware.

| Link | Capture buffer | Output | Bluetooth | Total |
|---|---|---|---|---|
| **Wired, over USB** | 15 ms | 5 ms | 170.7 ms | **191 ms** |
| **Wireless, over Wi-Fi** | 200 ms | 5 ms | 170.7 ms | **376 ms** |

The Bluetooth figure is identical in both rows because it happens inside the
headphones, not on your Mac. It is 89% of the wired budget and no setting on
either machine changes it, so everything this software controls is the twenty
milliseconds beside it.

That figure was measured with AirPods Max. Other Bluetooth headphones differ, and
a wired output device or a USB DAC skips the stage almost entirely.

<details>
<summary><strong>How each number was obtained</strong></summary>

<br>

| Quantity | Value | Method |
|---|---|---|
| Mac to AirPods Max, Bluetooth | 170.7 ms | CoreAudio reported device latency |
| Wi-Fi jitter to the phone | 6 to 21 ms, sigma 3.6 | 20 ping packets |
| Wi-Fi buffer floor | 200 ms | 50 ms gave 4 sample skips in 15 s. 150 ms ran clean twice, then lost 514 ms of audio on the third run. 200 ms was clean three times |
| Wired buffer | 15 ms | Chosen for a jitter-free link and validated by listening |

**The 15 ms wired buffer is the one figure that is not instrumented.** scrcpy's
own default is 50 ms. If you hear clicks or brief dropouts that is sample
skipping, so raise it with `--buffer`. It sounds like glitches, not lag.

</details>

## How it works

One process. scrcpy captures the phone's audio and plays it itself, through SDL,
to the macOS default output device:

```
scrcpy --no-video --no-window --no-control \
       --audio-source=playback --audio-buffer=N --audio-output-buffer=5
```

Three details carry most of the weight:

**`--audio-source=playback`** uses Android's `AudioPlaybackCapture`, which taps
each app's PCM *before* stream volume is applied, so the phone's volume slider is
irrelevant. The alternative, `--audio-source=output` (`REMOTE_SUBMIX`), captures
post-volume and records silence whenever the phone's media stream is muted. Apps
can opt out of `playback`: Instagram does not, Spotify does.

**`--no-window`** stops SDL registering scrcpy as a GUI application. Without it,
scrcpy appears in the Dock and the app switcher despite having nothing to display.
Audio playback still works with it.

**No intermediate player.** An earlier design piped Opus into
`mpv --audio-device=<UID>`, which could pin an output device and refuse to fall
back. It was dropped for latency: mpv's `--audio-buffer` defaults to 0.2 s, and
even correctly tuned the extra encode, mux, pipe, demux and decode stages cost
about 10 ms.

### The output watchdog

scrcpy plays to the default output and **cannot be told to use a specific
device**. So "Stop if the output changes" is a watchdog, not a pin:

1. On start, the chosen device is made the macOS default output. If that fails,
   the bridge refuses to start.
2. While running, the default output is polled twice a second. If it stops being
   the chosen device, scrcpy's process group is killed.

**Exposure is up to about half a second, not zero.** If your headphones
disconnect mid-stream, macOS reassigns default output to the built-in speakers,
and audio can reach them before the watchdog fires.

Setting the default device is verified by reading the property back rather than
trusting the return code, because CoreAudio returns `noErr` for devices that then
refuse to become default. At least one widely used tool reports success in that
case.

One more thing worth knowing: **AirPods Max can be Bluetooth-connected yet absent
from CoreAudio** when idle in standby. Presence is therefore judged by CoreAudio
enumeration, never by the Bluetooth connected list.

## Command line

The app is a wrapper around `bin/pab`, which works standalone.

```sh
pab run [--wired | --wireless]   # stream; blocks until stopped
        [--buffer MS]            # override the buffer
        [--device UID]           # output device, made the system default
        [--serial S]             # which phone
        [--no-guard]             # no device check, no watchdog
pab stop                         # tear down a running bridge
pab status                       # running or stopped
pab info                         # machine-readable state, JSON
pab doctor                       # dependencies, devices, transports, config
pab enable-wireless              # enable wireless ADB; needs USB once
```

## Configuration

`~/.config/pixel-audio-bridge/config`

```sh
AIRPODS_MATCH="AirPods Max"   # substring matched against output device names
PHONE_IP=""                   # learned automatically over USB
OUTPUT_UID=""                 # pin a specific CoreAudio device
PHONE_SERIAL=""               # pin a specific phone
```

`AIRPODS_MATCH` is only a name filter. Set it to any output device you own.

> [!WARNING]
> This file is read with `source`, so anyone who can write it can execute code as
> you. It lives in your home directory under your own permissions. Treat it the
> way you treat `~/.zshrc`.

## Troubleshooting

**Start with `./bin/pab doctor`.** It reports dependencies, output devices, adb
transports and config in one pass, and answers most questions before you have to
ask them.

<details>
<summary><strong>Nothing happens when I put my headphones on</strong></summary>

<br>

The app judges presence by CoreAudio, not Bluetooth. AirPods Max can show as
connected in Bluetooth while being absent from CoreAudio in standby, and the
bridge will correctly wait rather than fail.

Check what the app can actually see:

```sh
./bin/pab doctor | grep -A6 "output devices"
```

If your device is not listed there, play any sound on your Mac to wake it.

</details>

<details>
<summary><strong>It streams, but there is no sound</strong></summary>

<br>

Almost always the app on the phone opting out of capture. Android lets an app set
`allowAudioPlaybackCapture="false"` or flag its audio as DRM-protected, and
capture then returns silence with no error. Spotify does this. Instagram does not.

Try a different app on the phone. If everything is silent, check that the phone's
media stream is not muted, then look at the log for a warning about a persistently
low capture level.

</details>

<details>
<summary><strong>I hear clicks, pops or brief dropouts</strong></summary>

<br>

That is sample skipping, which means the buffer is too small for the link. Raise
it:

```sh
./bin/pab run --wired --buffer 30
```

The wired default of 15 ms is below scrcpy's own default of 50 ms and is the one
figure in this project validated by listening rather than instrumentation. If 30
fixes it, keep it.

Glitches and lag are different symptoms. Lag means the buffer is doing its job;
clicks mean it is too tight.

</details>

<details>
<summary><strong>Wireless stopped working</strong></summary>

<br>

Wireless ADB resets whenever the phone reboots. Plug in over USB and run:

```sh
./bin/pab enable-wireless
```

If the phone is awake and on the same network but still unreachable, its Wi-Fi
address may have changed. The address is relearned automatically the next time you
connect over USB.

</details>

<details>
<summary><strong>Audio briefly came out of my speakers</strong></summary>

<br>

Expected, and documented. The watchdog polls the default output twice a second, so
a mid-stream disconnect leaves a window of up to about half a second before
playback is killed. scrcpy cannot target a specific output device, which is why
this is a watchdog rather than a pin.

</details>

<details>
<summary><strong>The video on my phone is ahead of the audio</strong></summary>

<br>

The phone does not know its audio was captured, so it never delays video to
compensate. Over USB the offset is about 191 ms; over Wi-Fi it is about 376 ms and
clearly visible.

Use the cable for anything you are watching. Mirroring the video through scrcpy
would keep both in sync, but that routes audio through scrcpy's own window and
gives up the output watchdog.

</details>

## Limitations

- **Phone calls will not capture.** Android blocks `USAGE_VOICE_COMMUNICATION`
  from playback capture, and there is no return mic path.
- **Some apps opt out** of `AudioPlaybackCapture` and will be silent.
- **Video on the phone leads the audio**, because the phone cannot know to
  compensate.
- **Wireless ADB resets on reboot** and must be re-enabled over USB.
- **The watchdog is not instantaneous.** Up to about half a second of exposure on
  a mid-stream output change.

## Tests

```sh
./tests/run.sh
```

78 tests, none of which need a phone, headphones or any audio hardware. `adb`,
`paboutput` and `scrcpy` are replaced with fakes on `PATH`, and the UI logic lives
in `BridgeLogic`, free of `UserDefaults`, timers and processes so it can be called
directly.

The suite covers device selection, transport resolution, buffer choice, the
refusal paths, and the JSON contract between the shell and the app. That contract
has broken silently before, which is why it has its own tests.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for layout, the test approach, and the
short list of changes that will get pushed back on. In brief: bridge logic stays
in `bin/pab`, the app stays a supervisor over it, no network calls, and no latency
figure that has not been measured.

## Privacy and security

No accounts, no telemetry, and no network calls to anyone but your own phone. The
website loads nothing from third parties, and its fonts are self-hosted for
exactly that reason.

- [Privacy policy](https://nicglazkov.github.io/pixel-audio-bridge/privacy.html)
  ([PRIVACY.md](PRIVACY.md))
- [Security policy and threat model](https://nicglazkov.github.io/pixel-audio-bridge/security.html)
  ([SECURITY.md](SECURITY.md))

Please report vulnerabilities privately rather than as a public issue.

## Built with

[scrcpy](https://github.com/Genymobile/scrcpy) by Romain Vimont and Genymobile
does the capture and the playback, and this project would not exist without it.
Pixel Audio Bridge is the macOS front end, the device logic, and the watchdog.

See [NOTICE](NOTICE) for third-party attribution.

## Licence

MIT. See [LICENSE](LICENSE).
