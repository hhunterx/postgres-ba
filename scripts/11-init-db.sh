#!/bin/bash
set -e

# pgBackRest initialization script
# 
# Use cases:
# 1. Initialize pgBackRest for a NEW database (called by 11-init-db.sh)
# 2. Initialize pgBackRest for an EXISTING database (called by manually by user.sh)
# 3. Manual initialization after migration/restore
#
# This script is IDEMPOTENT - safe to run multiple times
# If stanza already exists, it will just report that and exit successfully

# Helper function to run commands as postgres user
# If already running as postgres, run directly; otherwise use su-exec
run_as_postgres() {
    if [ "$(id -u)" = "0" ]; then
        su-exec postgres "$@"
    else
        "$@"
    fi
}

echo "=========================================="
echo "pgBackRest Initialization"
echo "=========================================="

# Check if pgBackRest is configured
if [ -z "${PGBACKREST_STANZA}" ]; then
    echo "ERROR: PGBACKREST_STANZA environment variable is not set."
    echo "Cannot initialize pgBackRest without a stanza name."
    exit 1
fi

echo "Stanza: ${PGBACKREST_STANZA}"
echo ""

# Check if PostgreSQL is running
echo "Checking PostgreSQL status..."
if ! pg_isready -U "${POSTGRES_USER:-postgres}" > /dev/null 2>&1; then
    echo "ERROR: PostgreSQL is not running or not ready."
    echo "PostgreSQL must be running to create pgBackRest stanza."
    exit 1
fi
echo "✓ PostgreSQL is running"
echo ""

# Check if WAL archiving is configured
echo "Checking WAL archiving configuration..."
ARCHIVE_MODE=$(run_as_postgres psql -U ${POSTGRES_USER:-postgres} -tAc 'SHOW archive_mode')
ARCHIVE_COMMAND=$(run_as_postgres psql -U ${POSTGRES_USER:-postgres} -tAc 'SHOW archive_command')

if [ "$ARCHIVE_MODE" != "on" ]; then
    echo "WARNING: archive_mode is not 'on' (current: $ARCHIVE_MODE)"
    echo "pgBackRest requires archive_mode=on in postgresql.conf"
    echo ""
    echo "To fix this, add to postgresql.conf:"
    echo "  archive_mode = on"
    echo "  archive_command = 'pgbackrest --stanza=${PGBACKREST_STANZA} archive-push %p'"
    echo "Then restart PostgreSQL."
    exit 1
fi

if [[ ! "$ARCHIVE_COMMAND" =~ pgbackrest ]]; then
    echo "WARNING: archive_command does not use pgbackrest"
    echo "Current: $ARCHIVE_COMMAND"
    echo ""
    echo "To fix this, add to postgresql.conf:"
    echo "  archive_command = 'pgbackrest --stanza=${PGBACKREST_STANZA} archive-push %p'"
    echo "Then reload PostgreSQL: pg_ctl reload"
fi

echo "✓ WAL archiving is configured"
echo ""

# Check if stanza already exists (with backup)
echo "Checking if stanza already exists..."
STANZA_INFO=$(run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} info 2>&1)
# Check if stanza exists AND has a backup (not just "missing stanza path" or "error")
if echo "$STANZA_INFO" | grep -q "status: ok\|full backup"; then
    echo "✓ Stanza '${PGBACKREST_STANZA}' already exists with backup"
    echo ""
    
    # Show stanza info
    echo "Stanza information:"
    echo "$STANZA_INFO"
    
    echo ""
    echo "Stanza is ready. No action needed."
    exit 0
fi

echo "Stanza does not exist. Creating..."
echo ""

# Create stanza
echo "Creating pgBackRest stanza '${PGBACKREST_STANZA}'..."
if ! run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} --log-level-console=info stanza-create 2>&1 | tee /tmp/stanza-create.log; then
    echo ""
    echo "ERROR: Failed to create stanza. Check errors above."
    
    # Check for common issues
    if grep -q "do not match the database" /tmp/stanza-create.log; then
        echo ""
        echo "This error means a stanza with this name exists in S3 but for a different database."
        echo "To fix:"
        echo "  1. Delete the old stanza: pgbackrest --stanza=${PGBACKREST_STANZA} --force stanza-delete"
        echo "  2. Run this script again"
    fi
    
    exit 1
fi

echo ""
echo "✓ Stanza created successfully!"
echo ""

# Perform initial backup (always automatic, no prompting)
echo "Performing initial full backup..."
echo "This may take several minutes depending on database size..."
echo ""

if run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} --type=full --log-level-console=info backup; then
    echo ""
    echo "✓ Initial backup completed successfully!"
    echo ""
    echo "Backup information:"
    run_as_postgres pgbackrest --stanza=${PGBACKREST_STANZA} info
else
    echo ""
    echo "WARNING: Initial backup failed."
    echo "You can retry manually: pgbackrest --stanza=${PGBACKREST_STANZA} --type=full backup"
    # Don't fail - cron will retry
fi

echo ""
echo "=========================================="
echo "Initialization complete!"
echo "=========================================="
echo ""
echo "Stanza '${PGBACKREST_STANZA}' is ready to use."
echo "Automated backups will run according to cron schedule."
echo ""
