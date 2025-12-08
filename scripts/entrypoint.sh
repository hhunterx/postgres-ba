#!/bin/bash
set -e

echo "=========================================="
echo "PostgreSQL with pgBackRest - Starting up"
echo "=========================================="

# Configure pgBackRest
echo "Configuring pgBackRest..."
/usr/local/bin/configure-pgbackrest.sh

# Check if this is a replica or primary
if [ "${PG_MODE}" = "replica" ]; then
    echo "Starting in REPLICA mode..."
    # Replica setup logic would go here
    # For now, we'll focus on primary mode
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
        
        # Create pgBackRest stanza if it doesn't exist
        if ! pgbackrest --stanza=${PGBACKREST_STANZA} info > /dev/null 2>&1; then
            echo "Stanza not found. This might be the first time running."
            echo "Initializing PostgreSQL for the first time..."
            
            # Initialize the database
            initdb --username="${POSTGRES_USER}" --pwfile=<(echo "${POSTGRES_PASSWORD}")
            
            # Configure PostgreSQL
            /usr/local/bin/configure-postgres.sh
            
            # Start PostgreSQL temporarily to create stanza
            pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start
            
            # Create stanza
            echo "Creating pgBackRest stanza..."
            pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create
            
            # Perform initial full backup
            echo "Performing initial full backup..."
            pgbackrest --stanza=${PGBACKREST_STANZA} --type=full --log-level-console=info backup
            
            # Stop PostgreSQL
            pg_ctl -D "$PGDATA" -m fast -w stop
        else
            echo "Stanza exists. Restoring from latest backup..."
            
            # Restore from latest backup with progress
            pgbackrest --stanza=${PGBACKREST_STANZA} \
                --delta \
                --log-level-console=info \
                restore
            
            echo "Restore completed successfully!"
        fi
    else
        echo "Initializing new PostgreSQL database..."
        initdb --username="${POSTGRES_USER}" --pwfile=<(echo "${POSTGRES_PASSWORD}")
        
        # Configure PostgreSQL
        /usr/local/bin/configure-postgres.sh
        
        # Start PostgreSQL temporarily to create stanza
        pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start
        
        # Create stanza
        echo "Creating pgBackRest stanza..."
        pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create
        
        # Perform initial full backup
        echo "Performing initial full backup..."
        pgbackrest --stanza=${PGBACKREST_STANZA} --type=full --log-level-console=info backup
        
        # Stop PostgreSQL
        pg_ctl -D "$PGDATA" -m fast -w stop
    fi
fi

# Ensure PostgreSQL configuration is up to date
/usr/local/bin/configure-postgres.sh

# Setup cron jobs for backups
echo "Setting up backup cron jobs..."
/usr/local/bin/setup-cron.sh

# Start cron in background
crond -b -l 8

echo "=========================================="
echo "Starting PostgreSQL server..."
echo "=========================================="

# Execute the original postgres entrypoint
exec docker-entrypoint.sh "$@"
