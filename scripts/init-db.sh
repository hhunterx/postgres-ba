#!/bin/bash
set -e

echo "Running post-initialization setup..."

# Configure PostgreSQL for pgBackRest/SSL
/usr/local/bin/configure-postgres.sh

# Only run pgBackRest operations if stanza is configured
if [ "${PGBACKREST_STANZA}" != "" ]; then
    echo "Creating pgBackRest stanza..."
    pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create || true

    # Perform initial full backup
    echo "Performing initial full backup..."
    pgbackrest --stanza=${PGBACKREST_STANZA} --type=full --log-level-console=info backup

    echo "Initial backup completed successfully!"
else
    echo "pgBackRest not configured (PGBACKREST_STANZA not set). Skipping backup operations."
fi
