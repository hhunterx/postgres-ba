#!/bin/bash
set -e

# Configure PostgreSQL settings after initdb
# This runs ONLY during first database initialization (via /docker-entrypoint-initdb.d/)

echo "Configuring PostgreSQL for new database..."

# Apply PostgreSQL configuration
if [ -f /usr/local/bin/configure-postgres.sh ]; then
    /usr/local/bin/configure-postgres.sh
fi

echo "PostgreSQL configuration for new database completed."
