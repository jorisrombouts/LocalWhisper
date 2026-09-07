#!/bin/sh
# Smoke test: engine, cleanup and overlay through the binary's check flags. Fails on the first broken piece.
set -eu
cd "$(dirname "$0")"
T=$(mktemp -d)
swift build --quiet
BIN=.build/debug/LocalWhisper

say -v Samantha -o "$T/en.aiff" "Hello, this is a test of local whisper."
say -v Xander -o "$T/nl.aiff" "Hallo, dit is een test van lokale spraakherkenning."
afconvert -f WAVE -d LEI16@16000 -c 1 "$T/en.aiff" "$T/en.wav"
afconvert -f WAVE -d LEI16@16000 -c 1 "$T/nl.aiff" "$T/nl.wav"
python3 -c "import wave,random; w=wave.open('$T/noise.wav','wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(bytes(random.randint(0,255) if i%2==0 else random.randint(0,1) for i in range(64000)))"

"$BIN" --transcribe "$T/en.wav" 2>/dev/null | grep -i "test of local whisper" || { echo "FAIL: english transcription"; exit 1; }
"$BIN" --transcribe "$T/nl.wav" 2>/dev/null | grep -i "spraakherkenning" || { echo "FAIL: dutch transcription"; exit 1; }
[ "$("$BIN" --transcribe "$T/noise.wav" 2>/dev/null | grep "^text:")" = "text: " ] || { echo "FAIL: faint noise should transcribe to nothing"; exit 1; }

OUT=$("$BIN" --clean "ik wil eh morgen naar de de winkel gaan" 2>/dev/null | grep "^text:")
echo "$OUT" | grep -q "winkel" && ! echo "$OUT" | grep -qE " eh | de de " || { echo "FAIL: cleanup: $OUT"; exit 1; }

"$BIN" --overlay-demo "$T" >/dev/null 2>&1 || true
[ "$(ls "$T"/overlay-*.png | wc -l)" -eq 5 ] || { echo "FAIL: overlay render"; exit 1; }

rm -rf "$T"
echo "all checks passed"
