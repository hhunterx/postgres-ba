#!/bin/bash
set -e

# Initialize pgBackRest stanza and perform initial backup
# This runs ONLY during first database initialization (via /docker-entrypoint-initdb.d/)
# Delegates to init-db.sh for the actual work

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

# Delegate to init-db.sh
if [ -f /usr/local/bin/init-db.sh ]; then
    /usr/local/bin/init-db.sh
else
    echo "ERROR: init-db.sh not found at /usr/local/bin/init-db.sh"
    exit 1
fi
