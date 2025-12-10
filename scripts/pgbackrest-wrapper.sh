#!/bin/bash

# pgBackRest wrapper to avoid environment variable warnings
# This script cleans up environment variables that cause warnings in pgBackRest

# Save original pgBackRest binary path
PGBACKREST_BIN="/usr/bin/pgbackrest-orig"

# Remove only the problematic variables that cause warnings
unset PGBACKREST_S3_BUCKET 2>/dev/null || true
unset PGBACKREST_S3_ENDPOINT 2>/dev/null || true  
unset PGBACKREST_S3_REGION 2>/dev/null || true
unset PGBACKREST_S3_ACCESS_KEY 2>/dev/null || true
unset PGBACKREST_S3_SECRET_KEY 2>/dev/null || true
unset PGBACKREST_S3_PATH 2>/dev/null || true
unset PGBACKREST_S3_URI_STYLE 2>/dev/null || true
unset PGBACKREST_S3_VERIFY_TLS 2>/dev/null || true

# Execute pgBackRest with all other environment variables intact
exec "$PGBACKREST_BIN" "$@"