#!/bin/bash
set -e

# Configure SSL certificates
# This runs on EVERY container start (idempotent)

echo "Configuring SSL certificates..."

# Create SSL directory if it doesn't exist
mkdir -p /etc/postgresql/ssl
chown -R postgres:postgres /etc/postgresql/ssl

if [ -f /usr/local/bin/configure-ssl-with-ca.sh ]; then
    /usr/local/bin/configure-ssl-with-ca.sh
else
    echo "SSL configuration script not found, skipping."
fi

echo "SSL configuration completed."
