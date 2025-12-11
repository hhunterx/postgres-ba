#!/bin/bash
set -e

# Initialize pgBackRest stanza for EXISTING databases
# This runs BEFORE PostgreSQL starts to ensure the stanza exists
# when archive_command is first executed

# Helper function to run commands as postgres user
run_as_postgres() {
    if [ "$(id -u)" = "0" ]; then
        su-exec postgres "$@"
    else
        "$@"
    fi
}

echo "Initializing pgBackRest stanza for existing database..."

# Only run if pgBackRest is enabled and not a replica
if [ -z "${PGBACKREST_STANZA}" ]; then
    echo "PGBACKREST_STANZA not set, skipping stanza initialization."
    return 0
fi

if [ "${PG_MODE}" = "replica" ]; then
    echo "Running in replica mode, skipping stanza initialization."
    return 0
fi

# Only run if database already exists
PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}
if [ ! -f "${PGDATA}/PG_VERSION" ]; then
    echo "New database detected, stanza will be initialized after PostgreSQL starts."
    return 0
fi

echo "Existing database detected, creating stanza before PostgreSQL starts..."

# Check if stanza already exists
if run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} info > /dev/null 2>&1; then
    echo "✓ Stanza '${PGBACKREST_STANZA}' already exists"
    return 0
fi

# Create stanza in OFFLINE mode (doesn't require PostgreSQL to be running)
# This is safe because we just need to read PGDATA to get database system identifier
echo "Creating stanza '${PGBACKREST_STANZA}' in offline mode..."
if run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} --no-online --log-level-console=info stanza-create; then
    echo "✓ Stanza created successfully before PostgreSQL startup!"
else
    echo "WARNING: Failed to create stanza in offline mode."
    echo "         The stanza will be created after PostgreSQL starts (via 99-stanza-check.sh)"
fi
