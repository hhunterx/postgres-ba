#!/bin/bash
set -e

# Configure PostgreSQL settings BEFORE initdb (for existing DBs only)
echo "Existing database detected - configuring PostgreSQL now..."

# Apply PostgreSQL configuration
if [ -f /usr/local/bin/configure-postgres.sh ]; then
    /usr/local/bin/configure-postgres.sh
fi

echo "PostgreSQL configuration for existing database completed."
