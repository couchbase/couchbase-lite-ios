#!/bin/bash -e

# Output files (DER format)
CA_KEY_DER="ca-key.der"
CA_CERT_DER="ca-cert.der"
CA_P12="ca.p12"
P2_PASS="123"

# Temp files
CA_KEY_PEM="ca-key.pem"
CA_CSR="ca.csr"
CA_EXT="ca.ext"
CA_CERT_PEM="ca-cert.pem"

# Generate private key in PEM (temporary)
openssl genrsa -out "${CA_KEY_PEM}" 4096

# Convert private key PEM -> DER
openssl rsa -in "${CA_KEY_PEM}" -outform DER -out "${CA_KEY_DER}"

# Create CSR
openssl req -new -sha256 -key "${CA_KEY_PEM}" -out "${CA_CSR}" -subj "/CN=CBL-TEST-CA"

# Create an extension file for CA usage
cat > "${CA_EXT}" <<EOF
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF

# Create self-signed certificate with CA extensions in PEM (temporary)
openssl x509 -req -sha256 -days 3650 -in "${CA_CSR}" -signkey "${CA_KEY_PEM}" -out "${CA_CERT_PEM}" -extfile "${CA_EXT}"

# Convert certificate PEM -> DER
openssl x509 -in "ca-cert.pem" -outform DER -out "${CA_CERT_DER}"

# Create PKCS#12 (.p12) with key and cert
openssl pkcs12 -export -inkey "${CA_KEY_PEM}" -in "${CA_CERT_PEM}" -out "${CA_P12}" -password "pass:${P2_PASS}" -name "CBL-Test-CA" -legacy

# Cleanup temporary files
rm -f "${CA_KEY_PEM}" "${CA_CSR}" "${CA_EXT}" "${CA_CERT_PEM}"
