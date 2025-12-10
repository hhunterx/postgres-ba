#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "POSTGRES-BA TEST SUITE"
echo "=========================================="
echo ""
echo "This will run all scenario tests."
echo "Each scenario is isolated and will not interfere with others."
echo ""

FAILED_TESTS=()
PASSED_TESTS=()

run_test() {
    local scenario=$1
    local name=$2
    
    echo ""
    echo "=========================================="
    echo "Running: $name"
    echo "=========================================="
    echo ""
    
    if bash "$SCRIPT_DIR/$scenario/test.sh"; then
        PASSED_TESTS+=("$name")
        echo ""
        echo "✅ $name: PASSED"
    else
        FAILED_TESTS+=("$name")
        echo ""
        echo "❌ $name: FAILED"
    fi
    
    echo ""
    echo "Waiting 5s before next test..."
    sleep 5
}

# Run all scenarios
run_test "scenario-1-new-db" "Scenario 1: New Database"
run_test "scenario-2-restart" "Scenario 2: Restart"
run_test "scenario-3-restore" "Scenario 3: Restore from S3"
run_test "scenario-4-replica" "Scenario 4: Replica Mode"
run_test "scenario-5-existing-db" "Scenario 5: Existing DB Migration"

# Summary
echo ""
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo ""

echo "Passed: ${#PASSED_TESTS[@]}"
for test in "${PASSED_TESTS[@]}"; do
    echo "  ✅ $test"
done

echo ""
echo "Failed: ${#FAILED_TESTS[@]}"
for test in "${FAILED_TESTS[@]}"; do
    echo "  ❌ $test"
done

echo ""
if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo "=========================================="
    echo "ALL TESTS PASSED! 🎉"
    echo "=========================================="
    exit 0
else
    echo "=========================================="
    echo "SOME TESTS FAILED! ❌"
    echo "=========================================="
    exit 1
fi
