#!/bin/bash
set -e

echo "Starting MinIO service for tests..."
cd "$(dirname "$0")"
docker-compose up -d

echo ""
echo "Waiting for MinIO to be ready..."
sleep 5

echo ""
echo "MinIO is ready!"
echo "- MinIO Console: https://localhost:9001 (minioadmin/minioadmin)"
echo "- MinIO S3 API: https://localhost:9000"
echo ""
echo "Buckets created:"
echo "  - scenario1 (for scenario-1-new-db)"
echo "  - scenario2 (for scenario-2-restart)"
echo "  - scenario3 (for scenario-3-restore)"
echo "  - scenario4 (for scenario-4-replica)"
echo "  - scenario5 (for scenario-5-existing-db)"
echo ""
echo "You can now run individual test scenarios."
