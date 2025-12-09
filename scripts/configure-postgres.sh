#!/bin/bash
set -e

echo "Configuring PostgreSQL..."

# Configure pgBackRest-specific settings only if stanza is defined
if [ "${PGBACKREST_STANZA}" != "" ]; then
    echo "Configuring for pgBackRest with WAL archiving..."
    cat >> ${PGDATA}/postgresql.conf <<EOF

# pgBackRest Configuration
archive_mode = on
archive_command = 'pgbackrest --stanza=${PGBACKREST_STANZA} archive-push %p'
archive_timeout = 60

# WAL Configuration
wal_level = replica
max_wal_senders = ${MAX_WAL_SENDERS:-10}
max_replication_slots = ${MAX_REPLICATION_SLOTS:-10}
EOF
fi

# Always configure SSL
cat >> ${PGDATA}/postgresql.conf <<EOF

# SSL Configuration
ssl = on
ssl_cert_file = '/var/lib/postgresql/ssl/server.crt'
ssl_key_file = '/var/lib/postgresql/ssl/server.key'
ssl_ca_file = '/var/lib/postgresql/ssl/root.crt'

# Logging
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
log_error_verbosity = default

# Performance
shared_buffers = ${SHARED_BUFFERS:-1GB}
effective_cache_size = ${EFFECTIVE_CACHE_SIZE:-3GB}
maintenance_work_mem = ${MAINTENANCE_WORK_MEM:-256MB}
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = ${WORK_MEM:-16MB}
min_wal_size = 1GB
max_wal_size = 4GB
EOF

# Set pg_hba.conf for replication only if pgBackRest is configured
if [ "${PGBACKREST_STANZA}" != "" ]; then
    cat >> ${PGDATA}/pg_hba.conf <<EOF

# Replication connections - SSL required
hostssl replication     all             0.0.0.0/0               scram-sha-256
EOF
fi

echo "PostgreSQL configuration completed."
