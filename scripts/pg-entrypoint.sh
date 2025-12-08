#!/bin/bash
set -e

# This script runs as postgres user

echo "=========================================="
echo "PostgreSQL with pgBackRest - Starting"
echo "=========================================="

# Check if this is a replica or primary
if [ "${PG_MODE}" = "replica" ]; then
    echo "Starting in REPLICA mode..."
    echo "Replica mode not fully implemented yet. Please use primary mode."
    exit 1
fi

echo "Starting in PRIMARY mode..."

# Check if PostgreSQL data directory exists and has data
if [ -s "$PGDATA/PG_VERSION" ]; then
    echo "PostgreSQL data directory exists with data. Starting normally..."
else
    echo "PostgreSQL data directory is empty or doesn't exist."
    
    # Check if we should restore from backup
    if [ "${RESTORE_FROM_BACKUP}" = "true" ]; then
        echo "Attempting to restore from latest backup..."
        
        # Check if stanza exists
        if ! pgbackrest --stanza=${PGBACKREST_STANZA} info > /dev/null 2>&1; then
            echo "No backup found in S3. Cannot restore. Will initialize new database instead."
            RESTORE_FROM_BACKUP=false
        else
            echo "Stanza exists. Restoring from latest backup..."
            
            # Restore from latest backup with progress
            pgbackrest --stanza=${PGBACKREST_STANZA} \
                --delta \
                --log-level-console=info \
                restore
            
            echo "Restore completed successfully!"
            
            # Configure PostgreSQL after restore
            /usr/local/bin/configure-postgres.sh
        fi
    fi
    
    # If not restoring or restore failed, let docker-entrypoint.sh initialize
    if [ "${RESTORE_FROM_BACKUP}" != "true" ]; then
        echo "Will initialize new database via docker-entrypoint.sh..."
    fi
fi

echo "=========================================="
echo "Starting PostgreSQL server..."
echo "=========================================="

# Execute the original postgres entrypoint
exec docker-entrypoint.sh "$@"
