#!/bin/bash
set -e

# Initialize pgBackRest stanza and perform initial backup
# This runs ONLY during first database initialization (via /docker-entrypoint-initdb.d/)
# NOTE: PostgreSQL configs are applied in pre-init phase, not here

echo "Initializing pgBackRest stanza and backup..."

# Only run if stanza is configured
if [ -z "${PGBACKREST_STANZA}" ]; then
    echo "pgBackRest not configured (PGBACKREST_STANZA not set). Skipping."
    exit 0
fi

# Skip in replica mode (replicas don't manage backups)
if [ "${PG_MODE}" = "replica" ]; then
    echo "Replica mode detected. Skipping pgBackRest initialization."
    exit 0
fi

echo "Creating pgBackRest stanza '${PGBACKREST_STANZA}'..."
if ! pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create 2>&1 | tee /tmp/stanza-create.log; then
    # Check if error is due to mismatched system-id
    if grep -q "do not match the database" /tmp/stanza-create.log; then
        echo "Stanza exists but doesn't match this database. Recreating stanza..."
        pgbackrest --stanza=${PGBACKREST_STANZA} --force stanza-delete || true
        pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create
    else
        echo "ERROR: Failed to create stanza. Check logs above."
        exit 1
    fi
fi

echo "Stanza created successfully!"

# Perform initial full backup
echo "Performing initial full backup..."
# Use --no-archive-check for existing databases that may not have full WAL history
if pgbackrest --stanza=${PGBACKREST_STANZA} --type=full --no-archive-check --log-level-console=info backup; then
    echo "Initial backup completed successfully!"
else
    echo "WARNING: Initial backup failed. Will retry on next cron run."
    # Don't fail container startup if backup fails
    exit 0
fi
