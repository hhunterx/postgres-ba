#!/bin/bash
# Wrapper para executar init-db.sh preservando variáveis de ambiente

# Read environment variables from /proc/1/environ (main process)
eval $(cat /proc/1/environ | tr '\0' '\n' | grep -E '^(POSTGRES_USER|POSTGRES_DB|POSTGRES_PASSWORD|PGBACKREST_STANZA)=' | sed 's/^/export /')

# Run as postgres user with environment variables
su postgres -c "export POSTGRES_USER='${POSTGRES_USER}'; export POSTGRES_DB='${POSTGRES_DB}'; export PGBACKREST_STANZA='${PGBACKREST_STANZA}'; bash /docker-entrypoint-initdb.d/init-db.sh"
