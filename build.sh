#!/bin/bash
# ShiftPlayhead 빌드 → /Applications 설치 → 실행.
# 같은 개발자 인증서로 서명하므로 다시 빌드해도 손쉬운 사용 권한이 유지된다.
set -euo pipefail
cd "$(dirname "$0")"

APP=/Applications/ShiftPlayhead.app
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}"
IDENTITY="${IDENTITY:--}"

rm -rf build/ShiftPlayhead.app && mkdir -p build/ShiftPlayhead.app/Contents/MacOS
swiftc -O -swift-version 5 main.swift -o build/ShiftPlayhead.app/Contents/MacOS/ShiftPlayhead
cp Info.plist build/ShiftPlayhead.app/Contents/
mkdir -p build/ShiftPlayhead.app/Contents/Resources && cp AppIcon.icns build/ShiftPlayhead.app/Contents/Resources/
codesign --force --sign "$IDENTITY" build/ShiftPlayhead.app

pkill -x ShiftPlayhead 2>/dev/null && sleep 1 || true
rm -rf "$APP" && cp -R build/ShiftPlayhead.app "$APP"
open "$APP"
echo "installed: $APP"
