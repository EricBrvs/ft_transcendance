#!/usr/bin/env bash
set -e

CERT_DIR="/usr/share/kibana/config/certs"
CERT_FILE="${CERT_DIR}/kibana.crt"
KEY_FILE="${CERT_DIR}/kibana.key"

mkdir -p "$CERT_DIR"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Generating self-signed SSL certificate and key for Kibana..."
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/CN=kibana"
    echo "SSL certificate and key have been generated."
else
    echo "SSL certificate and key already exist, skipping generation."
fi

exec kibana
