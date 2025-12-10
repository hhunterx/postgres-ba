#!/bin/bash
set -e

echo "Setting up cron jobs for backups..."

# Create crontab file
CRON_FILE="/tmp/postgres-crontab"

cat > $CRON_FILE <<EOF
# PostgreSQL Backup Schedule

# Incremental backups every 30 minutes
*/30 * * * * su - postgres -c '/usr/local/bin/backup-cron.sh incr'

# Differential backup once a day at 2 AM
0 2 * * * su - postgres -c '/usr/local/bin/backup-cron.sh diff'

# Full backup once a week on Sunday at 3 AM
0 3 * * 0 su - postgres -c '/usr/local/bin/backup-cron.sh full'
EOF

# Install crontab for root user
crontab $CRON_FILE

# Remove temp file
rm $CRON_FILE

echo "Cron jobs installed successfully!"
echo "Schedule:"
echo "  - Incremental: Every 30 minutes"
echo "  - Differential: Daily at 2 AM"
echo "  - Full: Weekly on Sunday at 3 AM"
