#!/bin/bash
set -e

echo "Ensuring postgres user exists for pgBackRest compatibility..."

# Wait for PostgreSQL to be ready
until pg_isready -h localhost -p ${PGPORT:-5432} -U ${POSTGRES_USER:-postgres} 2>/dev/null; do
    echo "Waiting for PostgreSQL to start..."
    sleep 2
done

# Function to create postgres user if it doesn't exist
create_postgres_user() {
    local db_name="$1"
    local connect_user="$2"
    
    echo "Attempting to create postgres user using database: $db_name, user: $connect_user"
    
    # Check if postgres role exists and create if necessary
    PGPASSWORD="${POSTGRES_PASSWORD:-changeme}" psql -h localhost -U "$connect_user" -d "$db_name" -c "
    DO \$\$ 
    BEGIN 
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'postgres') THEN
            CREATE ROLE postgres WITH SUPERUSER CREATEDB CREATEROLE LOGIN PASSWORD '${POSTGRES_PASSWORD:-changeme}';
            RAISE NOTICE 'Created postgres user successfully';
        ELSE
            RAISE NOTICE 'postgres user already exists';
        END IF;
    END \$\$;" 2>/dev/null || return 1
    
    return 0
}

# Try to connect as postgres user first
if PGPASSWORD="${POSTGRES_PASSWORD:-changeme}" psql -h localhost -U postgres -d postgres -c "SELECT 1;" 2>/dev/null >/dev/null; then
    echo "postgres user exists and is accessible."
    exit 0
fi

echo "postgres user not accessible. Attempting to create..."

# Get the configured PostgreSQL user (from environment)
PG_USER="${POSTGRES_USER:-postgres}"

# If the configured user is not 'postgres', try to create the postgres user
if [ "$PG_USER" != "postgres" ]; then
    # Try to connect with the configured user and create postgres role
    if create_postgres_user "postgres" "$PG_USER"; then
        echo "Successfully created postgres user using $PG_USER"
        exit 0
    fi
    
    # Try with the default database
    DEFAULT_DB="${POSTGRES_DB:-postgres}"
    if [ "$DEFAULT_DB" != "postgres" ] && create_postgres_user "$DEFAULT_DB" "$PG_USER"; then
        echo "Successfully created postgres user using $PG_USER on database $DEFAULT_DB"
        exit 0
    fi
fi

# Try to find any superuser in the system
echo "Searching for existing superusers..."
SUPERUSERS=$(PGPASSWORD="${POSTGRES_PASSWORD:-changeme}" psql -h localhost -U "$PG_USER" -d postgres -t -c "
    SELECT rolname FROM pg_roles WHERE rolsuper = true AND rolcanlogin = true LIMIT 5;
" 2>/dev/null | tr -d ' ' | grep -v '^$' || echo "")

if [ -n "$SUPERUSERS" ]; then
    for superuser in $SUPERUSERS; do
        echo "Trying with superuser: $superuser"
        if create_postgres_user "postgres" "$superuser"; then
            echo "Successfully created postgres user using superuser: $superuser"
            exit 0
        fi
    done
fi

# Last resort: try to use template1
if create_postgres_user "template1" "$PG_USER"; then
    echo "Successfully created postgres user using template1"
    exit 0
fi

echo "Warning: Could not create postgres user. pgBackRest operations may fail."
echo "This can happen when using an existing database that doesn't have the postgres role."
echo "You may need to manually create the postgres user or configure pgBackRest to use a different user."

exit 1