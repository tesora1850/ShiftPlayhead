#!/bin/bash
# 배포용: 애플 실리콘+인텔 겸용으로 빌드해 dist/ShiftPlayhead.zip 을 만든다. (설치·실행은 안 함)
set -euo pipefail
cd "$(dirname "$0")"

# ShiftPlayhead 전용 인증서로 서명한다. 서명이 매번 같아야 손쉬운 사용 권한이 유지되고,
# 앱 안의 업데이트 기능도 같은 인증서로 서명된 새 버전만 설치한다. (인증서 백업: README 아래 "서명 인증서" 참고)
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -p codesigning | awk '/"ShiftPlayhead Code Signing"/{print $2; exit}')}"
[ -n "$IDENTITY" ] || { echo "키체인에 'ShiftPlayhead Code Signing' 인증서가 없어요" >&2; exit 1; }
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
