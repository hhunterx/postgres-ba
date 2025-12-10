#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "SCENARIO 4: Replica Mode"
echo "=========================================="
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker compose --profile replica down -v --remove-orphans 2>/dev/null || true
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

# Wait for primary to be healthy
echo ""
echo "Step 3: Waiting for primary PostgreSQL to be healthy..."
for i in {1..60}; do
    if docker compose exec -T postgres-primary pg_isready -U postgres > /dev/null 2>&1; then
        echo "Primary PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "FAILED: Primary PostgreSQL did not become ready in time"
        docker compose logs postgres-primary
        exit 1
    fi
    echo "Waiting... ($i/60)"
    sleep 2
done

# Wait for init-db.sh to complete
echo ""
echo "Step 4: Waiting for pgBackRest initialization (15s)..."
sleep 15

# Create test data on primary
echo ""
echo "Step 5: Creating test data on primary..."
docker compose exec -T postgres-primary psql -U postgres -d testdb -c "
CREATE TABLE IF NOT EXISTS replication_test (
    id SERIAL PRIMARY KEY,
    value VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO replication_test (value) VALUES ('primary_data_1');
"
echo "Test data created on primary."

# Start replica
echo ""
echo "Step 6: Starting replica container..."
docker compose --profile replica up -d postgres-replica

# Wait for replica to be healthy
echo ""
echo "Step 7: Waiting for replica PostgreSQL to be healthy..."
for i in {1..90}; do
    if docker compose exec -T postgres-replica pg_isready -U postgres > /dev/null 2>&1; then
        echo "Replica PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 90 ]; then
        echo "FAILED: Replica PostgreSQL did not become ready in time"
        docker compose logs postgres-replica
        exit 1
    fi
    echo "Waiting... ($i/90)"
    sleep 2
done

# Wait for replication to sync
echo ""
echo "Step 8: Waiting for replication to sync (10s)..."
sleep 10

# Test 1: Check replica is in recovery mode
echo ""
echo "Test 1: Check replica is in recovery mode..."
IS_REPLICA=$(docker compose exec -T postgres-replica psql -U postgres -tAc "SELECT pg_is_in_recovery()")
if [ "$IS_REPLICA" = "t" ]; then
    echo "✅ PASS: Replica is in recovery mode"
else
    echo "❌ FAIL: Replica is not in recovery mode"
    exit 1
fi

# Test 2: Check primary is NOT in recovery mode
echo ""
echo "Test 2: Check primary is not in recovery mode..."
IS_PRIMARY=$(docker compose exec -T postgres-primary psql -U postgres -tAc "SELECT pg_is_in_recovery()")
if [ "$IS_PRIMARY" = "f" ]; then
    echo "✅ PASS: Primary is not in recovery mode"
else
    echo "❌ FAIL: Primary is in recovery mode"
    exit 1
fi

# Test 3: Check data replicated
echo ""
echo "Test 3: Check data replicated to replica..."
REPLICA_DATA=$(docker compose exec -T postgres-replica psql -U postgres -d testdb -tAc "SELECT value FROM replication_test WHERE value = 'primary_data_1'" 2>/dev/null || echo "")
if [ "$REPLICA_DATA" = "primary_data_1" ]; then
    echo "✅ PASS: Data replicated to replica"
else
    echo "❌ FAIL: Data not replicated"
    echo "   Expected: primary_data_1"
    echo "   Got: $REPLICA_DATA"
    exit 1
fi

# Test 4: Insert more data and check replication
echo ""
echo "Test 4: Check live replication..."
docker compose exec -T postgres-primary psql -U postgres -d testdb -c "INSERT INTO replication_test (value) VALUES ('primary_data_2');"
sleep 3
REPLICA_DATA2=$(docker compose exec -T postgres-replica psql -U postgres -d testdb -tAc "SELECT value FROM replication_test WHERE value = 'primary_data_2'" 2>/dev/null || echo "")
if [ "$REPLICA_DATA2" = "primary_data_2" ]; then
    echo "✅ PASS: Live replication working"
else
    echo "❌ FAIL: Live replication not working"
    exit 1
fi

# Test 5: Replica should NOT have cron running (no backups)
echo ""
echo "Test 5: Check replica does not run cron (no backups)..."
if docker compose exec -T postgres-replica pgrep crond > /dev/null 2>&1; then
    echo "❌ FAIL: crond is running on replica (should not)"
    exit 1
else
    echo "✅ PASS: crond is not running on replica"
fi

# Test 6: Primary should have cron running
echo ""
echo "Test 6: Check primary has cron running..."
if docker compose exec -T postgres-primary pgrep crond > /dev/null 2>&1; then
    echo "✅ PASS: crond is running on primary"
else
    echo "❌ FAIL: crond is not running on primary"
    exit 1
fi

# Test 7: Replica should have SSL
echo ""
echo "Test 7: Check SSL on replica..."
SSL_STATUS=$(docker compose exec -T postgres-replica psql -U postgres -tAc "SHOW ssl")
if [ "$SSL_STATUS" = "on" ]; then
    echo "✅ PASS: SSL is enabled on replica"
else
    echo "❌ FAIL: SSL is not enabled on replica"
    exit 1
fi

echo ""
echo "=========================================="
echo "SCENARIO 4: ALL TESTS PASSED! ✅"
echo "=========================================="
