#!/bin/bash
# ShiftPlayhead 빌드 → /Applications 설치 → 실행.
# 전용 인증서로 서명하므로 다시 빌드해도 손쉬운 사용 권한이 유지된다.
set -euo pipefail
cd "$(dirname "$0")"

APP=/Applications/ShiftPlayhead.app
# ShiftPlayhead 전용 인증서로 서명한다. 서명이 매번 같아야 손쉬운 사용 권한이 유지되고,
# 앱 안의 업데이트 기능도 같은 인증서로 서명된 새 버전만 설치한다. (인증서 백업: README 아래 "서명 인증서" 참고)
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -p codesigning | awk '/"ShiftPlayhead Code Signing"/{print $2; exit}')}"
[ -n "$IDENTITY" ] || { echo "키체인에 'ShiftPlayhead Code Signing' 인증서가 없어요" >&2; exit 1; }

rm -rf build/ShiftPlayhead.app && mkdir -p build/ShiftPlayhead.app/Contents/MacOS
swiftc -O -swift-version 5 main.swift -o build/ShiftPlayhead.app/Contents/MacOS/ShiftPlayhead
cp Info.plist build/ShiftPlayhead.app/Contents/
mkdir -p build/ShiftPlayhead.app/Contents/Resources && cp AppIcon.icns build/ShiftPlayhead.app/Contents/Resources/
codesign --force --sign "$IDENTITY" build/ShiftPlayhead.app

pkill -x ShiftPlayhead 2>/dev/null && sleep 1 || true
rm -rf "$APP" && cp -R build/ShiftPlayhead.app "$APP"
open "$APP"
echo "installed: $APP"
