#!/bin/bash
set -e

# Configure pgBackRest and apply settings
# This runs on EVERY container start once (always)
# NOTE: Replicas do NOT configure pgBackRest as they receive WAL from primary

echo "Applying pgBackRest configuration..."

# Configure pgBackRest if enabled (and not in replica mode)
# Replicas get their WAL via streaming replication from primary
if [ -n "${PGBACKREST_STANZA}" ] && [ "${PG_MODE}" != "replica" ]; then
    echo "Configuring pgBackRest for stanza '${PGBACKREST_STANZA}'..."
    /usr/local/bin/configure-pgbackrest.sh
else
    if [ "${PG_MODE}" = "replica" ]; then
        echo "Replica mode detected - skipping pgBackRest configuration (replicas stream from primary)"
    else
        echo "pgBackRest not configured (PGBACKREST_STANZA not set)"
    fi
fi
 
echo "pgBackRest configuration completed."
