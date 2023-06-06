#!/bin/bash -e
​
openssl genrsa -out test-ca.key 4096
openssl req -new -x509 -sha256 -days 3650 -key test-ca.key -out test-ca.pem -subj "/CN=CBL Test CA"
​
cat > test-node.v3.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
EOF
​
openssl genrsa -out test-client.key 4096
openssl req -new -sha256 -key test-client.key -out test-client.pem -subj "/CN=CBL Test"
openssl x509 -req -sha256 -days 3650 -CA test-ca.pem -CAkey test-ca.key -CAcreateserial -in test-client.pem -out test-client.pem -extfile test-node.v3.ext
​
# Add -legacy if you are using openSSL 3.x instead of the default mac LibreSSL 3.x to allow keychain to recongize your password.
openssl pkcs12 -export -passout pass:123 -out client.p12 -inkey test-client.key -in test-client.pem
openssl x509 -in test-ca.pem -out client-ca.der -outform DER
​
rm test-*.*