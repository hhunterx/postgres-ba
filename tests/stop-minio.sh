#!/bin/bash
set -e

echo "Stopping MinIO service..."
cd "$(dirname "$0")"
docker-compose down

echo ""
echo "MinIO service stopped."
