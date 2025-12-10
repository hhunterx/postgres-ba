#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "SCENARIO 5: Existing Database Migration"
echo "=========================================="
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker compose --profile official --profile ba down -v --remove-orphans 2>/dev/null || true
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Clean start
echo "Step 1: Cleaning previous test..."
cleanup
sleep 2

# Start minio first
echo ""
echo "Step 2: Starting MinIO..."
docker compose up -d minio minio-setup
sleep 5

# Start official postgres to create database
echo ""
echo "Step 3: Starting official postgres:18-alpine image..."
docker compose --profile official up -d postgres-official

# Wait for official postgres to be healthy
echo ""
echo "Step 4: Waiting for official PostgreSQL to be healthy..."
for i in {1..60}; do
    if docker compose exec -T postgres-official pg_isready -U postgres > /dev/null 2>&1; then
        echo "Official PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "FAILED: Official PostgreSQL did not become ready in time"
        docker compose logs postgres-official
        exit 1
    fi
    echo "Waiting... ($i/60)"
    sleep 2
done

# Create test data with official image
echo ""
echo "Step 5: Creating test data with official postgres image..."
UNIQUE_ID=$(date +%s)
docker compose exec -T postgres-official psql -U postgres -d testdb -c "
CREATE TABLE IF NOT EXISTS migration_test (
    id SERIAL PRIMARY KEY,
    value VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO migration_test (value) VALUES ('official_data_${UNIQUE_ID}');
"
echo "Test data created with marker: official_data_${UNIQUE_ID}"

# Verify SSL is OFF in official image (default)
echo ""
echo "Step 6: Verify official image does NOT have SSL..."
SSL_OFFICIAL=$(docker compose exec -T postgres-official psql -U postgres -tAc "SHOW ssl" 2>/dev/null || echo "off")
echo "Official postgres SSL status: $SSL_OFFICIAL"

# Verify archive_mode is OFF in official image (default)
ARCHIVE_OFFICIAL=$(docker compose exec -T postgres-official psql -U postgres -tAc "SHOW archive_mode" 2>/dev/null || echo "off")
echo "Official postgres archive_mode: $ARCHIVE_OFFICIAL"

# Stop official postgres
echo ""
echo "Step 7: Stopping official postgres..."
docker compose --profile official stop postgres-official

# Start our postgres-ba image with the same volume
echo ""
echo "Step 8: Starting postgres-ba image with existing data..."
docker compose --profile ba up -d postgres-ba

# Wait for postgres-ba to be healthy
echo ""
echo "Step 9: Waiting for postgres-ba to be healthy..."
for i in {1..60}; do
    if docker compose exec -T postgres-ba pg_isready -U postgres > /dev/null 2>&1; then
        echo "postgres-ba is ready!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "FAILED: postgres-ba did not become ready in time"
        docker compose logs postgres-ba
        exit 1
    fi
    echo "Waiting... ($i/60)"
    sleep 2
done

# Wait for init-db.sh to complete
echo ""
echo "Step 10: Waiting for pgBackRest initialization (20s)..."
sleep 20

# Test 1: Check data persisted
echo ""
echo "Test 1: Check data persisted after migration..."
MIGRATED_DATA=$(docker compose exec -T postgres-ba psql -U postgres -d testdb -tAc "SELECT value FROM migration_test WHERE value = 'official_data_${UNIQUE_ID}'" 2>/dev/null || echo "")
if [ "$MIGRATED_DATA" = "official_data_${UNIQUE_ID}" ]; then
    echo "✅ PASS: Data persisted after migration"
else
    echo "❌ FAIL: Data lost during migration"
    echo "   Expected: official_data_${UNIQUE_ID}"
    echo "   Got: $MIGRATED_DATA"
    exit 1
fi

# Test 2: Check SSL is NOW enabled
echo ""
echo "Test 2: Check SSL is enabled after migration..."
SSL_STATUS=$(docker compose exec -T postgres-ba psql -U postgres -tAc "SHOW ssl")
if [ "$SSL_STATUS" = "on" ]; then
    echo "✅ PASS: SSL is now enabled"
else
    echo "❌ FAIL: SSL is not enabled after migration"
    exit 1
fi

# Test 3: Check archive_mode is NOW on
echo ""
echo "Test 3: Check archive_mode is on after migration..."
ARCHIVE_MODE=$(docker compose exec -T postgres-ba psql -U postgres -tAc "SHOW archive_mode")
if [ "$ARCHIVE_MODE" = "on" ]; then
    echo "✅ PASS: archive_mode is now on"
else
    echo "❌ FAIL: archive_mode is not on after migration"
    exit 1
fi

# Test 4: Check stanza was created
echo ""
echo "Test 4: Check pgBackRest stanza was created..."
if docker compose exec -T postgres-ba su-exec postgres pgbackrest --stanza=test-scenario5 info > /dev/null 2>&1; then
    echo "✅ PASS: Stanza was created"
else
    echo "❌ FAIL: Stanza was not created"
    echo "Checking init log..."
    docker compose exec -T postgres-ba cat /var/log/pgbackrest-init.log 2>/dev/null || true
    exit 1
fi

# Test 5: Check backup was created
echo ""
echo "Test 5: Check backup was created..."
BACKUP_INFO=$(docker compose exec -T postgres-ba su-exec postgres pgbackrest --stanza=test-scenario5 info --output=json 2>/dev/null)
if echo "$BACKUP_INFO" | grep -q '"backup"'; then
    echo "✅ PASS: Backup was created"
    echo ""
    echo "Backup info:"
    docker compose exec -T postgres-ba su-exec postgres pgbackrest --stanza=test-scenario5 info
else
    echo "❌ FAIL: No backup found"
    exit 1
fi

# Test 6: Check cron is running
echo ""
echo "Test 6: Check cron is running..."
if docker compose exec -T postgres-ba pgrep crond > /dev/null 2>&1; then
    echo "✅ PASS: crond is running"
else
    echo "❌ FAIL: crond is not running"
    exit 1
fi

echo ""
echo "=========================================="
echo "SCENARIO 5: ALL TESTS PASSED! ✅"
echo "=========================================="
echo ""
echo "Successfully migrated from official postgres:18-alpine to postgres-ba!"
echo "- Data preserved"
echo "- SSL enabled"
echo "- pgBackRest configured"
echo "- Backup created automatically"
