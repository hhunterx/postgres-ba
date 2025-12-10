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

# Wait for init-db.sh to complete
echo ""
echo "Step 4: Waiting for pgBackRest initialization (20s)..."
sleep 20

# Create unique test data
echo ""
echo "Step 5: Creating unique test data..."
UNIQUE_ID=$(date +%s)
docker compose exec -T postgres psql -U postgres -d testdb -c "
CREATE TABLE IF NOT EXISTS restore_test (
    id SERIAL PRIMARY KEY,
    unique_value VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO restore_test (unique_value) VALUES ('restore_marker_${UNIQUE_ID}');
"
echo "Test data created with marker: restore_marker_${UNIQUE_ID}"

# Force a checkpoint and archive
echo ""
echo "Step 6: Forcing checkpoint and WAL archive..."
docker compose exec -T postgres psql -U postgres -c "CHECKPOINT;"
sleep 5

# Create another backup to ensure data is backed up
echo ""
echo "Step 7: Creating backup with test data..."
docker compose exec -T postgres su-exec postgres pgbackrest --stanza=test-scenario3 --type=full backup || {
    echo "Backup failed, checking logs..."
    exit 1
}
echo "Backup completed."

# Show backup info
echo ""
echo "Backup info:"
docker compose exec -T postgres su-exec postgres pgbackrest --stanza=test-scenario3 info

# Stop primary
echo ""
echo "Step 8: Stopping primary container..."
docker compose stop postgres

# Start restore container
echo ""
echo "Step 9: Starting restore container..."
docker compose --profile restore up -d postgres-restore

# Wait for restore postgres to be healthy
echo ""
echo "Step 10: Waiting for restored PostgreSQL to be healthy..."
for i in {1..120}; do
    if docker compose exec -T postgres-restore pg_isready -U postgres > /dev/null 2>&1; then
        echo "Restored PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 120 ]; then
        echo "FAILED: Restored PostgreSQL did not become ready in time"
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

echo ""
echo "=========================================="
echo "SCENARIO 3: ALL TESTS PASSED! ✅"
echo "=========================================="
