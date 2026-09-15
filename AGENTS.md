# LocalWhisper: rules for changing the code

What it is, how to install and use it: `README.md`. This file is what keeps a change from breaking the app.

## Docs

- After a change, check `README.md`, `PLAN.md` and this file; rewrite only a sentence the change made wrong. Replace and delete before adding; no history, no changelog, no rationale a user does not need. The README's size and speed figures are measurements (`wc -l Sources/LocalWhisper/*.swift`, `du -sh` on the installed binary, the log); a code change re-measures them.

## Build and test

- `./build-app.sh` fetches deps, builds release, signs, and restarts `build/LocalWhisper.app`. `./build-app.sh install` refreshes `/Applications/LocalWhisper.app`, the login item. Never replace a bundle under a running app: macOS silently drops its permissions. Never run both copies at once.
- Sign with the "LocalWhisper Dev" certificate (`make-signing-cert.sh`). An ad-hoc signature is a new identity per build, and every permission grant dies with it.
- `./check.sh` is the smoke test: engine on English, Dutch, noise, a hum VAD must reject and a spoken "thank you" it must keep; cleanup on Dutch and on a question it must not answer; overlay render. Run it before merging. The paste, hotkey and hands-free paths are checked by hand; `--insert-test` pastes into the frontmost app and the log's `mode=` field shows the gesture.
- Log: `~/Library/Logs/LocalWhisper.log`. Baseline on an M4 Pro: engine load 0.5 s (0.7 s on a cold file cache), whisper 0.9 s per dictation (1.6 s beyond 30 s of audio), cleanup 0.5 s plus 30 ms per second of audio. Far above these is a regression.
- The two models and the framework are gitignored; `fetch-deps.sh` gets them. A model file of a few KB is a proxy block page, which is what the size guards catch.

## Permissions

- "Inserted" but no paste is Accessibility, not code. `ax_trusted=0` in the log with the app enabled in System Settings means a stale entry: `tccutil reset Accessibility nl.joris.localwhisper`, relaunch, grant again. A binary started from a shell inherits the terminal's grants; only `open` tests the app's own.
- The agent sandbox cannot read `log show` or take screenshots. Use the log file and `--overlay-demo`.

## Code

- SwiftUI instantiates the `App` struct more than once: the controller is a singleton, started on `didFinishLaunching`. Loading whisper (Metal) before AppKit has finished launching stalls.
- Top-level `Task {}` in `main.swift` runs on the main actor; blocking main with a semaphore deadlocks it. Harness code uses `RunLoop.main.run()` or `Task.detached`.
- whisper.cpp v1.9.2 asserts in a ggml-metal `atexit` handler; the app quits with `_exit`. Its "failed to load Core ML model" line is the expected Metal fallback.
- Recording uses `AVCaptureSession` with an explicit `AVCaptureDeviceInput`; `AVAudioEngine` cannot bind a device reliably (Bluetooth headsets renegotiate their sample rate right after the mic opens). The converter is rebuilt when the buffer format changes.
- The level meter in `DictationController` tracks a noise floor and a recent peak with tuned constants; recorded silence must give zero.
- Whisper invents speech in non-speech audio, and its own `no_speech_prob` reads 0.00 while doing it. Silero VAD gates the decoder: only audio it hears speech in is transcribed, so hum, noise and clicks come back empty in a few ms. Neither loudness, duration nor decoder confidence separates an invented sentence from a real one, so do not add a threshold or a phrase deny list in front of it. VAD is the only guard left: without the model the app logs a warning and hallucinates again. `whisper peak=` stays in the log to tell a dead microphone from one VAD heard no speech on.
- FoundationModels wants to answer a dictated question and translate a foreign one: the instructions forbid both and the examples (past turns in the session `Transcript`, one a question, two Dutch) show the behaviour. Never use the same text as an example and a test; a duplicate prompt makes the model answer it. Verify with `--clean`. macOS evicts the model after idle and a cold call takes over 2 s, past the timeout: a fresh session is prewarmed when recording starts.
- Overlay: the `NSPanel` has a fixed generous transparent frame and never activates; the SwiftUI pill sizes itself inside it and the hands-free ✕ is a tap gesture, not a button. `ProgressView` does not render in a non-activating panel; use SF Symbol effects. All icons are SF Symbols; the menu bar icon stays monochrome. Animations ignore Reduce Motion by design.
