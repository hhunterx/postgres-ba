# Test Scenarios

This directory contains test scenarios for the postgres-ba project.

## MinIO Setup

All test scenarios share a single MinIO instance to avoid port conflicts and resource overhead. The MinIO service must be started manually before running any tests.

### Starting MinIO

Before running any test scenario, start the MinIO service:

```bash
cd tests
./start-minio.sh
```

This will:

- Start MinIO on ports 9000 (S3 API) and 9001 (Console)
- Create TLS certificates
- Create separate buckets for each scenario:
  - `scenario1` - for scenario-1-new-db
  - `scenario2` - for scenario-2-restart
  - `scenario3` - for scenario-3-restore
  - `scenario4` - for scenario-4-replica
  - `scenario5` - for scenario-5-existing-db

### Stopping MinIO

To stop the MinIO service:

```bash
cd tests
./stop-minio.sh
```

### Accessing MinIO

- **Console UI**: https://localhost:9001
- **S3 API**: https://localhost:9000
- **Credentials**: minioadmin / minioadmin

## Test Scenarios

Each scenario has its own isolated environment with:

- Separate bucket in MinIO (scenario1, scenario2, etc.)
- Separate PostgreSQL port
- Separate Docker volumes
- Own `.env` configuration file

### Scenario 1: New Database

Tests first-time database creation with pgBackRest setup.

```bash
cd scenario-1-new-db
./test.sh
```

### Scenario 2: Restart

Tests container restart with existing database.

```bash
cd scenario-2-restart
./test.sh
```

### Scenario 3: Restore from Backup

Tests database restoration from S3 backup.

```bash
cd scenario-3-restore
./test.sh
```

### Scenario 4: Primary/Replica

Tests PostgreSQL replication setup.

```bash
cd scenario-4-replica
./test.sh
```

### Scenario 5: Existing Database Migration

Tests migration from official PostgreSQL to postgres-ba.

```bash
cd scenario-5-existing-db
./test.sh
```

## Running All Tests

To run all test scenarios sequentially:

```bash
cd tests
./start-minio.sh
./run-all-tests.sh
```

## Network Configuration

All services (MinIO and PostgreSQL containers from each scenario) connect to a shared Docker network called `tests-network`. This allows containers from different scenarios to communicate with the shared MinIO instance while maintaining isolation between scenarios.

## Important Notes

1. **Always start MinIO first**: All tests require MinIO to be running
2. **Separate buckets**: Each scenario uses its own bucket to avoid data conflicts
3. **Port mapping**: Each scenario uses different PostgreSQL ports (5501, 5502, etc.)
4. **Clean state**: Use `docker-compose down -v` in each scenario directory to reset state
