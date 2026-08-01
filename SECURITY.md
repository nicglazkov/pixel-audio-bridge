# Security Policy

## Supported versions

This is a single-developer project. Security fixes land on `main`, and only the
most recent release is supported.

| Version | Supported |
|---|---|
| 1.0.x | Yes |
| < 1.0 | No |

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private reporting instead:
[Report a vulnerability](https://github.com/nicglazkov/pixel-audio-bridge/security/advisories/new).

Please include what you were running, what you observed, and how to reproduce
it. I'll acknowledge within a week. Since this is a spare-time project, I can't
promise a fix deadline, but I will tell you honestly what I intend to do and
when.

## Threat model — what this software actually does

Worth understanding before reporting, and worth knowing before you install it:

- **It runs entirely locally.** No server, no accounts, no network calls to any
  third party. See [PRIVACY.md](PRIVACY.md).
- **It executes two external binaries** — `scrcpy` and `adb` — resolved from
  your `PATH`, falling back to Homebrew and the Android SDK's standard
  locations. If an attacker can already write to a directory on your `PATH`,
  they can already run code as you; this app does not widen that.
- **It changes your default audio output device.** That is the documented
  mechanism by which it works, not a side effect.
- **It reads a config file** at `~/.config/pixel-audio-bridge/config`, which is
  sourced as shell script. **Anyone who can write that file can execute code as
  you.** It lives in your home directory under your own permissions; treat it as
  you would `~/.zshrc`.
- **It is unsigned and un-notarized by design.** You build it from source
  yourself, so there is no binary to trust and no Gatekeeper prompt.

## Known accepted risks

**Wireless ADB.** `pab enable-wireless` turns on Android Debug Bridge over TCP.
While that is enabled, any host on the same network that can reach your phone
may attempt to connect to it, subject to Android's own authorisation prompt.
This is inherent to ADB. It resets when the phone reboots. Use USB if this
matters to you — it is also faster.

**The output watchdog is not instantaneous.** When the output device changes
mid-stream, playback is killed within about half a second, not immediately.
Audio may briefly reach another device in that window. This is documented on the
site and in the README, and is a consequence of scrcpy having no way to target a
specific output device.
