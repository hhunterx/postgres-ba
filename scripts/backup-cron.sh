#!/bin/bash

# Backup script with logging
LOG_FILE="/var/log/pgbackrest/backup-cron.log"
BACKUP_TYPE=$1

# Source environment variables from pgBackRest config
if [ -f /etc/pgbackrest/pgbackrest.conf ]; then
    PGBACKREST_STANZA=$(grep '^\[' /etc/pgbackrest/pgbackrest.conf | grep -v '^\[global\]' | sed 's/\[\(.*\)\]/\1/' | head -1)
fi

# Fallback to default if not found
PGBACKREST_STANZA=${PGBACKREST_STANZA:-main}

echo "========================================" >> $LOG_FILE
echo "$(date): Starting ${BACKUP_TYPE} backup" >> $LOG_FILE
echo "========================================" >> $LOG_FILE

# Perform backup
pgbackrest --stanza=${PGBACKREST_STANZA} \
    --type=${BACKUP_TYPE} \
    --log-level-console=info \
    backup >> $LOG_FILE 2>&1

if [ $? -eq 0 ]; then
    echo "$(date): ${BACKUP_TYPE} backup completed successfully" >> $LOG_FILE
else
    echo "$(date): ${BACKUP_TYPE} backup FAILED" >> $LOG_FILE
    exit 1
fi

# Show backup info
echo "========================================" >> $LOG_FILE
echo "$(date): Current backup information" >> $LOG_FILE
echo "========================================" >> $LOG_FILE
pgbackrest --stanza=${PGBACKREST_STANZA} info >> $LOG_FILE 2>&1

echo "" >> $LOG_FILE
