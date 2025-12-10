#!/bin/bash
set -e

# Post-initialization tasks
# This runs on EVERY container start (idempotent)

echo "Running post-initialization tasks..."

# Initialize pgBackRest stanza if configured
if [ -n "${PGBACKREST_STANZA}" ] && [ "${PG_MODE}" != "replica" ]; then
    echo "Checking pgBackRest stanza '${PGBACKREST_STANZA}'..."
    
    # Setup cron jobs for backups (idempotent)
    if [ -f /usr/local/bin/setup-cron.sh ]; then
        echo "Ensuring backup cron jobs are configured..."
        /usr/local/bin/setup-cron.sh
        
        # Start/restart cron in background (idempotent)
        # Kill existing cron if running
        pkill crond 2>/dev/null || true
        sleep 1
        crond -b -l 8 2>/dev/null || true
    fi
    
    # Initialize pgBackRest stanza in background after PostgreSQL is ready
    # (idempotent - won't recreate if stanza already exists)
    if [ -f /usr/local/bin/run-init-db.sh ]; then
        echo "Scheduling pgBackRest stanza initialization..."
        (
            # Wait for PostgreSQL to be fully ready
            sleep 10
            echo "Starting pgBackRest stanza initialization (background)..."
            /usr/local/bin/run-init-db.sh > /var/log/pgbackrest-init.log 2>&1 || true
            echo "pgBackRest initialization completed. Check /var/log/pgbackrest-init.log for details."
        ) &
    fi
fi

echo "Post-initialization completed."
