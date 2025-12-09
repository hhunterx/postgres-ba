#!/bin/bash
set -e

echo "Running post-initialization setup..."

# Configure PostgreSQL for pgBackRest/SSL
/usr/local/bin/configure-postgres.sh

# Only run pgBackRest operations if stanza is configured
if [ "${PGBACKREST_STANZA}" != "" ]; then
    echo "Creating pgBackRest stanza..."
    if ! pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create 2>&1 | tee /tmp/stanza-create.log; then
        # Check if error is due to mismatched system-id
        if grep -q "do not match the database" /tmp/stanza-create.log; then
            echo "Stanza exists but doesn't match this database. Recreating stanza..."
            pgbackrest --stanza=${PGBACKREST_STANZA} --force stanza-delete || true
            pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create
        fi
    fi

    # Perform initial full backup
    echo "Performing initial full backup..."
    # Use --no-archive-check for existing databases that may not have full WAL history
    if pgbackrest --stanza=${PGBACKREST_STANZA} --type=full --no-archive-check --log-level-console=info backup; then
        echo "Initial backup completed successfully!"
    else
        echo "WARNING: Initial backup failed. Will retry on next cron run."
    fi
else
    echo "pgBackRest not configured (PGBACKREST_STANZA not set). Skipping backup operations."
fi
