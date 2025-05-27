#!/bin/bash

# Define directories
CERTS_DIR="./certs-generated"
FRONTEND_DIR="$CERTS_DIR/frontend"

# Create directories
echo "Creating certificate directories..."
mkdir -p "$FRONTEND_DIR"

echo "Generating self-signed certificate for frontend..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$FRONTEND_DIR/frontend.key" \
    -out "$FRONTEND_DIR/frontend.crt" \
    -subj "/C=FR/ST=Paris/L=Paris/O=ft_transcendance/CN=ft_transcendance.com"

# Set permissions
echo "Setting file permissions..."
chmod 644 "$FRONTEND_DIR/frontend.crt"
chmod 600 "$FRONTEND_DIR/frontend.key"

echo "Certificates generated successfully in $FRONTEND_DIR"
