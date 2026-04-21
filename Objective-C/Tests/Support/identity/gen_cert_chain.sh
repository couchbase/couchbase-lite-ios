#!/usr/bin/env bash
#
# Regenerates the Root CA / Intermediate CA / Leaf certificate chain embedded
# as PEM string literals in TrustCheckTest.m:
#   - testTrustCHeckWithRootCerts (cert1=leaf, cert2=intermediate, cert3=root)
#   - testTrustCheckWithAcceptOnlySelfSignedCertOnNonSelfSignedCert (reuses cert1=leaf)
#
# When the leaf / intermediate expire, run this script and paste the PEM blocks
# it prints back into TrustCheckTest.m (replacing the cert1 / cert2 / cert3
# literals in both tests for cert1, just cert2/cert3 in the root-certs test).
#
# Requires: openssl (the LibreSSL that ships with macOS works).
#
# Usage:
#   ./gen_cert_chain.sh [years]
#
# `years` is the validity period for the leaf and intermediate (default 20).
# The root CA gets years*2 so it always outlives what it signs.

set -euo pipefail

YEARS="${1:-20}"
LEAF_DAYS=$(( YEARS * 365 ))
INT_DAYS=$(( YEARS * 365 ))
ROOT_DAYS=$(( YEARS * 2 * 365 ))

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM
echo "WORK DIR: ${WORK}"
cd "$WORK"

# ---- Root CA (self-signed) ----
openssl genrsa -out root.key 2048 2>/dev/null
openssl req -x509 -new -key root.key -sha256 -days "$ROOT_DAYS" \
    -subj "/CN=My Root CA" \
    -extensions v3_ca \
    -config <(cat <<'CFG'
[req]
distinguished_name = dn
[dn]
[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
CFG
) -out root.crt

# ---- Intermediate CA (signed by Root) ----
openssl genrsa -out int.key 2048 2>/dev/null
openssl req -new -key int.key -subj "/CN=Intermediate1 CA" -out int.csr

cat > int.ext <<'CFG'
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
CFG

openssl x509 -req -in int.csr -CA root.crt -CAkey root.key -CAcreateserial \
    -out int.crt -days "$INT_DAYS" -sha256 -extfile int.ext 2>/dev/null

# ---- Leaf (signed by Intermediate) ----
openssl genrsa -out leaf.key 2048 2>/dev/null
openssl req -new -key leaf.key -subj "/CN=Leaf Cert" -out leaf.csr

cat > leaf.ext <<'CFG'
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
CFG

openssl x509 -req -in leaf.csr -CA int.crt -CAkey int.key -CAcreateserial \
    -out leaf.crt -days "$LEAF_DAYS" -sha256 -extfile leaf.ext 2>/dev/null

echo "==================== leaf (cert1) ===================="
cat leaf.crt
echo "==================== inter (cert2) ===================="
cat int.crt
echo "==================== root (cert3) ===================="
cat root.crt

echo ""
echo "Expirations:"
echo -n "  leaf:         "; openssl x509 -in leaf.crt -noout -enddate
echo -n "  inter:        "; openssl x509 -in int.crt  -noout -enddate
echo -n "  root:         "; openssl x509 -in root.crt -noout -enddate
