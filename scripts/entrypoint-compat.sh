#!/bin/bash
set -e

# Wrapper entrypoint para compatibilidade com postgres:18-alpine
# Executa setup de pgBackRest/SSL/cron primeiro, depois chama docker-entrypoint.sh oficial

echo "=========================================="
echo "PostgreSQL with pgBackRest - Initialization"
echo "=========================================="

# Ensure PostgreSQL data directory parent has correct permissions
PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}
mkdir -p ${PGDATA}
chown -R postgres:postgres ${PGDATA}

# Handle RESTORE from backup if requested
if [ "${RESTORE_FROM_BACKUP}" = "true" ] && [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "RESTORE_FROM_BACKUP=true detected. Attempting to restore from backup..."
    
    if [ "${PGBACKREST_STANZA}" = "" ]; then
        echo "ERROR: PGBACKREST_STANZA must be set to restore from backup"
        exit 1
    fi
    
    # Configure pgBackRest first
    /usr/local/bin/configure-pgbackrest.sh || true
    
    # Check if stanza exists
    if ! su - postgres -c "pgbackrest --stanza=${PGBACKREST_STANZA} info" > /dev/null 2>&1; then
        echo "ERROR: No backup found in S3. Cannot restore."
        exit 1
    fi
    
    echo "Restoring from latest backup..."
    su - postgres -c "pgbackrest --stanza=${PGBACKREST_STANZA} --delta --log-level-console=info restore"
    
    echo "Restore completed successfully!"
    
    # Configure PostgreSQL after restore
    /usr/local/bin/configure-postgres.sh || true
fi

# Handle REPLICA setup if requested
if [ "${PG_MODE}" = "replica" ] && [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "PG_MODE=replica detected. Setting up replica..."
    
    if [ "${PRIMARY_HOST}" = "" ]; then
        echo "ERROR: PRIMARY_HOST must be set for replica mode"
        exit 1
    fi
    
    # Wait for primary to be ready
    echo "Waiting for primary to be ready..."
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if pg_isready -h ${PRIMARY_HOST} -p ${PRIMARY_PORT:-5432} -U ${POSTGRES_USER:-postgres} > /dev/null 2>&1; then
            echo "Primary is ready!"
            break
        fi
        attempt=$((attempt + 1))
        echo "Waiting for primary... (attempt $attempt/$max_attempts)"
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "ERROR: Primary not ready after $max_attempts attempts"
        exit 1
    fi
    
    # Create replication slot on primary
    echo "Creating replication slot on primary..."
    SLOT_NAME=$(hostname | sed 's/-/_/g')
    PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${PRIMARY_HOST} -p ${PRIMARY_PORT:-5432} -U ${POSTGRES_USER:-postgres} -d postgres -c \
        "SELECT pg_create_physical_replication_slot('${SLOT_NAME}');" 2>/dev/null || \
        echo "Replication slot already exists (will try to continue anyway)"
    
    # Use pg_basebackup to clone data from primary
    echo "Cloning data from primary using pg_basebackup..."
    PGPASSWORD=${POSTGRES_PASSWORD} pg_basebackup \
        -h ${PRIMARY_HOST} \
        -p ${PRIMARY_PORT:-5432} \
        -U ${POSTGRES_USER:-postgres} \
        -D ${PGDATA} \
        -Fp \
        -Xs \
        -P \
        -R \
        -v
    
    echo "pg_basebackup completed successfully!"
    
    # Configure replication slot
    cat >> ${PGDATA}/postgresql.conf <<EOF

# Replica Configuration
primary_slot_name = '${SLOT_NAME}'
hot_standby = on
EOF
    
    echo "Replica setup completed!"
fi

# Configure pgBackRest (if enabled)
if [ "${PGBACKREST_STANZA}" != "" ]; then
    # Configuring pgBackRest
    /usr/local/bin/configure-pgbackrest.sh || true
    
    # Setup cron jobs for backups
    /usr/local/bin/setup-cron.sh || true
    
    # Start cron in background
    crond -b -l 8 || true
    
    # Ensure proper permissions
    mkdir -p /tmp/pgbackrest
    chown -R postgres:postgres /etc/pgbackrest /var/log/pgbackrest /var/lib/pgbackrest /var/spool/pgbackrest /tmp/pgbackrest 2>/dev/null || true
fi

# Configure SSL certificates with CA
if [ -f /usr/local/bin/configure-ssl-with-ca.sh ]; then
    echo "Configuring SSL certificates..."
    /usr/local/bin/configure-ssl-with-ca.sh || true
fi

# Configure PostgreSQL for pgBackRest if database exists and stanza is set
# (only for PRIMARY mode, not REPLICA or RESTORE)
if [ -s "$PGDATA/PG_VERSION" ] && [ "${PGBACKREST_STANZA}" != "" ] && [ "${PG_MODE}" != "replica" ] && [ "${RESTORE_FROM_BACKUP}" != "true" ]; then
    echo "Existing database detected with pgBackRest enabled."
    echo "Configuring PostgreSQL for pgBackRest..."
    /usr/local/bin/configure-postgres.sh || true
    
    # Mark that we need to run init-db.sh after startup
    touch /tmp/pgbackrest-needs-init
fi

echo "Setup completed. Starting PostgreSQL..."
echo ""

# Call the official PostgreSQL entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
