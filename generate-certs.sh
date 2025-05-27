#!/bin/bash

# This script generates SSL certificates for Elasticsearch and Kibana
# Based on the official Elastic documentation

# Define directories
CERTS_DIR="/home/ebervas/ft_transcendance/certs-generated"
CA_DIR="$CERTS_DIR/ca"
INSTANCE_DIR="$CERTS_DIR/instance"

# Create directories if they don't exist
echo "Creating certificate directories..."
mkdir -p "$CA_DIR" "$INSTANCE_DIR"

echo "Generating Certificate Authority (CA)..."
openssl genrsa -out "$CA_DIR/ca.key" 2048
openssl req -new -x509 -sha256 -key "$CA_DIR/ca.key" -out "$CA_DIR/ca.crt" -days 3650 -subj "/C=FR/ST=Paris/L=Paris/O=ft_transcendance/CN=ft_transcendance-ca"

echo "Generating certificates for Elasticsearch and Kibana..."
openssl genrsa -out "$INSTANCE_DIR/instance.key" 2048
openssl req -new -key "$INSTANCE_DIR/instance.key" -out "$INSTANCE_DIR/instance.csr" -subj "/C=FR/ST=Paris/L=Paris/O=ft_transcendance/CN=elasticsearch"
openssl x509 -req -in "$INSTANCE_DIR/instance.csr" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -CAcreateserial -out "$INSTANCE_DIR/instance.crt" -days 365 -sha256

# Clean up temporary files
echo "Removing temporary files..."
rm -f "$INSTANCE_DIR/instance.csr" "$CA_DIR/ca.srl"

# Set file permissions
echo "Setting file permissions..."
chmod 644 "$CA_DIR/ca.crt" "$INSTANCE_DIR/instance.crt"
chmod 600 "$CA_DIR/ca.key" "$INSTANCE_DIR/instance.key"

echo "Certificates successfully generated in $CERTS_DIR"
echo "CA: $CA_DIR/ca.crt, $CA_DIR/ca.key"
echo "Instance: $INSTANCE_DIR/instance.crt, $INSTANCE_DIR/instance.key"
