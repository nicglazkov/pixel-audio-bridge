<div align="center">

<img src="docs/assets/icon.png" width="104" alt="">

<h1>Pixel Audio Bridge</h1>

<p><strong>Hear your phone through your Mac's headphones.</strong><br>
<sub>Put them on and it starts by itself. Take them off and it stops.</sub></p>

[![build](https://github.com/nicglazkov/pixel-audio-bridge/actions/workflows/build.yml/badge.svg)](https://github.com/nicglazkov/pixel-audio-bridge/actions/workflows/build.yml)
[![licence: MIT](https://img.shields.io/badge/licence-MIT-5B3FE0)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-6E7689)](#what-you-need)
[![191 ms wired](https://img.shields.io/badge/latency-191%20ms%20wired-0F8A57)](https://nicglazkov.github.io/pixel-audio-bridge/how-it-works.html#measurements)
[![tests: 78](https://img.shields.io/badge/tests-78-6E7689)](#tests)
[![notarized](https://img.shields.io/badge/signed-notarized%20by%20Apple-0F8A57)](#install)

<br>

<img src="docs/assets/app-streaming.png" width="340" alt="The Pixel Audio Bridge window, streaming from a Pixel 6 Pro">

</div>

---

Most good headphones hold one Bluetooth connection at a time, so using them with
your phone means unpairing them from your Mac and pairing them back afterwards.

You cannot fix that with Bluetooth. **macOS has no A2DP sink**, so a Mac can never
appear in a phone's output list as a speaker. This moves the audio instead: over
USB or your own network, out of whatever your Mac is already playing to.

## What you need

|  |  |  |
|---|---|---|
| **Mac** | macOS 14+ | Apple silicon or Intel |
| **Phone** | Android 11+ | USB debugging enabled |
| **Output** | Any device | Headphones, a USB DAC, or speakers |
| **Tools** | `scrcpy` and `adb` | Both free, both on Homebrew |
| **Install** | Homebrew or DMG | Signed and notarized, universal |

## Install

```sh
brew install --cask nicglazkov/tap/pixel-audio-bridge
brew install --cask android-platform-tools   # skip if you have Android Studio
```

Two commands. The first brings the app, `scrcpy` and the `pab` command; the
second brings `adb`, which is only missing if you do not already have the
Android SDK. The app checks for both on launch and tells you if either is
absent, so there is nothing to get wrong.

Or download **[PixelAudioBridge.dmg](https://github.com/nicglazkov/pixel-audio-bridge/releases/latest/download/PixelAudioBridge.dmg)**
and drag it to Applications.

Opens like any other Mac app. Apple has checked it for malware, so macOS will
not warn you or block it. Universal, so it runs on Apple silicon and Intel.

Already have Android Studio? `adb` is at `~/Library/Android/sdk/platform-tools`
and the app finds it there, so skip the second command.

Your phone needs three settings changed before any of this works: unlock
Developer options, turn on USB debugging, then approve this Mac when it asks.
There is no route that skips it, because the bridge reaches your phone through
`adb`. [The getting started guide](https://nicglazkov.github.io/pixel-audio-bridge/getting-started.html) walks both routes with a picture of every screen you need to find.

No cable at all? **`pab pair`** does the whole Wi-Fi pairing. It finds the phone
on your network, asks only for the six digit code the phone shows, and looks up
the separate port it has to connect on, so the two are never mixed up. With a
cable already attached, `pab enable-wireless` is quicker.

<details>
<summary><strong>Build from source instead</strong></summary>

<br>

```sh
brew install scrcpy
git clone https://github.com/nicglazkov/pixel-audio-bridge.git
cd pixel-audio-bridge && ./build.sh
open build/PixelAudioBridge.app
```

`./build.sh` produces a universal binary signed ad hoc, which is fine for your
own machine. `SIGN=developer ./build.sh` signs with a Developer ID under
hardened runtime, and `./release.sh` runs the full notarized release pipeline.

</details>

## How it reacts

| When | It does |
|---|---|
| You put your headphones on | Starts by itself, within about a second |
| You take them off | Goes quiet and waits, then resumes when they return |
| You unplug the cable | Moves to Wi-Fi and widens the buffer |
| Your Mac's output changes | **Halts instead of following it** |
| You quit the app | Tears down every child process |

Closing the window does not stop playback. The app lives in the menu bar.

## Latency

| Link | Buffer | Bluetooth | Total |
|---|---|---|---|
| **Wired, USB** | 15 ms | 170.7 ms | **191 ms** |
| **Wireless, Wi-Fi** | 200 ms | 170.7 ms | **376 ms** |

The Bluetooth figure is identical in both because it happens inside the
headphones. It is 89% of the wired budget and nothing on either machine changes
it, so everything this software controls is the twenty milliseconds beside it.

Measured with AirPods Max. A wired output device skips that stage almost
entirely. [How each number was measured](https://nicglazkov.github.io/pixel-audio-bridge/how-it-works.html#measurements)

## Commands

```sh
pab run [--wired|--wireless] [--buffer MS] [--device UID] [--serial S]
pab pair                      # pair over Wi-Fi, no cable needed
pab stop | status | info | doctor | enable-wireless
```

`pab doctor` reports dependencies, devices, transports and config in one pass.
Start there when something is wrong.

Homebrew puts `pab` on your PATH. If you installed from the disk image instead,
it lives inside the app:

```sh
/Applications/PixelAudioBridge.app/Contents/Resources/pab doctor
```

## Documentation

| | |
|---|---|
| [**Getting started**](https://nicglazkov.github.io/pixel-audio-bridge/getting-started.html) | Setting the phone up, step by step, with or without a cable |
| [**How it works**](https://nicglazkov.github.io/pixel-audio-bridge/how-it-works.html) | The internals, the watchdog, and how every number was measured |
| [**Troubleshooting**](https://nicglazkov.github.io/pixel-audio-bridge/troubleshooting.html) | No sound, clicks, wireless resets, and the rest |
| [**Privacy**](https://nicglazkov.github.io/pixel-audio-bridge/privacy.html) | What is stored, and what leaves your machine. Nothing does |
| [**Security**](https://nicglazkov.github.io/pixel-audio-bridge/security.html) | Threat model, accepted risks, and how to report a vulnerability |
| [**Contributing**](CONTRIBUTING.md) | Layout, tests, and what will get pushed back on |

## Limitations

- Phone calls cannot be captured. Android blocks it, and there is no mic path back.
- Some apps opt out of audio capture and will be silent. Spotify does; Instagram does not.
- Video on the phone leads the audio, because the phone cannot know to compensate.
- The output watchdog takes up to about half a second, so it is not a hard guarantee.

## Tests

```sh
./tests/run.sh
```

78 tests, none needing a phone, headphones or any audio hardware.

## Built with

[scrcpy](https://github.com/Genymobile/scrcpy) does the capture and playback, and
this would not exist without it. See [NOTICE](NOTICE) for attribution.

MIT licensed. See [LICENSE](LICENSE).
