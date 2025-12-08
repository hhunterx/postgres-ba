#!/bin/bash
set -e

echo "Running post-initialization setup..."

# Configure PostgreSQL for pgBackRest
/usr/local/bin/configure-postgres.sh

# Create pgBackRest stanza
echo "Creating pgBackRest stanza..."
pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create || true

# Perform initial full backup
echo "Performing initial full backup..."
pgbackrest --stanza=${PGBACKREST_STANZA} --type=full --log-level-console=info backup

echo "Initial backup completed successfully!"
