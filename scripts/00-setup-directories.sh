#!/bin/bash
set -e

# Setup directories and permissions
# This runs BEFORE database initialization on every container start once (always)

echo "Setting up directories and permissions..."

PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}

# Ensure PostgreSQL data directory has correct permissions
mkdir -p "${PGDATA}"
chown -R postgres:postgres "${PGDATA}"

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
    
    # Create log file with correct permissions
    touch /var/log/pgbackrest-init.log
    
    chown -R postgres:postgres \
        /var/log/pgbackrest \
        /var/lib/pgbackrest \
        /var/spool/pgbackrest \
        /etc/pgbackrest \
        /tmp/pgbackrest \
        /var/log/pgbackrest-init.log 2>/dev/null || true
fi

# Create SSL directory
mkdir -p /etc/postgresql/ssl
chown -R postgres:postgres /etc/postgresql/ssl

echo "Directory setup completed."
