# LocalWhisper

Menu bar dictation app: hold Left Option, speak, release, cleaned text at the cursor. Everything on-device.
Swift Package (no Xcode project), whisper.cpp prebuilt xcframework on Metal, Apple FoundationModels for cleanup.

## Build and run

- `./build-app.sh` is the only build path: quits the running app, `swift build -c release`, assembles and signs `build/LocalWhisper.app`, relaunches it. Never replace the bundle while the app runs; macOS then fails to validate the process and silently drops its permissions.
- Sign with the "LocalWhisper Dev" certificate (`make-signing-cert.sh`, one-time). An ad-hoc signature is a new identity on every build, and every Accessibility and Microphone grant dies with it.
- `Resources/ggml-large-v3-turbo.bin` (1.6 GB) and `Frameworks/whisper.xcframework` are gitignored. A "downloaded" model of a few KB is an HTML block page; huggingface.co can be blocked by a Cloudflare Gateway on this network.
- Test flags on the binary: `--transcribe file.wav`, `--record 3`, `--clean "raw text"`, `--insert-test` (pastes into the frontmost app), `--overlay-demo <dir>` (renders every pill state to PNG).

## Permissions (TCC)

- Posting ⌘V needs Accessibility. The hotkey works without it, so a dictation that shows "Inserted" but pastes nothing is a permission problem, not a code problem.
- A binary started from a shell inherits the terminal's permissions. Only a launch via `open` tests the app's own grant.
- The app logs `insert: ax_trusted=… post_event_ok=…` to `~/Library/Logs/LocalWhisper.log`. `ax_trusted=0` while System Settings shows the app enabled means a stale entry: `tccutil reset Accessibility nl.joris.localwhisper`, relaunch, grant again.
- The sandbox cannot read the unified log (`log show` returns nothing) or take screenshots. Use the app log and the render flags instead.

## Code

- SwiftUI instantiates the `App` struct more than once: the controller is a singleton, started on `didFinishLaunching`. Loading whisper (Metal) before AppKit has finished launching stalls.
- Top-level `Task {}` in `main.swift` runs on the main actor; blocking main with a semaphore deadlocks it. Harness code uses `RunLoop.main.run()` or `Task.detached`.
- whisper.cpp v1.9.2 asserts in a ggml-metal `atexit` handler; the app quits with `_exit`. Its "failed to load Core ML model" line is the expected Metal fallback.
- Whisper hallucinates sentences on silence: segments with `no_speech_prob >= 0.6` and punctuation-only output are dropped.
- FoundationModels translates unless the instructions say to keep the language; the prompt is few-shot with Dutch examples. Verify with `--clean`.
- Overlay: the `NSPanel` has a fixed generous transparent frame; the SwiftUI pill sizes itself inside it. `ProgressView` does not render in a non-activating panel; use SF Symbol effects. All icons are SF Symbols.
