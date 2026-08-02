# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] 2026-08-02

Signed, notarized distribution. No build tools required to install.

### Added
- **Signed and notarized by Apple**, so there is no Gatekeeper warning and no
  right-click-to-open dance.
- **Homebrew cask**: `brew install --cask nicglazkov/tap/pixel-audio-bridge`,
  which pulls in scrcpy as a dependency.
- **DMG and zip** attached to the release, at stable URLs that do not change
  between versions.

### Fixed
- **The app is now universal.** It was compiled arm64 only while the
  documentation claimed Apple silicon and Intel, so it would not have run on an
  Intel Mac at all. Both slices are now built and merged.
- `paboutput` moved from Resources to MacOS, where codesign expects an
  executable. `pab` stays in Resources, since anything in MacOS must carry its
  own signature and a script's signature lives in an extended attribute that
  does not reliably survive archiving.

## [1.0.0] 2026-08-01

First release.

### Added
- SwiftUI menu bar app with a window: status, transport, output and phone
  pickers, and a light/dark website to match.
- **Waiting state.** The app launches whatever is connected, starts on its own
  when the chosen output appears, and returns to waiting when it leaves.
- **Output watchdog.** Makes the chosen device the system default and stops
  playback within ~0.5 s if that ever changes.
- `pab` command-line tool, usable standalone: `run`, `stop`, `status`, `info`,
  `doctor`, `enable-wireless`.
- Automatic transport selection (USB when plugged in, Wi-Fi otherwise) with a
  15 ms buffer wired and 200 ms wireless.
- 78 tests that run without a phone, headphones or audio hardware.

### Notes
- End-to-end latency is ~191 ms wired and ~376 ms wireless. 170.7 ms of that is
  the Bluetooth hop inside the headphones and cannot be reduced by any setting.
- The 15 ms wired buffer was chosen for a jitter-free link and validated by
  listening rather than by instrumenting sample-skips. Raise it with `--buffer`
  if you hear clicks.

[1.1.0]: https://github.com/nicglazkov/pixel-audio-bridge/releases/tag/v1.1.0
[1.0.0]: https://github.com/nicglazkov/pixel-audio-bridge/releases/tag/v1.0.0
