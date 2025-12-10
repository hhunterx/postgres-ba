#!/bin/bash
set -e

# Post-initialization tasks
# This runs on EVERY container start (idempotent)

echo "Running post-initialization tasks..."

# Setup cron jobs for backups (idempotent)
if [ -n "${PGBACKREST_STANZA}" ] && [ "${PG_MODE}" != "replica" ]; then
    if [ -f /usr/local/bin/setup-cron.sh ]; then
        echo "Ensuring backup cron jobs are configured..."
        /usr/local/bin/setup-cron.sh
        
        # Start/restart cron in background (idempotent)
        # Kill existing cron if running
        pkill crond 2>/dev/null || true
        sleep 1
        crond -b -l 8 2>/dev/null || true
    fi
fi

echo "Post-initialization completed."
