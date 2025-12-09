#!/bin/bash
set -e

# Wrapper entrypoint para compatibilidade com postgres:18-alpine
# Executa setup de pgBackRest/SSL/cron primeiro, depois chama docker-entrypoint.sh oficial

echo "=========================================="
echo "PostgreSQL with pgBackRest - Initialization"
echo "=========================================="

# Ensure PostgreSQL data directory parent has correct permissions
mkdir -p /var/lib/postgresql/data
chown -R postgres:postgres /var/lib/postgresql/data

# Configure pgBackRest (if enabled)
if [ "${PGBACKREST_STANZA}" != "" ]; then
    echo "Configuring pgBackRest..."
    /usr/local/bin/configure-pgbackrest.sh || true
    
    # Setup cron jobs for backups
    echo "Setting up backup cron jobs..."
    /usr/local/bin/setup-cron.sh || true
    
    # Start cron in background
    crond -b -l 8 || true
    
    # Ensure proper permissions
    chown -R postgres:postgres /etc/pgbackrest /var/log/pgbackrest /var/lib/pgbackrest /var/spool/pgbackrest 2>/dev/null || true
fi

# Configure SSL certificates with CA
if [ -f /usr/local/bin/configure-ssl-with-ca.sh ]; then
    echo "Configuring SSL certificates..."
    /usr/local/bin/configure-ssl-with-ca.sh || true
fi

echo "Setup completed. Starting PostgreSQL..."
echo ""

# Call the official PostgreSQL entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
