#!/bin/bash
set -e

# This script runs as postgres user

echo "=========================================="
echo "PostgreSQL with pgBackRest - Starting"
echo "=========================================="

# Check if this is a replica or primary
if [ "${PG_MODE}" = "replica" ]; then
    echo "Starting in REPLICA mode..."
    
    # Check if PostgreSQL data directory exists and has data
    if [ -s "$PGDATA/PG_VERSION" ]; then
        echo "PostgreSQL data directory exists. Starting as replica..."
    else
        echo "PostgreSQL data directory is empty. Setting up replica..."
        
        # Wait for primary to be ready
        echo "Waiting for primary to be ready..."
        max_attempts=30
        attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if pg_isready -h ${PRIMARY_HOST} -p ${PRIMARY_PORT:-5432} -U ${POSTGRES_USER} > /dev/null 2>&1; then
                echo "Primary is ready!"
                break
            fi
            attempt=$((attempt + 1))
            echo "Waiting for primary... (attempt $attempt/$max_attempts)"
            sleep 2
        done
        
        if [ $attempt -eq $max_attempts ]; then
            echo "ERROR: Primary not ready after $max_attempts attempts"
            exit 1
        fi
        
        # Create replication slot on primary
        echo "Creating replication slot on primary..."
        SLOT_NAME=$(hostname | sed 's/-/_/g')
        PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${PRIMARY_HOST} -p ${PRIMARY_PORT:-5432} -U ${POSTGRES_USER} -d postgres -c \
            "SELECT pg_create_physical_replication_slot('${SLOT_NAME}');" 2>/dev/null || \
            echo "Replication slot already exists (will try to continue anyway)"
        
        # Use pg_basebackup to clone data from primary
        echo "Cloning data from primary using pg_basebackup..."
        echo "This may take a while depending on database size..."
        
        PGPASSWORD=${POSTGRES_PASSWORD} pg_basebackup \
            -h ${PRIMARY_HOST} \
            -p ${PRIMARY_PORT:-5432} \
            -U ${POSTGRES_USER} \
            -D ${PGDATA} \
            -Fp \
            -Xs \
            -P \
            -R \
            -v
        
        echo "pg_basebackup completed successfully!"
        
        # The -R flag already creates standby.signal and configures primary_conninfo
        # But we'll ensure the slot name is set correctly
        echo "Configuring replication slot..."
        cat >> ${PGDATA}/postgresql.conf <<EOF

# Replica Configuration
primary_slot_name = '${SLOT_NAME}'
hot_standby = on
EOF
        
        echo "Replica setup completed!"
    fi
else
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
fi

echo "=========================================="
echo "Starting PostgreSQL server..."
echo "=========================================="

# Execute the original postgres entrypoint
exec docker-entrypoint.sh "$@"
