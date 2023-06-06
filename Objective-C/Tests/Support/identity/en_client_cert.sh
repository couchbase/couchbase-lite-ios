#!/bin/bash -e

echo
echo "You will be prompted for a password, use your own chosen password and keep entering the same one until told otherwise."
read -p "Press Enter to continue"

openssl genrsa -aes256 -out test-ca.key 4096
openssl req -x509 -new -nodes -key test-ca.key -sha256 -days 3650 -out test-ca.crt -subj "/CN=Test CA/C=UK/ST=UK/L=Manchester/O=Couchbase"
openssl req -new -nodes -out test-node.csr -newkey rsa:4096 -keyout test-node.key -subj "/CN=Test Node/C=UK/ST=UK/L=Manchester/O=Couchbase"

cat > test-node.v3.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
EOF

openssl x509 -req -in test-node.csr -CA test-ca.crt -CAkey test-ca.key -CAcreateserial -out test-node.crt -days 3650 -sha256 -extfile test-node.v3.ext

rm test-node.v3.ext
rm test-node.csr
rm test-ca.srl

echo
echo "Use the password 123 if you want the exported p12 to work correctly with the tests"
read -p "Press Enter to continue"

# Use LibreSSL. If using OpenSSL 3.x add -legacy when exporting below
# https://stackoverflow.com/questions/70431528/mac-verification-failed-during-pkcs12-import-wrong-password-azure-devops

openssl pkcs12 -export -out client.p12 -inkey test-node.key -in test-node.crt
openssl x509 -in test-ca.crt -out client-ca.der -outform DER

rm -rf test-*