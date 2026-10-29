#!/bin/bash
# 배포용: 애플 실리콘+인텔 겸용으로 빌드해 dist/ShiftPlayhead.zip 을 만든다. (설치·실행은 안 함)
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${SIGN_IDENTITY:--}"   # 배포본은 임시 서명 (개인 인증서·이메일이 안 들어가게)
OUT=dist/ShiftPlayhead.app

rm -rf dist && mkdir -p "$OUT/Contents/MacOS" dist/tmp
for a in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $a-apple-macos13.0 main.swift -o dist/tmp/$a
done
lipo -create dist/tmp/arm64 dist/tmp/x86_64 -output "$OUT/Contents/MacOS/ShiftPlayhead"
rm -rf dist/tmp
cp Info.plist "$OUT/Contents/"
mkdir -p "$OUT/Contents/Resources" && cp AppIcon.icns "$OUT/Contents/Resources/"
codesign --force --sign "$IDENTITY" "$OUT"
(cd dist && ditto -c -k --keepParent ShiftPlayhead.app ShiftPlayhead.zip)
echo "made: dist/ShiftPlayhead.zip"
