#!/bin/bash
set -e

# Configure pgBackRest and apply settings
# This runs on EVERY container start once (always)

echo "Applying pgBackRest configuration..."

# Configure pgBackRest if enabled (and not in replica mode)
# Note: We need pgBackRest configured even for restore mode (for restore_command)
if [ -n "${PGBACKREST_STANZA}" ] && [ "${PG_MODE}" != "replica" ]; then
    echo "Configuring pgBackRest for stanza '${PGBACKREST_STANZA}'..."
    /usr/local/bin/configure-pgbackrest.sh
fi
 
echo "pgBackRest configuration completed."
