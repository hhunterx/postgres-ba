#!/bin/bash
set -e

# Enhanced entrypoint for PostgreSQL with pgBackRest
# Compatible with postgres:18-alpine official image
# 
# This entrypoint:
# 1. Runs pre-initialization scripts (setup, restore, replica)
# 2. Delegates to official docker-entrypoint.sh for database init
# 3. Post-initialization tasks run via /docker-entrypoint-initdb.d/

echo "=========================================="
echo "PostgreSQL 18 with pgBackRest"
echo "=========================================="

# Install missing critical packages at runtime if build-time installation failed
if ! command -v openssl >/dev/null 2>&1 || ! command -v pgbackrest >/dev/null 2>&1; then
    echo "Installing missing packages at runtime..."
    echo "Checking which packages are missing..."
    ! command -v openssl >/dev/null 2>&1 && echo "  - openssl is missing"
    ! command -v pgbackrest >/dev/null 2>&1 && echo "  - pgbackrest is missing"
    ! command -v su-exec >/dev/null 2>&1 && echo "  - su-exec is missing (gosu available as fallback)"
    ! command -v curl >/dev/null 2>&1 && echo "  - curl is missing (wget available as fallback)"
    
    echo "Attempting to install (with retries for DNS issues)..."
    RETRY_COUNT=0
    MAX_RETRIES=10
    INSTALLED=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$INSTALLED" = false ]; do
        if [ $RETRY_COUNT -gt 0 ]; then
            # Exponential backoff: wait longer on each retry
            WAIT_TIME=$((3 + RETRY_COUNT * 2))
            echo "Retry attempt $RETRY_COUNT of $MAX_RETRIES (waiting ${WAIT_TIME}s for DNS)..."
            sleep $WAIT_TIME
        fi
        
        # Capture output and check if installation succeeded
        set +e  # Temporarily disable exit on error
        apk add --no-cache openssl pgbackrest postgresql-contrib su-exec curl > /tmp/apk-install.log 2>&1
        APK_EXIT=$?
        set -e  # Re-enable exit on error
        cat /tmp/apk-install.log  # Show output
        
        if [ $APK_EXIT -eq 0 ]; then
            echo "Packages installed successfully!"
            INSTALLED=true
        else
            echo "Installation failed with exit code $APK_EXIT"
            if grep -q "DNS:" /tmp/apk-install.log; then
                echo "DNS error detected, will retry..."
                RETRY_COUNT=$((RETRY_COUNT + 1))
            else
                echo "Non-DNS error, stopping retries"
                break
            fi
        fi
    done
    
    if [ "$INSTALLED" = false ]; then
        echo "WARNING: Package installation failed after $MAX_RETRIES attempts. Checking what succeeded..."
        command -v openssl >/dev/null 2>&1 && echo "  ✓ openssl installed" || echo "  ✗ openssl FAILED"
        command -v pgbackrest >/dev/null 2>&1 && echo "  ✓ pgbackrest installed" || echo "  ✗ pgbackrest FAILED"
        command -v su-exec >/dev/null 2>&1 && echo "  ✓ su-exec installed" || echo "  ✗ su-exec FAILED (using gosu)"
        command -v curl >/dev/null 2>&1 && echo "  ✓ curl installed" || echo "  ✗ curl FAILED (using wget)"
    fi
    
    # Setup pgbackrest wrapper if needed and pgbackrest is now available
    if [ -f /usr/bin/pgbackrest ] && [ ! -f /usr/bin/pgbackrest-orig ]; then
        mv /usr/bin/pgbackrest /usr/bin/pgbackrest-orig
        ln -s /usr/local/bin/pgbackrest-wrapper.sh /usr/bin/pgbackrest
    fi
fi

PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}
export PGDATA

# ============================================
# Pre-initialization phase
# ============================================
# These scripts run BEFORE the official entrypoint

echo "Running pre-initialization scripts..."

# 1. Setup directories and permissions (always run)
if [ -f /usr/local/bin/00-setup-directories.sh ]; then
    source /usr/local/bin/00-setup-directories.sh
fi

# Check if database already exists
DB_INITIALIZED=false
if [ -s "$PGDATA/PG_VERSION" ]; then
    DB_INITIALIZED=true
    echo "Database already initialized at ${PGDATA}"
fi

# 2. Handle backup restore (only if DB doesn't exist)
if [ "$DB_INITIALIZED" = false ] && [ -f /usr/local/bin/01-restore-from-backup.sh ]; then
    source /usr/local/bin/01-restore-from-backup.sh
fi

# 3. Setup replica (only if DB doesn't exist)
if [ "$DB_INITIALIZED" = false ] && [ -f /usr/local/bin/02-setup-replica.sh ]; then
    source /usr/local/bin/02-setup-replica.sh
fi

# 4. Configure SSL (always run, both new and existing databases)
if [ -f /usr/local/bin/10-configure-ssl.sh ]; then
    echo "Configuring SSL certificates..."
    source /usr/local/bin/10-configure-ssl.sh
fi

# 5. Configure PostgreSQL and pgBackRest (always run, both new and existing databases)
if [ -f /usr/local/bin/20-configure-pgbackrest-postgres.sh ]; then
    source /usr/local/bin/20-configure-pgbackrest-postgres.sh
fi

# 6. Post-initialization tasks (always run if pgBackRest enabled)
# Sets up cron and schedules init-db.sh (idempotent)
if [ -n "${PGBACKREST_STANZA}" ] && [ "${PG_MODE}" != "replica" ] && [ -f /usr/local/bin/99-post-init.sh ]; then
    source /usr/local/bin/99-post-init.sh
fi

# ============================================
# Database initialization phase
# ============================================
# The official docker-entrypoint.sh will:
# - Run initdb if database doesn't exist
# - Execute scripts in /docker-entrypoint-initdb.d/ (only on first init!)
# - Start PostgreSQL

echo ""
if [ "$DB_INITIALIZED" = true ]; then
    echo "Starting existing PostgreSQL database..."
else
    echo "Initializing new PostgreSQL database..."
    echo "Scripts in /docker-entrypoint-initdb.d/ will run after initdb"
fi
echo "Database directory: ${PGDATA}"
echo ""

# Call the official PostgreSQL entrypoint
# This handles all the standard initialization
exec /usr/local/bin/docker-entrypoint.sh "$@"
