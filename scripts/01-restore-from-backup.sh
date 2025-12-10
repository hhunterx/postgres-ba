#!/bin/bash
set -e

# Handle restore from backup
# This runs BEFORE database initialization

PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}

# Only restore if explicitly requested and database doesn't exist
if [ "${RESTORE_FROM_BACKUP}" != "true" ]; then
    echo "RESTORE_FROM_BACKUP not enabled, skipping restore."
    exit 0
fi

if [ -s "$PGDATA/PG_VERSION" ]; then
    echo "Database already exists at $PGDATA, skipping restore."
    exit 0
fi

echo "=========================================="
echo "Restoring PostgreSQL from backup"
echo "=========================================="

if [ -z "${PGBACKREST_STANZA}" ]; then
    echo "ERROR: PGBACKREST_STANZA must be set to restore from backup"
    exit 1
fi

# Configure pgBackRest first
echo "Configuring pgBackRest for restore..."
/usr/local/bin/configure-pgbackrest.sh

# Check if stanza/backup exists
echo "Checking for available backups..."
if ! su - postgres -c "pgbackrest --stanza=${PGBACKREST_STANZA} info" > /dev/null 2>&1; then
    echo "ERROR: No backup found for stanza '${PGBACKREST_STANZA}'"
    echo "Cannot restore without an existing backup."
    exit 1
fi

# Perform restore
echo "Restoring from latest backup..."
su - postgres -c "pgbackrest --stanza=${PGBACKREST_STANZA} --delta --log-level-console=info restore"

echo "Restore completed successfully!"
echo "PostgreSQL configuration will be applied in next step."

# Signal that we've restored and should skip normal init
export POSTGRES_HOST_AUTH_METHOD=trust
