#!/bin/bash -e

# Output files (DER format)
CA_KEY_DER="ca-key.der"
CA_CERT_DER="ca-cert.der"

# Temp files
CA_KEY_PEM="ca-key.pem"
CA_CSR="ca.csr"
CA_EXT="ca.ext"

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
openssl x509 -req -sha256 -days 3650 -in "${CA_CSR}" -signkey "${CA_KEY_PEM}" -out "ca-cert.pem" -extfile "${CA_EXT}"

# Convert certificate PEM -> DER
openssl x509 -in "ca-cert.pem" -outform DER -out "${CA_CERT_DER}"

# Cleanup temporary files
# rm -f "${CA_KEY_PEM}" "${CA_CSR}" "${CA_EXT}" "ca-cert.pem"

rm -f "${CA_CSR}" "${CA_EXT}" "ca-cert.pem"