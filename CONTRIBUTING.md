# Contributing

Thanks for looking. This is a small, opinionated utility, so a quick note on what
fits before you spend time on a change.

## Build and test

```sh
brew install scrcpy          # runtime dependency
./build.sh                   # produces build/PixelAudioBridge.app
./tests/run.sh               # 78 tests, no hardware required
```

`tests/run.sh` runs two suites. Neither needs a phone, headphones, or any audio
device: `adb`, `paboutput` and `scrcpy` are replaced with fakes on `PATH`, and
the UI logic lives in `BridgeLogic`, which is free of `UserDefaults`, timers and
processes so it can be called directly.

If you change behaviour, add a case. If you change the JSON that `pab info`
emits, add a case to `tests/main.swift`. That contract is the boundary between
the shell and the app, and it has broken silently before.

## Layout

| Path | What it is |
|---|---|
| `bin/pab` | All bridge logic: device selection, transport, watchdog, process lifecycle |
| `app/OutputDevice.swift` | `paboutput`, which reads and sets the macOS default output device |
| `app/BridgeController.swift` | App state, and the pure `BridgeLogic` the tests exercise |
| `app/ContentView.swift` | SwiftUI window and menu bar |
| `app/IconGen.swift` | Draws the app icon at build time |
| `docs/` | The website, served by GitHub Pages |

`pab` works standalone. The app is a supervisor and a status display over it, and
that split is deliberate, so please keep bridge logic in the shell script rather
than moving it into Swift.

## Things that will get pushed back on

- **Making the output guard weaker without saying so.** The watchdog already has
  a documented ~0.5 s exposure window; anything that widens it needs to be
  stated on the site and in the README, not just in code.
- **Adding network calls.** [PRIVACY.md](PRIVACY.md) promises there are none.
  That promise is checkable, and it should stay that way.
- **Adding third-party requests to the website.** Fonts are self-hosted on
  purpose.
- **Quoting a latency figure that hasn't been measured.** Every number in this
  project came from an actual measurement, and the one value that didn't
  (the 15 ms wired buffer) is labelled as such everywhere it appears.

## Style

Match what's there. Comments explain *why*, especially where something looks
odd. Most of the strange-looking code in this repository is load-bearing, and
the comment says which failure it exists to prevent.
