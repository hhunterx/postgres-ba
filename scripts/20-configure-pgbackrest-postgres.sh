#!/bin/bash
set -e

# Configure PostgreSQL for pgBackRest and apply settings
# This runs on EVERY container start for existing databases (idempotent)

PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}

echo "Applying PostgreSQL configuration..."

# Configure pgBackRest if enabled (and not in replica mode)
# Note: We need pgBackRest configured even for restore mode (for restore_command)
if [ -n "${PGBACKREST_STANZA}" ] && [ "${PG_MODE}" != "replica" ]; then
    echo "Configuring pgBackRest for stanza '${PGBACKREST_STANZA}'..."
    /usr/local/bin/configure-pgbackrest.sh
fi

# Apply PostgreSQL configuration if database is already initialized
# (For new databases, this will run via /docker-entrypoint-initdb.d/)
if [ -s "$PGDATA/PG_VERSION" ] && [ -f /usr/local/bin/configure-postgres.sh ]; then
    echo "Updating configuration for existing database..."
    /usr/local/bin/configure-postgres.sh
fi

echo "PostgreSQL configuration completed."
