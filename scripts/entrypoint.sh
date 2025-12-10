#!/bin/bash
set -e

# Enhanced entrypoint for PostgreSQL with pgBackRest
# Compatible with postgres:18-alpine official image
# 
# This entrypoint:
# 1. Runs pre-initialization scripts (setup permissions, restore, replica, ssl, pgBackRest config)
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
 
# 2. Configure pgBackRest (always run, both new and existing databases)
if [ -f /usr/local/bin/01-configure-pgbackrest.sh ]; then
    source /usr/local/bin/01-configure-pgbackrest.sh
fi

# 3. Handle backup restore (only if DB doesn't exist)
if [ -f /usr/local/bin/02-restore-from-backup.sh ]; then
    source /usr/local/bin/02-restore-from-backup.sh
fi

# 4. Setup replica (only if DB doesn't exist)
# Replica configuration is handled by configure-postgres.sh after pg_basebackup
if [ -f /usr/local/bin/03-setup-replica.sh ]; then
    source /usr/local/bin/03-setup-replica.sh
fi

# 5. Configure SSL (always run, both new and existing databases)
if [ -f /usr/local/bin/04-configure-ssl.sh ]; then
    source /usr/local/bin/04-configure-ssl.sh
fi

# 6. Configure PostgreSQL for existing DBs only
# (For new DBs, this will run via /docker-entrypoint-initdb.d/10-configure-postgres-initdb.sh)
# configure-postgres.sh handles ALL cases: primary, replica, restored, new DB
# It builds postgresql.auto.conf incrementally based on mode and environment variables
if [ -s "$PGDATA/PG_VERSION" ] && [ -f /usr/local/bin/10-configure-postgres-initdb.sh ]; then
    source /usr/local/bin/10-configure-postgres-initdb.sh
fi

# 7. Post-initialization tasks (always run if pgBackRest enabled and not replica)
# Sets up cron and schedules init-db.sh (idempotent)
# Replicas do NOT run backup cron jobs
if [ -n "${PGBACKREST_STANZA}" ] && [ "${PG_MODE}" != "replica" ] && [ -f /usr/local/bin/09-configure-cron.sh ]; then
    source /usr/local/bin/09-configure-cron.sh
fi

# ============================================
# Database initialization phase
# ============================================
# The official docker-entrypoint.sh will:
# - Run initdb if database doesn't exist
# - Execute scripts in /docker-entrypoint-initdb.d/ (only on first init!)
# - Start PostgreSQL
 
echo "Database directory: ${PGDATA}"

# Call the official PostgreSQL entrypoint
# This handles all the standard initialization
exec /usr/local/bin/docker-entrypoint.sh "$@"
