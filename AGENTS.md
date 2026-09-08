# LocalWhisper: rules for changing the code

What it is, how to install and use it: `README.md`. This file is what keeps a change from breaking the app.

## Build and test

- `./build-app.sh` fetches deps, builds release, signs, and restarts `build/LocalWhisper.app`. `./build-app.sh install` refreshes `/Applications/LocalWhisper.app`, the login item. Never replace a bundle under a running app: macOS silently drops its permissions. Never run both copies at once.
- Sign with the "LocalWhisper Dev" certificate (`make-signing-cert.sh`). An ad-hoc signature is a new identity per build, and every permission grant dies with it.
- `./check.sh` is the smoke test (engine on English and Dutch, cleanup, overlay render); run it before merging. The flags it uses: `--transcribe file.wav`, `--clean "raw text"`, `--insert-test` (pastes into the frontmost app), `--overlay-demo <dir>` (renders every pill state to PNG), `--launch-at-login on|off`.
- Log: `~/Library/Logs/LocalWhisper.log`. Baseline on an M4 Pro: engine load 1.3 s, whisper 0.9 s per dictation (1.7 s beyond 30 s of audio), cleanup 0.5 s plus 30 ms per second of audio. Far above these is a regression.
- The model and the framework are gitignored; `fetch-deps.sh` gets them. A model file of a few KB is a proxy block page.

## Permissions

- "Inserted" but no paste is Accessibility, not code. `ax_trusted=0` in the log with the app enabled in System Settings means a stale entry: `tccutil reset Accessibility nl.joris.localwhisper`, relaunch, grant again. A binary started from a shell inherits the terminal's grants; only `open` tests the app's own.
- The agent sandbox cannot read `log show` or take screenshots. Use the log file and `--overlay-demo`.

## Code

- SwiftUI instantiates the `App` struct more than once: the controller is a singleton, started on `didFinishLaunching`. Loading whisper (Metal) before AppKit has finished launching stalls.
- Top-level `Task {}` in `main.swift` runs on the main actor; blocking main with a semaphore deadlocks it. Harness code uses `RunLoop.main.run()` or `Task.detached`.
- whisper.cpp v1.9.2 asserts in a ggml-metal `atexit` handler; the app quits with `_exit`. Its "failed to load Core ML model" line is the expected Metal fallback.
- Recording uses `AVCaptureSession` with an explicit `AVCaptureDeviceInput`. Binding a device onto `AVAudioEngine`'s input node breaks on Bluetooth headsets, which renegotiate their sample rate right after the mic opens. The log's `mic:` and `mic stopped:` lines show the device and the captured seconds.
- Whisper hallucinates on silence ("Thank you.", "you"): clips whose loudest 100 ms stays under 0.01 RMS are skipped, segments with `no_speech_prob >= 0.6` and punctuation-only output are dropped. The log line `whisper rms= peak=` is the calibration data.
- FoundationModels translates unless the instructions say to keep the language; the prompt is few-shot with Dutch examples. Verify with `--clean`.
- Overlay: the `NSPanel` has a fixed generous transparent frame; the SwiftUI pill sizes itself inside it. `ProgressView` does not render in a non-activating panel; use SF Symbol effects. All icons are SF Symbols; the menu bar icon stays monochrome. Menu items use title case, with an ellipsis when they open another window. The animations stay on regardless of Reduce Motion; that is the owner's choice.
