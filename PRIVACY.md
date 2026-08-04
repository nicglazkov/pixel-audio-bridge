# Privacy Policy

**Last updated: 1 August 2026**

Pixel Audio Bridge is a local utility. It has no backend, no account system, and
no analytics. This document describes exactly what it touches, and is written to
be checkable, so every claim here can be verified against the source in this
repository.

## The short version

The app collects nothing and talks only to your own phone, unless you switch on
the optional update check. The website sets no cookies and loads nothing from
third parties.

## What the app does with data

### Audio

Audio captured from your phone is played through your Mac's output device and
then discarded. **It is never written to disk, buffered to a file, or
transmitted anywhere.** The capture is performed by
[scrcpy](https://github.com/Genymobile/scrcpy) and reaches your speakers through
CoreAudio; nothing in between retains it.

### Network activity

The app makes **no requests to any server operated by the author**. There is no
crash reporting, no telemetry, and no licence or activation call. It has no
backend to talk to.

There is exactly one request it can ever make to a third party, and it does not
make it unless you say so.

**The update check is off until you turn it on.** On first launch the app asks
whether it may check for updates. Until you answer, and permanently if you
decline, it contacts nothing. If you accept, once a day it asks GitHub's release
API whether a newer version exists. The request carries no identifier, no device
information and no usage data, and the reply is a version number. GitHub will see
your IP address, as it would if you visited the releases page yourself. You can
change your mind at any time.

Everything else it causes is between your Mac and your own phone:

| Path | When | Contents |
|---|---|---|
| USB cable, via `adb` | Wired mode | Audio stream from your phone |
| Your local network, via `adb` over TCP | Wireless mode | Audio stream from your phone |

Wireless mode connects to a private address on your own network, typically
something like `192.168.x.x:5555`. That traffic does not leave your network.

### What is stored on your Mac

| Location | Contents | Why |
|---|---|---|
| `~/.config/pixel-audio-bridge/config` | Your phone's last known local IP, the name filter used to match your output device, optional pinned device and phone identifiers | So wireless mode works without you looking up an address |
| macOS user defaults, under `com.glazkov.pixel-audio-bridge` | Whether the bridge is enabled, chosen transport, output and phone selections, watchdog setting, window position | To restore your preferences between launches |
| `$TMPDIR/pixel-audio-bridge/bridge.log` | Diagnostic output from the current session, including device names and adb serials | So `pab doctor` and the "Open Log" button can help when something breaks |

All three are plain files on your machine. Nothing is uploaded. Delete them and
the app rebuilds what it needs.

### What it can see about your devices

To function, the app reads your connected audio output devices (names and
CoreAudio identifiers) and your connected Android devices (adb serials, and the
phone's model name and Wi-Fi address). This information stays on your Mac and
appears only in the app's own interface and log.

## A security note about ADB

Wireless mode requires Android Debug Bridge over TCP, which you enable with
`pab enable-wireless`. **While wireless debugging is on, any device on the same
network that can reach your phone may attempt to connect to it**, subject to
Android's authorisation prompt. This is a property of ADB itself, not of this
app.

It resets whenever your phone reboots. If that concerns you, use the USB cable,
which is also the lower-latency option.

## The website

This site is a set of static files served by GitHub Pages.

- **No cookies.** None are set, for any purpose.
- **No analytics.** There is no tracking script of any kind.
- **No third-party requests.** Fonts are self-hosted in this repository rather
  than loaded from a font CDN, specifically so that visiting the site does not
  disclose your IP address to anyone else.
- **Local storage** is used for exactly one thing: remembering whether you chose
  light or dark mode. It never leaves your browser.

**One thing outside our control:** the site is hosted on GitHub Pages, and
GitHub receives standard web-server information when you visit, including your
IP address and user agent. That is GitHub's processing, under
[GitHub's Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-privacy-statement).
We neither receive nor have access to it.

## Children

This is a developer utility with no accounts and no data collection. It is not
directed at children and collects no information from anyone.

## Changes

Any change to this policy will appear in this file, with the date above updated
and the change visible in the repository's git history.

## Contact

Open an issue at
[github.com/nicglazkov/pixel-audio-bridge/issues](https://github.com/nicglazkov/pixel-audio-bridge/issues).
For security matters, see [SECURITY.md](SECURITY.md).
