#!/bin/bash
set -e

# Setup directories and permissions
# This runs BEFORE database initialization on every container start once (always)

echo "Setting up directories and permissions..."

PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}

# Only create PGDATA directory if it already has content (existing DB)
# For new databases, let docker-entrypoint.sh handle PGDATA creation
# This avoids initdb errors about "directory exists but is not empty"
if [ -f "${PGDATA}/PG_VERSION" ]; then
    echo "Existing database detected, ensuring correct permissions..."
    chown -R postgres:postgres "${PGDATA}"
else
    echo "New database - PGDATA will be created by initdb"
    # Ensure parent directory exists with correct permissions
    mkdir -p "$(dirname "${PGDATA}")"
    chown -R postgres:postgres "$(dirname "${PGDATA}")"
fi

# Create pgBackRest directories if enabled
if [ -n "${PGBACKREST_STANZA}" ]; then
    echo "Creating pgBackRest directories..."
    mkdir -p \
        /var/log/pgbackrest \
        /var/lib/pgbackrest \
        /var/spool/pgbackrest \
        /etc/pgbackrest \
        /etc/pgbackrest/conf.d \
        /tmp/pgbackrest

    chown -R postgres:postgres \
        /var/log/pgbackrest \
        /var/lib/pgbackrest \
        /var/spool/pgbackrest \
        /etc/pgbackrest \
        /tmp/pgbackrest 2>/dev/null || true
fi

# Create SSL directory
mkdir -p /etc/postgresql/ssl
chown -R postgres:postgres /etc/postgresql/ssl

echo "Directory setup completed."
