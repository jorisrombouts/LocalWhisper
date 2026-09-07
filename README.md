# LocalWhisper

Hold Left Option, speak, release. The text appears at your cursor, in any app.
Speech recognition (whisper.cpp, large-v3-turbo) and cleanup (Apple Intelligence) run on your Mac. Nothing leaves it.

## Requirements

- Apple Silicon Mac running macOS 26
- Xcode Command Line Tools: `xcode-select --install`
- Apple Intelligence enabled, for the cleanup step. The app works without it and inserts the raw transcript.

## Install

```sh
git clone <this repository> LocalWhisper && cd LocalWhisper
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

## Privacy

No network calls. The model and Apple Intelligence run on-device. Your clipboard is restored after the paste.

## Troubleshooting

- The pill says "Inserted" but nothing was pasted: Accessibility is missing or stale. Run `tccutil reset Accessibility nl.joris.localwhisper`, relaunch the app, grant it again.
- Timings per dictation and engine output are in `~/Library/Logs/LocalWhisper.log`.
- If you rebuild often, run `./make-signing-cert.sh` once so permissions survive rebuilds.

## Development

A Swift Package with no Xcode project. `./build-app.sh` builds and runs `build/LocalWhisper.app`; `./fetch-deps.sh` gets the model and the whisper.cpp framework. The rules for changing the code are in `AGENTS.md`.
