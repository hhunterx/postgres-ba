#!/bin/bash
set -e

# Set default PGDATA if not provided
PGDATA=${PGDATA:-/var/lib/postgresql/data/pgdata}
export PGDATA

echo "Configuring pgBackRest..."
echo "Using PGDATA: $PGDATA"

# Create pgBackRest configuration file
cat > /etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-type=s3
repo1-s3-bucket=${PGBACKREST_S3_BUCKET}
repo1-s3-endpoint=${PGBACKREST_S3_ENDPOINT:-s3.amazonaws.com}
repo1-s3-region=${PGBACKREST_S3_REGION:-us-east-1}
repo1-s3-key=${PGBACKREST_S3_ACCESS_KEY}
repo1-s3-key-secret=${PGBACKREST_S3_SECRET_KEY}
repo1-path=${PGBACKREST_S3_PATH:-/pgbackrest}
repo1-retention-full=${RETENTION_FULL:-3}
repo1-retention-diff=${RETENTION_DIFF:-14}
repo1-retention-archive-type=full
repo1-retention-archive=${RETENTION_ARCHIVE:-2}
repo1-cipher-pass=x
repo1-cipher-type=aes-256-cbc
repo1-compress=gz
repo1-compress-level=3

process-max=${PGBACKREST_PROCESS_MAX:-2}
log-level-console=info
log-level-file=debug
start-fast=y
stop-auto=y
delta=y
archive-async=y

[${PGBACKREST_STANZA}]
pg1-path=${PGDATA}
pg1-port=${PGPORT:-5432}
pg1-socket-path=/var/run/postgresql
EOF

chmod 640 /etc/pgbackrest/pgbackrest.conf

echo "pgBackRest configuration completed."
