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

# Create stanza in OFFLINE mode (doesn't require PostgreSQL to be running)
# This is safe because we just need to read PGDATA to get database system identifier
# If the stanza already exists and is valid, pgBackRest will report that (not an error)
# If it exists but is invalid/mismatched, it will fail and we'll handle that
echo "Creating/verifying stanza '${PGBACKREST_STANZA}' in offline mode..."

# Capture output to check for specific messages
STANZA_OUTPUT=$(run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} --no-online --log-level-console=info stanza-create 2>&1 || true)
echo "$STANZA_OUTPUT"

# Check if stanza was created or already existed
if echo "$STANZA_OUTPUT" | grep -q "stanza-create command end: completed successfully\|already exists"; then
    echo "✓ Stanza '${PGBACKREST_STANZA}' is ready!"
else
    echo "WARNING: Failed to create/verify stanza in offline mode."
    echo "         The stanza will be created after PostgreSQL starts (via 99-stanza-check.sh)"
fi
