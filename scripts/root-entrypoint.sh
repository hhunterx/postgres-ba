#!/bin/bash
set -e

# This script runs as root to setup cron and then hands off to the main entrypoint

echo "=========================================="
echo "PostgreSQL with pgBackRest - Root Setup"
echo "=========================================="

# Ensure PostgreSQL data directory parent has correct permissions
mkdir -p /var/lib/postgresql/data
chown -R postgres:postgres /var/lib/postgresql/data

# Configure pgBackRest
echo "Configuring pgBackRest..."
/usr/local/bin/configure-pgbackrest.sh

# Ensure proper permissions
chown -R postgres:postgres /etc/pgbackrest /var/log/pgbackrest /var/lib/pgbackrest /var/spool/pgbackrest

# Setup cron jobs for backups
echo "Setting up backup cron jobs..."
/usr/local/bin/setup-cron.sh

# Start cron in background
crond -b -l 8

echo "Root setup completed. Handing off to postgres user..."
echo ""

# Now run the actual entrypoint as postgres user
exec gosu postgres /usr/local/bin/pg-entrypoint.sh "$@"
