#!/bin/sh
# Downloads the whisper model and the prebuilt whisper.cpp framework. Both are gitignored. Safe to re-run.
set -eu
cd "$(dirname "$0")"
WHISPER=v1.9.2
MODEL=Resources/ggml-large-v3-turbo.bin

if [ ! -f "$MODEL" ]; then
  echo "downloading model (1.6 GB)"
  curl -L --progress-bar -o "$MODEL" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
fi
# A few-KB "model" is an HTML block page from a filtering proxy, not a model.
if [ "$(stat -f %z "$MODEL")" -lt 1000000000 ]; then
  rm -f "$MODEL"; echo "model download failed: huggingface.co unreachable or blocked"; exit 1
fi

if [ ! -d Frameworks/whisper.xcframework ]; then
  echo "downloading whisper.cpp $WHISPER framework"
  TMP=$(mktemp -d)
  curl -L --progress-bar -o "$TMP/xc.zip" "https://github.com/ggml-org/whisper.cpp/releases/download/$WHISPER/whisper-$WHISPER-xcframework.zip"
  unzip -q "$TMP/xc.zip" -d "$TMP"
  mkdir -p Frameworks && mv "$TMP/build-apple/whisper.xcframework" Frameworks/
  rm -rf "$TMP"
fi
echo "deps ready"
