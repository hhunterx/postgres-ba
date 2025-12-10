#!/bin/bash
set -e

# Initialize pgBackRest stanza and perform initial backup
# This runs ONLY during first database initialization (via /docker-entrypoint-initdb.d/)
# 
# NOTE: During initdb, the temporary PostgreSQL server does NOT have archive_mode=on
# because postgresql.auto.conf is only read on server start, not during initdb.
# 
# Therefore, we schedule init-db.sh to run in background after the server restarts.

echo "=========================================="
echo "pgBackRest Stanza Initialization (Scheduled)"
echo "=========================================="

# Only run if stanza is configured
if [ -z "${PGBACKREST_STANZA}" ]; then
    echo "pgBackRest not configured (PGBACKREST_STANZA not set). Skipping."
    exit 0
fi

# Skip in replica mode (replicas don't manage backups)
if [ "${PG_MODE}" = "replica" ]; then
    echo "Replica mode detected. Skipping pgBackRest initialization."
    exit 0
fi

echo "Stanza: ${PGBACKREST_STANZA}"
echo ""
echo "NOTE: pgBackRest stanza creation and initial backup will run"
echo "automatically after PostgreSQL restarts with WAL archiving enabled."
echo ""

# Schedule init-db.sh to run after PostgreSQL restarts
# The docker-entrypoint.sh will restart PostgreSQL after running all initdb.d scripts
# We schedule with nohup to survive the process restart
if [ -f /usr/local/bin/init-db.sh ]; then
    echo "Scheduling pgBackRest initialization to run in 15 seconds..."
    (
        # Wait for PostgreSQL to restart with archive_mode=on
        sleep 15
        
        # Verify PostgreSQL is ready
        for i in {1..30}; do
            if pg_isready -U "${POSTGRES_USER:-postgres}" > /dev/null 2>&1; then
                break
            fi
            sleep 2
        done
        
        echo "Starting pgBackRest stanza initialization..."
        /usr/local/bin/init-db.sh >> /var/log/pgbackrest-init.log 2>&1 || true
        echo "pgBackRest initialization completed."
    ) &
    disown
fi

echo "Check /var/log/pgbackrest-init.log for initialization progress."
echo ""
