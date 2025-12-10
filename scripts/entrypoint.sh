#!/bin/bash
set -e

# Enhanced entrypoint for PostgreSQL with pgBackRest
# Compatible with postgres:18-alpine official image
# 
# This entrypoint:
# 1. Runs pre-initialization scripts (setup, restore, replica)
# 2. Delegates to official docker-entrypoint.sh for database init
# 3. Post-initialization tasks run via /docker-entrypoint-initdb.d/

echo "=========================================="
echo "PostgreSQL 18 with pgBackRest"
echo "=========================================="

PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}
export PGDATA

# ============================================
# Pre-initialization phase
# ============================================
# These scripts run BEFORE the official entrypoint

echo "Running pre-initialization scripts..."

# 1. Setup directories and permissions (always run)
if [ -f /usr/local/bin/00-setup-directories.sh ]; then
    source /usr/local/bin/00-setup-directories.sh
fi

# Check if database already exists
DB_INITIALIZED=false
if [ -s "$PGDATA/PG_VERSION" ]; then
    DB_INITIALIZED=true
    echo "Database already initialized at ${PGDATA}"
fi

# 2. Handle backup restore (only if DB doesn't exist)
if [ "$DB_INITIALIZED" = false ] && [ -f /usr/local/bin/01-restore-from-backup.sh ]; then
    source /usr/local/bin/01-restore-from-backup.sh
fi

# 3. Setup replica (only if DB doesn't exist)
if [ "$DB_INITIALIZED" = false ] && [ -f /usr/local/bin/02-setup-replica.sh ]; then
    source /usr/local/bin/02-setup-replica.sh
fi

# 4. Configure SSL (always run, even for existing databases)
if [ -f /usr/local/bin/10-configure-ssl.sh ]; then
    echo "Configuring SSL certificates..."
    source /usr/local/bin/10-configure-ssl.sh
fi

# 5. Configure PostgreSQL and pgBackRest (always run for existing databases)
if [ "$DB_INITIALIZED" = true ] && [ -f /usr/local/bin/20-configure-pgbackrest-postgres.sh ]; then
    echo "Applying configuration to existing database..."
    source /usr/local/bin/20-configure-pgbackrest-postgres.sh
fi

# 6. Post-initialization tasks (always run if pgBackRest is enabled)
if [ "$DB_INITIALIZED" = true ] && [ -n "${PGBACKREST_STANZA}" ] && [ -f /usr/local/bin/99-post-init.sh ]; then
    echo "Running post-initialization tasks..."
    source /usr/local/bin/99-post-init.sh
fi

# ============================================
# Database initialization phase
# ============================================
# The official docker-entrypoint.sh will:
# - Run initdb if database doesn't exist
# - Execute scripts in /docker-entrypoint-initdb.d/ (only on first init!)
# - Start PostgreSQL

echo ""
if [ "$DB_INITIALIZED" = true ]; then
    echo "Starting existing PostgreSQL database..."
else
    echo "Initializing new PostgreSQL database..."
    echo "Scripts in /docker-entrypoint-initdb.d/ will run after initdb"
fi
echo "Database directory: ${PGDATA}"
echo ""

# Call the official PostgreSQL entrypoint
# This handles all the standard initialization
exec /usr/local/bin/docker-entrypoint.sh "$@"
