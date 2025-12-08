#!/bin/bash
set -e

echo "Configuring pgBackRest..."

# Create pgBackRest configuration file
cat > /etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-type=s3
repo1-s3-bucket=${S3_BUCKET}
repo1-s3-endpoint=${S3_ENDPOINT:-s3.amazonaws.com}
repo1-s3-region=${S3_REGION:-us-east-1}
repo1-s3-key=${S3_ACCESS_KEY}
repo1-s3-key-secret=${S3_SECRET_KEY}
repo1-path=${S3_PATH:-/pgbackrest}
repo1-retention-full=${RETENTION_FULL:-4}
repo1-retention-diff=${RETENTION_DIFF:-4}

process-max=${PGBACKREST_PROCESS_MAX:-4}
log-level-console=info
log-level-file=debug
start-fast=y
delta=y

[${PGBACKREST_STANZA}]
pg1-path=${PGDATA}
pg1-port=${PGPORT:-5432}
pg1-socket-path=/var/run/postgresql
EOF

chmod 640 /etc/pgbackrest/pgbackrest.conf

echo "pgBackRest configuration completed."
