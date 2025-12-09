#!/bin/bash
set -e

# Shared CA directory - should be on a shared volume or passed from primary
CA_DIR="${CA_DIR:-/var/lib/postgresql/ca}"
CA_CERT="${CA_DIR}/ca.crt"
CA_KEY="${CA_DIR}/ca.key"

SSL_DIR="${SSL_CERT_DIR:-/var/lib/postgresql/ssl}"
SERVER_CERT="${SSL_DIR}/server.crt"
SERVER_KEY="${SSL_DIR}/server.key"
SERVER_CSR="${SSL_DIR}/server.csr"

# Server name (use hostname or environment variable)
SERVER_NAME="${SERVER_NAME:-$(hostname)}"

echo "=========================================="
echo "PostgreSQL SSL with Shared CA"
echo "=========================================="
echo "Server Name: $SERVER_NAME"
echo "CA Directory: $CA_DIR"
echo "SSL Directory: $SSL_DIR"

# Create directories
if [ ! -d "$CA_DIR" ]; then
    echo "Creating CA directory: $CA_DIR"
    mkdir -p "$CA_DIR"
    chown postgres:postgres "$CA_DIR"
    chmod 700 "$CA_DIR"
fi

if [ ! -d "$SSL_DIR" ]; then
    echo "Creating SSL directory: $SSL_DIR"
    mkdir -p "$SSL_DIR"
    chown postgres:postgres "$SSL_DIR"
    chmod 700 "$SSL_DIR"
fi

# Generate CA certificate (only if it doesn't exist)
if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
    echo "Generating shared CA certificate (valid for 10 years)..."
    
    # Generate CA private key
    openssl genrsa -out "$CA_KEY" 2048
    
    # Generate CA self-signed certificate
    openssl req -new -x509 -key "$CA_KEY" -out "$CA_CERT" \
        -days 3650 \
        -subj "/C=BR/ST=State/L=City/O=Organization/CN=PostgreSQL-CA"
    
    echo "CA certificate generated successfully."
else
    echo "CA certificate already exists. Using existing CA."
fi

# Generate server certificate (always regenerate per server)
if [ -f "$SERVER_CERT" ] && [ -f "$SERVER_KEY" ]; then
    echo "Server certificate already exists. Skipping generation."
else
    echo "Generating server certificate signed by CA (valid for 10 years)..."
    
    # Generate server private key
    openssl genrsa -out "$SERVER_KEY" 2048
    
    # Generate server certificate signing request
    openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" \
        -subj "/C=BR/ST=State/L=City/O=Organization/CN=$SERVER_NAME"
    
    # Sign server certificate with CA
    openssl x509 -req -in "$SERVER_CSR" \
        -CA "$CA_CERT" -CAkey "$CA_KEY" \
        -CAcreateserial -out "$SERVER_CERT" \
        -days 3650 \
        -sha256
    
    # Clean up CSR
    rm -f "$SERVER_CSR"
    
    echo "Server certificate generated and signed by CA."
fi

# Set proper permissions
chown postgres:postgres "$CA_CERT" "$CA_KEY" "$SERVER_CERT" "$SERVER_KEY"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_CERT"
chmod 644 "$CA_CERT"
chmod 600 "$CA_KEY"

# Create root certificate file for client validation (same as CA cert)
ROOT_CERT="${SSL_DIR}/root.crt"
cp "$CA_CERT" "$ROOT_CERT"
chown postgres:postgres "$ROOT_CERT"
chmod 644 "$ROOT_CERT"

echo "SSL certificates ready:"
echo "  CA Certificate: $CA_CERT"
echo "  Server Certificate: $SERVER_CERT"
echo "  Server Key: $SERVER_KEY"
echo "  Root Cert (for validation): $ROOT_CERT"
echo "=========================================="
