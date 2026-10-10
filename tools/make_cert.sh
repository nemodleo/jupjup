#!/bin/zsh
# 자체 서명 인증서 "Jupjup Dev"를 로그인 키체인에 만든다 (한 번만).
# 애드혹 서명은 빌드마다 바뀌어 macOS가 화면 기록 권한을 매번 되묻는다. 같은 인증서로 서명하면
# 코드 요구사항이 고정돼 다시 빌드해도 권한이 유지된다. build.sh가 이 이름을 찾아 자동으로 쓴다.
# 실행 중 키체인 비밀번호 창이 한두 번 뜬다(신뢰 설정·첫 서명 때 "항상 허용").
set -e
NAME="Jupjup Dev"
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then echo "이미 있음: $NAME"; exit 0; fi
T="$(mktemp -d)"; cd "$T"
cat > ext.cnf <<'EOF'
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=Jupjup Dev
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config ext.cnf >/dev/null 2>&1
# macOS의 security import는 OpenSSL 3의 기본 PKCS12(AES·PBKDF2)를 못 읽는다("MAC verification failed") → 옛 형식(3DES·SHA1)으로
openssl pkcs12 -export -out dev.p12 -inkey key.pem -in cert.pem -passout pass:jupjup -name "$NAME" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES >/dev/null 2>&1 \
  || openssl pkcs12 -export -legacy -out dev.p12 -inkey key.pem -in cert.pem -passout pass:jupjup -name "$NAME" >/dev/null 2>&1
# 개인 키를 로그인 키체인에, codesign이 묻지 않고 쓰게
security import dev.p12 -k ~/Library/Keychains/login.keychain-db -P jupjup -T /usr/bin/codesign -T /usr/bin/security
# 이 인증서를 코드 서명용으로 신뢰(사용자 범위). 여기서 비밀번호 창이 뜰 수 있다
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
rm -rf "$T"
security find-identity -v -p codesigning | grep "$NAME" && echo "만들어짐: $NAME · 이제 ./build.sh 한 번 빌드하고 화면 기록 권한을 마지막으로 한 번 켜 주세요"
