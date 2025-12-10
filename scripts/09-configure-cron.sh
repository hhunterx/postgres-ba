#!/bin/bash
set -e

# Configure cron jobs for backups
# This runs on EVERY container start (idempotent)

echo "Configuring cron jobs for pgBackRest backups..."

# Setup cron jobs for backups (idempotent)
if [ -n "${PGBACKREST_STANZA}" ] && [ "${PG_MODE}" != "replica" ]; then
    if [ -f /usr/local/bin/setup-cron.sh ]; then
        echo "Ensuring backup cron jobs are configured..."
        /usr/local/bin/setup-cron.sh
        
        # Start/restart cron in background (idempotent)
        # Kill existing cron if running
        pkill crond 2>/dev/null || true
        sleep 1
        
        if ! crond -b -l 8; then
            echo "ERROR: Failed to start cron daemon. Automated backups will not run."
            echo "You can manually trigger backups using:"
            echo "  pgbackrest --stanza=${PGBACKREST_STANZA} --type=full backup"
            exit 1
        else
            echo "✓ Cron daemon started successfully"
        fi
    fi
fi

echo "Cron job configuration"
