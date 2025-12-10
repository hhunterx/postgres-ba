#!/bin/bash
set -e

# Handle restore from backup
# This runs BEFORE database initialization
# NOTE: This script is sourced, so use return instead of exit for non-error cases

PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}

# Helper function to run commands as postgres user
# If already running as postgres, run directly; otherwise use su-exec
run_as_postgres() {
    if [ "$(id -u)" = "0" ]; then
        su-exec postgres "$@"
    else
        "$@"
    fi
}

# Only restore if explicitly requested and database doesn't exist
if [ "${RESTORE_FROM_BACKUP}" != "true" ]; then
    echo "RESTORE_FROM_BACKUP not enabled, skipping restore."
    return 0 2>/dev/null || true
fi

if [ -s "$PGDATA/PG_VERSION" ]; then
    echo "Database already exists at $PGDATA, skipping restore."
    return 0 2>/dev/null || true
fi

# Validate conflicting modes
if [ "${PG_MODE}" = "replica" ]; then
    echo "ERROR: Cannot use RESTORE_FROM_BACKUP=true with PG_MODE=replica"
    echo "Replicas should be setup from primary, not from backup restore."
    exit 1
fi

echo "=========================================="
echo "Restoring PostgreSQL from backup"
echo "=========================================="

if [ -z "${PGBACKREST_STANZA}" ]; then
    echo "ERROR: PGBACKREST_STANZA must be set to restore from backup"
    exit 1
fi

# Check if stanza/backup exists
echo "Checking for available backups..."
if ! run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} info > /dev/null 2>&1; then
    echo "ERROR: No backup found for stanza '${PGBACKREST_STANZA}'"
    echo "Cannot restore without an existing backup."
    exit 1
fi

# Perform restore
echo "Restoring from latest backup..."
run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} --delta --log-level-console=info restore

echo "Restore completed successfully!"

# Signal that we've restored and should skip normal init
export POSTGRES_HOST_AUTH_METHOD=trust
