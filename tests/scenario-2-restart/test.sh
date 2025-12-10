#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "SCENARIO 2: Restart (Existing Database)"
echo "=========================================="
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker compose down -v --remove-orphans 2>/dev/null || true
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Clean start
echo "Step 1: Cleaning previous test..."
cleanup
sleep 2

# Build and start
echo ""
echo "Step 2: Building and starting containers (first time)..."
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
echo "Step 4: Waiting for pgBackRest initialization (15s)..."
sleep 15

# Create some test data
echo ""
echo "Step 5: Creating test data..."
docker compose exec -T postgres psql -U postgres -d testdb -c "
CREATE TABLE IF NOT EXISTS test_table (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO test_table (name) VALUES ('before_restart');
"
echo "Test data created."

# Get row count before restart
ROWS_BEFORE=$(docker compose exec -T postgres psql -U postgres -d testdb -tAc "SELECT COUNT(*) FROM test_table")
echo "Rows before restart: $ROWS_BEFORE"

# Stop postgres (not down - keep volumes)
echo ""
echo "Step 6: Stopping PostgreSQL container..."
docker compose stop postgres
sleep 3

# Start again
echo ""
echo "Step 7: Starting PostgreSQL container again..."
docker compose start postgres

# Wait for postgres to be healthy
echo ""
echo "Step 8: Waiting for PostgreSQL to be healthy after restart..."
for i in {1..60}; do
    if docker compose exec -T postgres pg_isready -U postgres > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "FAILED: PostgreSQL did not become ready after restart"
        docker compose logs postgres
        exit 1
    fi
    echo "Waiting... ($i/60)"
    sleep 2
done

# Wait a bit for init-db.sh in background
sleep 10

# Test 1: Check data persisted
echo ""
echo "Test 1: Check data persisted after restart..."
ROWS_AFTER=$(docker compose exec -T postgres psql -U postgres -d testdb -tAc "SELECT COUNT(*) FROM test_table")
if [ "$ROWS_BEFORE" = "$ROWS_AFTER" ]; then
    echo "✅ PASS: Data persisted ($ROWS_AFTER rows)"
else
    echo "❌ FAIL: Data lost (before: $ROWS_BEFORE, after: $ROWS_AFTER)"
    exit 1
fi

# Test 2: Check SSL still enabled
echo ""
echo "Test 2: Check SSL still enabled..."
SSL_STATUS=$(docker compose exec -T postgres psql -U postgres -tAc "SHOW ssl")
if [ "$SSL_STATUS" = "on" ]; then
    echo "✅ PASS: SSL is still enabled"
else
    echo "❌ FAIL: SSL is not enabled after restart"
    exit 1
fi

# Test 3: Check archive_mode still on
echo ""
echo "Test 3: Check archive_mode still on..."
ARCHIVE_MODE=$(docker compose exec -T postgres psql -U postgres -tAc "SHOW archive_mode")
if [ "$ARCHIVE_MODE" = "on" ]; then
    echo "✅ PASS: archive_mode is still on"
else
    echo "❌ FAIL: archive_mode is not on after restart"
    exit 1
fi

# Test 4: Check stanza still exists
echo ""
echo "Test 4: Check stanza still exists..."
if docker compose exec -T postgres su-exec postgres pgbackrest --stanza=test-scenario2 info > /dev/null 2>&1; then
    echo "✅ PASS: Stanza still exists"
else
    echo "❌ FAIL: Stanza not found after restart"
    exit 1
fi

# Test 5: Check cron is running
echo ""
echo "Test 5: Check cron restarted..."
if docker compose exec -T postgres pgrep crond > /dev/null 2>&1; then
    echo "✅ PASS: crond is running after restart"
else
    echo "❌ FAIL: crond is not running after restart"
    exit 1
fi

# Test 6: Stanza not duplicated (idempotent)
echo ""
echo "Test 6: Check init-db.sh is idempotent..."
LOG_CONTENT=$(docker compose exec -T postgres cat /var/log/pgbackrest-init.log 2>/dev/null || echo "")
if echo "$LOG_CONTENT" | grep -q "already exists"; then
    echo "✅ PASS: init-db.sh detected existing stanza (idempotent)"
else
    echo "⚠️  WARN: Could not verify idempotency from logs"
fi

echo ""
echo "=========================================="
echo "SCENARIO 2: ALL TESTS PASSED! ✅"
echo "=========================================="
