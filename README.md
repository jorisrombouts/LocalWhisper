# LocalWhisper

Hold Left Option, speak, release. The text appears at your cursor, in any app.
Speech recognition (whisper.cpp, large-v3-turbo) and cleanup (Apple Intelligence) run on your Mac. Nothing leaves it.

## Requirements

- Apple Silicon Mac running macOS 26
- Xcode Command Line Tools: `xcode-select --install`
- Apple Intelligence enabled, for the cleanup step. The app works without it and inserts the raw transcript.

## Install

```sh
git clone https://github.com/jorisrombouts/LocalWhisper.git && cd LocalWhisper
./build-app.sh install
```

The first build downloads the 1.6 GB model. The app is installed in `/Applications` and appears in the menu bar as a waveform.
macOS asks for two permissions on first use: Microphone, and Accessibility, which is what lets the app paste at your cursor.

## Use

- Hold Left Option, speak, release. Pressing any other key while holding cancels, so Option shortcuts like `€` or `@` still work.
- A pill at the bottom of the screen shows listening, transcribing, cleaning up, and inserted.
- The language is detected automatically. Dutch, English and Swedish are verified.
- The menu has a cleanup toggle, Launch at Login, the last transcript, and Quit.

Cleanup fixes punctuation and capitalisation, removes fillers, and applies self-corrections such as "no wait". It never translates. Dictations under four words are inserted as is.

## Speed

Measured on an M4 Pro, from key release to text at the cursor. Timings for your own machine are in the log, see Troubleshooting.

| Dictation | Recognition | Cleanup | Total |
|---|---|---|---|
| 3 s | 0.9 s | 0.6 s | 1.5 s |
| 10 s | 1.0 s | 1.1 s | 2.1 s |
| 20 s | 1.1 s | 1.4 s | 2.5 s |
| 45 s | 1.7 s | 2.5 s | 4.2 s |

Recognition is flat up to 30 s of audio. Turning cleanup off in the menu leaves only the recognition column.

## Privacy

No network calls. The model and Apple Intelligence run on-device. Your clipboard is restored after the paste.

## Troubleshooting

- The pill says "Inserted" but nothing was pasted: Accessibility is missing or stale. Run `tccutil reset Accessibility nl.joris.localwhisper`, relaunch the app, grant it again.
- Timings per dictation and engine output are in `~/Library/Logs/LocalWhisper.log`.
- If you rebuild often, run `./make-signing-cert.sh` once so permissions survive rebuilds.

## Credits

Built on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) by Georgi Gerganov and contributors (MIT), using its prebuilt framework and the `ggml-large-v3-turbo` model derived from OpenAI's Whisper. Cleanup uses Apple's on-device Foundation Models.

## Development

A Swift Package with no Xcode project. `./build-app.sh` builds and runs `build/LocalWhisper.app`; `./fetch-deps.sh` gets the model and the whisper.cpp framework. `./check.sh` is the smoke test. The rules for changing the code are in `AGENTS.md`.

## Future improvements

Not done, written down so they are not rediscovered.

- CoreML encoder: whisper's encoder on the Neural Engine cuts the 0.9 s per dictation to roughly 0.4 s. Needs a one-time Python conversion of the model with coremltools and a framework built with CoreML support.
- Fn/Globe as hotkey. Needs "Press Fn key: Do Nothing" in Keyboard settings.
- Custom vocabulary through whisper's `initial_prompt`, if technical terms get mangled.
- Streaming preview while speaking, and voice activity detection.
- Model download on first launch instead of at build time, needed before distributing a prebuilt app.
- Notarized release with a Developer ID, so a prebuilt app opens without Gatekeeper warnings.
- Layered app icon made with Icon Composer (ships with Xcode 26).
