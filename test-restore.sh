#!/bin/bash

echo "=========================================="
echo "Testing S3 Restore Process"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: Stop all containers
print_info "Step 1: Stopping all containers..."
docker-compose down
if [ $? -eq 0 ]; then
    print_info "Containers stopped successfully"
else
    print_error "Failed to stop containers"
    exit 1
fi
echo ""

# Step 2: Remove all volumes
print_info "Step 2: Removing all volumes..."
print_warning "This will delete all local PostgreSQL data!"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    print_error "Operation cancelled by user"
    exit 1
fi

docker volume rm postgres-ba_postgres_data postgres-ba_postgres_logs 2>/dev/null
if [ $? -eq 0 ]; then
    print_info "Volumes removed successfully"
else
    print_warning "Some volumes may not exist or already removed"
fi
echo ""

# Step 3: Update .env to enable restore
print_info "Step 3: Updating .env to enable restore from S3..."
if [ -f .env ]; then
    # Create backup of .env
    cp .env .env.backup
    print_info "Backup of .env created as .env.backup"
    
    # Update RESTORE_FROM_BACKUP to true
    sed -i.tmp 's/^RESTORE_FROM_BACKUP=.*/RESTORE_FROM_BACKUP=true/' .env
    rm -f .env.tmp
    print_info "RESTORE_FROM_BACKUP set to true"
else
    print_error ".env file not found"
    exit 1
fi
echo ""

# Step 4: Show current backup info (optional - requires AWS CLI or similar)
print_info "Step 4: Current configuration:"
echo "  S3 Bucket: $(grep S3_BUCKET .env | cut -d= -f2)"
echo "  S3 Endpoint: $(grep S3_ENDPOINT .env | cut -d= -f2)"
echo "  S3 Path: $(grep S3_PATH .env | cut -d= -f2)"
echo "  Stanza: $(grep PGBACKREST_STANZA .env | cut -d= -f2)"
echo ""

# Step 5: Start containers with restore
print_info "Step 5: Starting containers with restore enabled..."
print_warning "This will restore from the latest backup in S3..."
echo ""

docker-compose up -d

if [ $? -eq 0 ]; then
    print_info "Containers started successfully"
    echo ""
    print_info "Monitoring restore process..."
    echo ""
    
    # Wait a bit for container to start
    sleep 3
    
    # Follow logs
    print_info "Following logs (press Ctrl+C to stop):"
    echo ""
    docker-compose logs -f postgres
else
    print_error "Failed to start containers"
    
    # Restore original .env
    if [ -f .env.backup ]; then
        mv .env.backup .env
        print_info "Original .env restored"
    fi
    exit 1
fi
