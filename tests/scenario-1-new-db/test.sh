#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "SCENARIO 1: First Start (New Database)"
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
echo "Step 2: Building and starting containers..."
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

# Wait for init-db.sh to complete (runs in background after 10s)
echo ""
echo "Step 4: Waiting for pgBackRest initialization (15s)..."
sleep 15

# Test 1: Check if database was created
echo ""
echo "Test 1: Check database exists..."
if docker compose exec -T postgres psql -U postgres -d testdb -c "SELECT 1" > /dev/null 2>&1; then
    echo "✅ PASS: Database 'testdb' exists"
else
    echo "❌ FAIL: Database 'testdb' not found"
    exit 1
fi

# Test 2: Check SSL is enabled
echo ""
echo "Test 2: Check SSL is enabled..."
SSL_STATUS=$(docker compose exec -T postgres psql -U postgres -tAc "SHOW ssl")
if [ "$SSL_STATUS" = "on" ]; then
    echo "✅ PASS: SSL is enabled"
else
    echo "❌ FAIL: SSL is not enabled (status: $SSL_STATUS)"
    exit 1
fi

# Test 3: Check archive_mode is on
echo ""
echo "Test 3: Check archive_mode is on..."
ARCHIVE_MODE=$(docker compose exec -T postgres psql -U postgres -tAc "SHOW archive_mode")
if [ "$ARCHIVE_MODE" = "on" ]; then
    echo "✅ PASS: archive_mode is on"
else
    echo "❌ FAIL: archive_mode is not on (status: $ARCHIVE_MODE)"
    exit 1
fi

# Test 4: Check archive_command uses pgbackrest
echo ""
echo "Test 4: Check archive_command..."
ARCHIVE_CMD=$(docker compose exec -T postgres psql -U postgres -tAc "SHOW archive_command")
if [[ "$ARCHIVE_CMD" == *"pgbackrest"* ]]; then
    echo "✅ PASS: archive_command uses pgbackrest"
else
    echo "❌ FAIL: archive_command does not use pgbackrest"
    echo "   Got: $ARCHIVE_CMD"
    exit 1
fi

# Test 5: Check stanza exists
echo ""
echo "Test 5: Check pgBackRest stanza exists..."
if docker compose exec -T -u postgres postgres pgbackrest --stanza=test-scenario1 info > /dev/null 2>&1; then
    echo "✅ PASS: Stanza 'test-scenario1' exists"
else
    echo "❌ FAIL: Stanza not found"
    exit 1
fi

# Test 6: Check backup exists
echo ""
echo "Test 6: Check backup exists..."
BACKUP_INFO=$(docker compose exec -T -u postgres postgres pgbackrest --stanza=test-scenario1 info --output=json 2>/dev/null)
if echo "$BACKUP_INFO" | grep -q '"backup"'; then
    echo "✅ PASS: Backup exists"
    echo ""
    echo "Backup info:"
    docker compose exec -T -u postgres postgres pgbackrest --stanza=test-scenario1 info
else
    echo "❌ FAIL: No backup found"
    exit 1
fi

# Test 7: Check cron is running
echo ""
echo "Test 7: Check cron is running..."
if docker compose exec -T postgres pgrep crond > /dev/null 2>&1; then
    echo "✅ PASS: crond is running"
else
    echo "❌ FAIL: crond is not running"
    exit 1
fi

echo ""
echo "=========================================="
echo "SCENARIO 1: ALL TESTS PASSED! ✅"
echo "=========================================="
