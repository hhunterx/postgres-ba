#!/bin/bash
set -e

# Setup PostgreSQL replica using pg_basebackup
# This runs BEFORE database initialization
# NOTE: This script is sourced, so use return instead of exit for non-error cases

PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}

# Only setup replica if explicitly requested
if [ "${PG_MODE}" != "replica" ]; then
    echo "PG_MODE is not 'replica', skipping replica setup."
    return 0 2>/dev/null || true
fi

# Skip if database already exists
if [ -s "$PGDATA/PG_VERSION" ]; then
    echo "Database already exists at $PGDATA, skipping replica setup."
    return 0 2>/dev/null || true
fi

echo "=========================================="
echo "Setting up PostgreSQL Replica"
echo "=========================================="

if [ -z "${PRIMARY_HOST}" ]; then
    echo "ERROR: PRIMARY_HOST must be set for replica mode"
    exit 1
fi

# Wait for primary to be ready
echo "Waiting for primary at ${PRIMARY_HOST}:${PRIMARY_PORT:-5432}..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if pg_isready -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT:-5432}" -U "${POSTGRES_USER:-postgres}" > /dev/null 2>&1; then
        echo "Primary is ready!"
        break
    fi
    attempt=$((attempt + 1))
    echo "Attempt $attempt/$max_attempts..."
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    echo "ERROR: Primary not ready after $max_attempts attempts"
    exit 1
fi

# Create replication slot on primary
SLOT_NAME=$(hostname | sed 's/-/_/g')
echo "Creating replication slot '${SLOT_NAME}' on primary..."

PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h "${PRIMARY_HOST}" \
    -p "${PRIMARY_PORT:-5432}" \
    -U "${POSTGRES_USER:-postgres}" \
    -d postgres \
    -c "SELECT pg_create_physical_replication_slot('${SLOT_NAME}');" 2>/dev/null || \
    echo "Replication slot may already exist, continuing..."

# Clone data from primary using pg_basebackup
echo "Cloning data from primary using pg_basebackup..."
PGPASSWORD="${POSTGRES_PASSWORD}" pg_basebackup \
    -h "${PRIMARY_HOST}" \
    -p "${PRIMARY_PORT:-5432}" \
    -U "${POSTGRES_USER:-postgres}" \
    -D "${PGDATA}" \
    -Fp \
    -Xs \
    -P \
    -R \
    -v

echo "Configuring replica settings..."
cat >> "${PGDATA}/postgresql.conf" <<EOF

# Replica Configuration
primary_slot_name = '${SLOT_NAME}'
hot_standby = on
EOF

echo "Replica setup completed successfully!"

# Signal that we've setup replica and should skip normal init
export POSTGRES_HOST_AUTH_METHOD=trust
