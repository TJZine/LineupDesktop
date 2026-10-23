#!/bin/sh
set -eu
fixture_ca="$HOME/.config/lineup-android/fixture-ca"
umask 077
mkdir -p "$fixture_ca"
if [ ! -f "$fixture_ca/ca.crt" ]; then
cat > "$fixture_ca/ca.cnf" <<'EOF'
[req]
distinguished_name=dn
x509_extensions=ca
prompt=no
[dn]
CN=Lineup synthetic fixture CA
[ca]
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$fixture_ca/ca.key" -out "$fixture_ca/ca.crt" -days 90 -config "$fixture_ca/ca.cnf" >/dev/null 2>&1
fi
if [ ! -f "$fixture_ca/localhost.crt" ]; then
openssl req -newkey rsa:2048 -nodes -keyout "$fixture_ca/localhost.key" -out "$fixture_ca/localhost.csr" -subj '/CN=localhost' >/dev/null 2>&1
printf '%s\n' 'subjectAltName=DNS:localhost,IP:127.0.0.1' 'extendedKeyUsage=serverAuth' 'keyUsage=critical,digitalSignature,keyEncipherment' 'authorityKeyIdentifier=keyid,issuer' 'subjectKeyIdentifier=hash' > "$fixture_ca/leaf.ext"
openssl x509 -req -in "$fixture_ca/localhost.csr" -CA "$fixture_ca/ca.crt" -CAkey "$fixture_ca/ca.key" -CAcreateserial -out "$fixture_ca/localhost.crt" -days 90 -extfile "$fixture_ca/leaf.ext" >/dev/null 2>&1
fi

# Production trusts the public CA only in the debuggable source set.
fixture_resources="$(dirname "$0")/../../../android/app/src/debug/res/raw"
mkdir -p "$fixture_resources"
cp "$fixture_ca/ca.crt" "$fixture_resources/fixture_ca.crt"
