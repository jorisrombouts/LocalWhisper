# LocalWhisper

Hold Left Option and speak, or tap it and speak hands-free. The text appears at your cursor, in any app.

- Recognition: [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) with the large-v3-turbo model.
- Cleanup: Apple's on-device Foundation Models, the Apple Intelligence system model of about 3B parameters, not bundled.

Everything runs on your Mac. Nothing leaves it.

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

Two ways, same result:

- **Hold** Left Option, speak, release.
- **Tap** Left Option, speak, tap again. Esc or the ✕ in the pill discards. It stops by itself after two minutes without speech.

Any other key while holding cancels, so Option shortcuts like `€` or `@` still work. A pill at the bottom of the screen shows listening, transcribing, cleaning up, and inserted. The language is detected automatically; Dutch, English and Swedish are verified.

The menu has a microphone picker ("Automatic" is the built-in microphone; Bluetooth headsets work when picked but miss the first half second), a cleanup toggle, Launch at Login, Recent transcriptions (the last five; clicking one copies it), and Quit.

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

## Size

| Component | Size |
|---|---|
| Model (ggml-large-v3-turbo) | 1.5 GB |
| whisper.cpp framework | 5.9 MB |
| App icon | 1.2 MB |
| App binary | 437 KB |

The Swift source is about 750 lines in 10 files.

## Privacy

No network calls. The model and Apple Intelligence run on-device. Your clipboard is restored after the paste.

## Troubleshooting

- The pill says "Inserted" but nothing was pasted: Accessibility is missing or stale. Run `tccutil reset Accessibility nl.joris.localwhisper`, relaunch the app, grant it again.
- Timings per dictation and engine output are in `~/Library/Logs/LocalWhisper.log`.
- If you rebuild often, run `./make-signing-cert.sh` once so permissions survive rebuilds.

## Development

A Swift Package with no Xcode project. `./build-app.sh` builds and runs `build/LocalWhisper.app`; `./fetch-deps.sh` gets the model and the whisper.cpp framework. `./check.sh` is the smoke test. The rules for changing the code are in `AGENTS.md`.

## Roadmap

- Core ML encoder: recognition about twice as fast, for 1.3 GB more disk space.
- The pill reports a failed paste instead of "Inserted".
