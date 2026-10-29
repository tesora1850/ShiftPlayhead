#!/bin/bash
# ShiftPlayhead 전용 서명 인증서를 새로 만든다.
#  1) 이름(CN)만 들어간 20년짜리 코드 서명 인증서를 만들어 로그인 키체인에 넣는다 (codesign만 쓸 수 있게).
#  2) 직접 정한 비밀번호(12자 이상)로 백업 파일(.p12)을 만든다.
#  3) main.swift 의 업데이트 서명 확인값을 새 인증서로 바꾼다.
# 사용: tools/new_cert.sh [--replace] [백업 파일 경로]
#   --replace  키체인에 있는 기존 'ShiftPlayhead Code Signing' 인증서를 지우고 새로 만든다.
# 주의: 인증서를 바꾸면 이미 배포한 버전은 자동 업데이트로 새 버전을 받을 수 없다 (직접 받아야 함).
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="ShiftPlayhead Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
REPLACE=0
if [ "${1:-}" = "--replace" ]; then REPLACE=1; shift; fi
OUT="${1:-$HOME/Desktop/ShiftPlayhead-서명인증서.p12}"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  if [ $REPLACE -eq 0 ]; then
    echo "키체인에 '$NAME' 인증서가 이미 있어요. 지우고 새로 만들려면 --replace 를 붙여 실행하세요." >&2; exit 1
  fi
  while security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; do
    security delete-identity -c "$NAME" "$KEYCHAIN" >/dev/null
  done
  echo "기존 인증서를 키체인에서 지웠어요."
fi
[ -e "$OUT" ] && { echo "$OUT 파일이 이미 있어요. 옮기거나 다른 경로를 주세요." >&2; exit 1; }

# 백업 비밀번호: 화면에 안 보임, 12자 이상, 두 번 확인
while true; do
  read -r -s -p "백업 비밀번호 (12자 이상, 다른 곳에 안 쓰는 것): " PW; echo
  [ ${#PW} -ge 12 ] || { echo "너무 짧아요. 12자 이상으로 해주세요."; continue; }
  read -r -s -p "한 번 더: " PW2; echo
  [ "$PW" = "$PW2" ] && break
  echo "두 번 입력한 게 달라요. 다시 해주세요."
done
export PW

WORK=$(mktemp -d); chmod 700 "$WORK"
trap 'rm -P "$WORK"/key.pem 2>/dev/null; rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = ShiftPlayhead Code Signing
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
/usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 7300 -config "$WORK/cert.cnf" 2>/dev/null
chmod 600 "$WORK/key.pem"

# 백업 파일 (사용자 비밀번호)
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" -out "$OUT" -passout env:PW
unset PW PW2
# 키체인에 넣기 (codesign만 허용). 사용자 비밀번호가 명령줄에 드러나지 않게 일회용 비밀번호로 한 번 더 묶어 넣는다.
TMPPW=$(/usr/bin/openssl rand -hex 24); export TMPPW
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" -out "$WORK/import.p12" -passout env:TMPPW
security import "$WORK/import.p12" -k "$KEYCHAIN" -P "$TMPPW" -T /usr/bin/codesign >/dev/null
unset TMPPW

HASH=$(/usr/bin/openssl x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f')
sed -i '' -E "s/certificate leaf = H\"[0-9a-f]{40}\"/certificate leaf = H\"$HASH\"/" main.swift
grep -q "$HASH" main.swift || { echo "main.swift 의 서명 확인값을 바꾸지 못했어요." >&2; exit 1; }

echo
echo "완료"
echo "- 키체인: '$NAME' (지문 $HASH)"
echo "- 백업 파일: $OUT  → iCloud Drive 같은 다른 곳으로 옮기고, 비밀번호는 암호 앱에 저장하세요."
echo "- main.swift 서명 확인값을 새 인증서로 바꿨어요. ./build.sh 로 다시 설치한 뒤 손쉬운 사용 권한을 한 번 다시 켜주세요."
