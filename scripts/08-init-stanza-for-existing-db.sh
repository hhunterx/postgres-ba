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

echo "Existing database detected, checking stanza status..."

# Start PostgreSQL temporarily in single-user mode to create stanza
# We need PostgreSQL running to verify database system identifier
echo "Starting PostgreSQL temporarily to initialize stanza..."

# Start PostgreSQL in background
run_as_postgres postgres -D "${PGDATA}" &
PG_PID=$!

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if run_as_postgres pg_isready -U postgres > /dev/null 2>&1; then
        echo "✓ PostgreSQL is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: PostgreSQL failed to start within 30 seconds"
        kill $PG_PID 2>/dev/null || true
        exit 1
    fi
    sleep 1
done

# Check if stanza already exists
echo "Checking if stanza '${PGBACKREST_STANZA}' exists..."
if run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} info > /dev/null 2>&1; then
    echo "✓ Stanza already exists"
else
    echo "Creating stanza '${PGBACKREST_STANZA}'..."
    if ! run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create; then
        echo "ERROR: Failed to create stanza"
        kill $PG_PID 2>/dev/null || true
        exit 1
    fi
    echo "✓ Stanza created successfully"
fi

# Stop temporary PostgreSQL instance
echo "Stopping temporary PostgreSQL instance..."
run_as_postgres pg_ctl -D "${PGDATA}" -m fast stop
wait $PG_PID 2>/dev/null || true

echo "Stanza initialization completed."
