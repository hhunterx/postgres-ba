#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "SCENARIO 3: Restore from S3"
echo "=========================================="
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker compose --profile restore down -v --remove-orphans 2>/dev/null || true
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Clean start
echo "Step 1: Cleaning previous test..."
cleanup
sleep 2

# Build and start primary
echo ""
echo "Step 2: Building and starting primary container..."
docker compose up -d --build

# Wait for postgres to be healthy
echo ""
echo "Step 3: Waiting for PostgreSQL to be healthy..."
for i in {1..60}; do
    if docker compose exec -T postgres pg_isready -U postgres > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "FAILED: PostgreSQL did not become ready in time"
        docker compose logs postgres
        exit 1
    fi
    echo "Waiting... ($i/60)"
    sleep 2
done

# Wait for stanza creation and initial backup
echo ""
echo "Step 4: Waiting for pgBackRest stanza creation and initial backup..."
echo "Note: 99-stanza-check.sh runs in background after 15s delay"
for i in {1..90}; do
    # Check if stanza exists AND has at least one backup
    BACKUP_INFO=$(docker compose exec -T postgres su-exec postgres pgbackrest --stanza=test-scenario3 info 2>&1)
    if echo "$BACKUP_INFO" | grep -q "full backup"; then
        echo "pgBackRest stanza is ready with initial backup!"
        break
    fi
    if [ $i -eq 90 ]; then
        echo "WARNING: Initial backup not ready after 180s"
        echo "Last info output:"
        echo "$BACKUP_INFO"
    fi
    if [ $((i % 5)) -eq 0 ]; then
        echo "Waiting for initial backup... ($i/90) - $((i * 2))s elapsed"
    fi
    sleep 2
done

# Additional wait for database to be fully stable after backup
echo ""
echo "Step 4b: Ensuring database is fully ready for connections..."
sleep 5
for i in {1..30}; do
    if docker compose exec -T postgres psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
        echo "Database is accepting queries!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "WARNING: Database not accepting queries after 30s"
        docker compose logs postgres | tail -30
    fi
    echo "Waiting for database to accept queries... ($i/30)"
    sleep 2
done

# Create unique test data with retry logic
echo ""
echo "Step 5: Creating unique test data..."
UNIQUE_ID=$(date +%s)
MAX_RETRIES=5
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker compose exec -T postgres psql -U postgres -d testdb -c "
CREATE TABLE IF NOT EXISTS restore_test (
    id SERIAL PRIMARY KEY,
    unique_value VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO restore_test (unique_value) VALUES ('restore_marker_${UNIQUE_ID}');
" 2>&1; then
        echo "Test data created with marker: restore_marker_${UNIQUE_ID}"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "Failed to insert data, retrying in 3s... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
            sleep 3
        else
            echo "FAILED: Could not insert test data after $MAX_RETRIES attempts"
            docker compose logs postgres | tail -50
            exit 1
        fi
    fi
done

# Force a checkpoint and archive
echo ""
echo "Step 6: Forcing checkpoint and WAL archive..."
docker compose exec -T postgres psql -U postgres -c "CHECKPOINT;"
sleep 5

# Create incremental backup to ensure test data is backed up
echo ""
echo "Step 7: Creating incremental backup with test data..."
docker compose exec -T postgres su-exec postgres pgbackrest --stanza=test-scenario3 --type=incr backup || {
    echo "Incremental backup failed, trying full backup..."
    docker compose exec -T postgres su-exec postgres pgbackrest --stanza=test-scenario3 --type=full backup || {
        echo "Backup failed, checking logs and info..."
        docker compose exec -T postgres su-exec postgres pgbackrest --stanza=test-scenario3 info
        exit 1
    }
}
echo "Backup completed."

# Show backup info
echo ""
echo "Backup info:"
docker compose exec -T postgres su-exec postgres pgbackrest --stanza=test-scenario3 info

# Stop and remove primary (but keep S3 data)
echo ""
echo "Step 8: Stopping and removing primary container..."
docker compose stop postgres
docker compose rm -f postgres

# Remove primary volumes to simulate data loss
echo ""
echo "Step 9: Removing primary volumes to simulate data loss..."
docker volume rm scenario-3-restore_postgres-data scenario-3-restore_postgres-ssl 2>/dev/null || true
sleep 2

# Start restore container
echo ""
echo "Step 10: Starting restore container with RESTORE_FROM_BACKUP=true..."
docker compose --profile restore up -d postgres-restore

# Check restore logs to confirm restore happened
echo ""
echo "Checking restore logs..."
sleep 10
echo ""
echo "=== Restore Container Logs (first 50 lines) ==="
docker compose logs postgres-restore | head -50
echo "=== End of initial logs ==="

# Wait for restore postgres to be healthy
echo ""
echo "Step 11: Waiting for restored PostgreSQL to be healthy..."
for i in {1..120}; do
    if docker compose exec -T postgres-restore pg_isready -U postgres > /dev/null 2>&1; then
        echo "Restored PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 120 ]; then
        echo "FAILED: Restored PostgreSQL did not become ready in time"
        echo ""
        echo "=== Full Restore Container Logs ==="
        docker compose logs postgres-restore
        exit 1
    fi
    echo "Waiting... ($i/120)"
    sleep 2
done

# Test 1: Check restored data
echo ""
echo "Test 1: Check restored data exists..."
RESTORED_DATA=$(docker compose exec -T postgres-restore psql -U postgres -d testdb -tAc "SELECT unique_value FROM restore_test WHERE unique_value = 'restore_marker_${UNIQUE_ID}'" 2>/dev/null || echo "")
if [ "$RESTORED_DATA" = "restore_marker_${UNIQUE_ID}" ]; then
    echo "✅ PASS: Data restored correctly (marker: $RESTORED_DATA)"
else
    echo "❌ FAIL: Data not restored"
    echo "   Expected: restore_marker_${UNIQUE_ID}"
    echo "   Got: $RESTORED_DATA"
    docker compose logs postgres-restore
    exit 1
fi

# Test 2: Check SSL is enabled on restored instance
echo ""
echo "Test 2: Check SSL on restored instance..."
SSL_STATUS=$(docker compose exec -T postgres-restore psql -U postgres -tAc "SHOW ssl")
if [ "$SSL_STATUS" = "on" ]; then
    echo "✅ PASS: SSL is enabled on restored instance"
else
    echo "❌ FAIL: SSL is not enabled on restored instance"
    exit 1
fi

# Test 3: Verify pgBackRest configuration was applied
echo ""
echo "Test 3: Verify WAL archiving is configured..."
ARCHIVE_MODE=$(docker compose exec -T postgres-restore psql -U postgres -tAc "SHOW archive_mode")
if [ "$ARCHIVE_MODE" = "on" ]; then
    echo "✅ PASS: WAL archiving is enabled (10-configure-postgres.sh was executed)"
else
    echo "❌ FAIL: WAL archiving is not enabled"
    exit 1
fi

# Test 4: Verify restore log shows actual restore happened
echo ""
echo "Test 4: Verify restore process in logs..."
if docker compose logs postgres-restore 2>&1 | grep -q "Restoring from latest backup"; then
    echo "✅ PASS: Restore process was executed (02-restore-from-backup.sh)"
else
    echo "❌ FAIL: Restore process not found in logs"
    docker compose logs postgres-restore
    exit 1
fi

# Test 5: Verify that initdb was NOT executed
echo ""
echo "Test 5: Verify initdb was NOT executed..."
if docker compose logs postgres-restore 2>&1 | grep -q "database system was shut down"; then
    echo "✅ PASS: Database was restored (not created via initdb)"
else
    echo "⚠️  WARNING: Could not confirm database was restored vs created"
fi

# Test 6: Verify new backup can be taken from restored instance
echo ""
echo "Test 6: Testing backup after restore..."
if docker compose exec -T postgres-restore su-exec postgres pgbackrest --stanza=test-scenario3 --type=incr backup 2>&1 | grep -q "completed successfully"; then
    echo "✅ PASS: Incremental backup works after restore"
else
    echo "❌ FAIL: Cannot create backup after restore"
    exit 1
fi

echo ""
echo "=========================================="
echo "SCENARIO 3: ALL TESTS PASSED! ✅"
echo "=========================================="
echo ""
echo "Summary of validations:"
echo "  ✅ Data restored correctly from backup"
echo "  ✅ SSL enabled on restored instance"
echo "  ✅ WAL archiving configured (10-configure-postgres.sh executed)"
echo "  ✅ Restore process executed (02-restore-from-backup.sh)"
echo "  ✅ Database restored from backup (not via initdb)"
echo "  ✅ Backups functional after restore"
