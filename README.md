# PostgreSQL with pgBackRest S3 Backup

Docker image based on PostgreSQL 18 (Alpine) with automated pgBackRest backups to S3.

## Features

- ✅ PostgreSQL 18 on Alpine Linux
- ✅ pgBackRest for enterprise-grade backup and restore
- ✅ Automated backups to S3 (full, differential, incremental)
- ✅ Automatic restore from S3 on first startup
- ✅ WAL archiving every 60 seconds
- ✅ **SSL/TLS with Self-Signed Certificates (10 years validity)**
- ✅ **Shared CA for Primary/Replica validation**
- ✅ Primary/Replica support
- ✅ Configurable via environment variables
- ✅ Automated cron-based backup scheduling

## Backup Schedule

- **Incremental**: Every 30 minutes
- **Differential**: Daily at 2 AM
- **Full**: Weekly on Sunday at 3 AM
- **WAL Archives**: Every 60 seconds

## SSL/TLS Configuration

All connections are encrypted with SSL/TLS using self-signed certificates:

- ✅ Certificates valid for 10 years
- ✅ Automatically generated on first startup
- ✅ Shared CA for Primary/Replica validation in cluster mode
- ✅ Unique server certificate per instance
- ✅ Persistent storage in Docker volumes
- ✅ Mandatory SSL for replication connections (`hostssl`)

### SSL Volumes

**Single Instance:**

- `postgres_ca` - Shared CA directory
- `postgres_ssl` - Server certificate directory

**Cluster Mode:**

- `postgres_cluster_ca` - Shared CA (used by primary and replicas)
- `postgres_cluster_primary_ssl` - Primary server certificates
- `postgres_cluster_replica_ssl` - Replica server certificates

For detailed SSL configuration, see [SSL Configuration Guide](docs/ssl-configuration.md)

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd postgres-ba
```

### 2. Configure Environment Variables

Copy the example environment file and edit it with your S3 credentials (optional):

```bash
cp .env.example .env
```

### 3. Choose Your Setup

**Option A: Drop-in Replacement (Compatibility Mode)**

- No pgBackRest features
- Pure PostgreSQL with SSL only
- Use `docker-compose.compat.yml`
- Perfect for existing postgres:18-alpine deployments

```bash
docker-compose -f docker-compose.compat.yml up -d
```

**Option B: Full Featured (with pgBackRest & S3 Backups)**

- Include pgBackRest for automated S3 backups
- Requires S3 configuration in `.env`
- Use regular `docker-compose.yml`

```bash
# Edit .env with your S3 credentials first
docker-compose up -d
```

### 4. Check Logs

```bash
# Compatibility mode
docker-compose -f docker-compose.compat.yml logs -f

# Full featured
docker-compose logs -f
```

## Docker Compose Files

- **`docker-compose.yml`** - Full featured with pgBackRest & S3 backups
- **`docker-compose.cluster.yml`** - Cluster setup (primary + replica with pgBackRest)
- **`docker-compose.compat.yml`** - Compatibility mode (drop-in replacement)

## Drop-in Replacement Mode

This image can be used as a direct replacement for `postgres:18-alpine` with additional SSL support.

### Migration from postgres:18-alpine

1. Replace the image name in your docker-compose.yml:

```yaml
# Before
image: postgres:18-alpine

# After
build:
  context: .
  dockerfile: Dockerfile
image: postgres-pgbackrest:latest
```

2. No other changes needed! All environment variables and volumes are compatible:

```yaml
postgres:
  image: postgres-pgbackrest:latest
  environment:
    POSTGRES_DB: my_database
    POSTGRES_USER: my_user
    POSTGRES_PASSWORD: my_password
  ports:
    - "5432:5432"
  volumes:
    - ./data:/var/lib/postgresql/data
    - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U my_user -d my_database"]
    interval: 10s
    timeout: 5s
    retries: 5
```

### Features in Compatibility Mode

✅ Full PostgreSQL 18 compatibility  
✅ SSL/TLS encryption enabled by default  
✅ `/docker-entrypoint-initdb.d/` scripts supported  
✅ All standard environment variables work  
✅ Automatic database initialization  
✅ Health checks work as expected

### Disabling Features

All features are **enabled by default** in compatibility mode. To disable them:

```yaml
environment:
  # Disable pgBackRest (already off if not set)
  # PGBACKREST_STANZA: ""

  # Disable SSL (not recommended, but possible - requires code change)
  # Would require environment variable support
```

**Note:** SSL cannot be disabled via environment variable yet, but pgBackRest is automatically skipped if `PGBACKREST_STANZA` is not set.

### PostgreSQL Configuration

| Variable            | Description                   | Default    |
| ------------------- | ----------------------------- | ---------- |
| `POSTGRES_USER`     | PostgreSQL superuser name     | `postgres` |
| `POSTGRES_PASSWORD` | PostgreSQL superuser password | `changeme` |
| `POSTGRES_DB`       | Default database name         | `postgres` |
| `POSTGRES_PORT`     | PostgreSQL port               | `5432`     |

### Mode Configuration

| Variable              | Description                          | Default   |
| --------------------- | ------------------------------------ | --------- |
| `PG_MODE`             | Server mode (`primary` or `replica`) | `primary` |
| `RESTORE_FROM_BACKUP` | Restore from S3 on first startup     | `false`   |

### Backup Configuration

| Variable                 | Description                              | Default |
| ------------------------ | ---------------------------------------- | ------- |
| `PGBACKREST_STANZA`      | pgBackRest stanza name                   | `main`  |
| `PGBACKREST_PROCESS_MAX` | Max parallel backup processes            | `4`     |
| `RETENTION_FULL`         | Number of full backups to retain         | `4`     |
| `RETENTION_DIFF`         | Number of differential backups to retain | `4`     |

### S3 Configuration (Required)

| Variable        | Description              | Default            |
| --------------- | ------------------------ | ------------------ |
| `S3_BUCKET`     | S3 bucket name           | **(required)**     |
| `S3_ACCESS_KEY` | S3 access key            | **(required)**     |
| `S3_SECRET_KEY` | S3 secret key            | **(required)**     |
| `S3_ENDPOINT`   | S3 endpoint URL          | `s3.amazonaws.com` |
| `S3_REGION`     | S3 region                | `us-east-1`        |
| `S3_PATH`       | Path prefix in S3 bucket | `/pgbackrest`      |

### Performance Tuning

| Variable                | Description              | Default |
| ----------------------- | ------------------------ | ------- |
| `SHARED_BUFFERS`        | Shared buffer size       | `256MB` |
| `EFFECTIVE_CACHE_SIZE`  | Effective cache size     | `1GB`   |
| `MAINTENANCE_WORK_MEM`  | Maintenance work memory  | `64MB`  |
| `WORK_MEM`              | Work memory per query    | `4MB`   |
| `MAX_WAL_SENDERS`       | Max WAL sender processes | `10`    |
| `MAX_REPLICATION_SLOTS` | Max replication slots    | `10`    |

### SSL Configuration

| Variable       | Description                | Default                        |
| -------------- | -------------------------- | ------------------------------ |
| `CA_DIR`       | Certificate Authority path | `/var/lib/postgresql/ca`       |
| `SSL_CERT_DIR` | SSL certificate directory  | `/var/lib/postgresql/ssl`      |
| `SERVER_NAME`  | Server hostname for CN     | `$(hostname)` (container name) |

## Usage Examples

### First Time Setup (New Database)

```bash
# Configure .env with your S3 credentials
docker-compose up -d

# The container will:
# 1. Initialize a new PostgreSQL database
# 2. Configure pgBackRest
# 3. Create initial full backup to S3
# 4. Start PostgreSQL
# 5. Begin automated backup schedule
```

### Restore from Existing Backup

```bash
# Set RESTORE_FROM_BACKUP=true in .env
RESTORE_FROM_BACKUP=true

# Start the container
docker-compose up -d

# The container will:
# 1. Restore latest backup from S3
# 2. Start PostgreSQL with restored data
# 3. Resume automated backup schedule
```

### Manual Backup Operations

```bash
# Enter the container
docker exec -it postgres-primary bash

# View backup information
pgbackrest --stanza=main info

# Perform manual full backup
pgbackrest --stanza=main --type=full backup

# Perform manual differential backup
pgbackrest --stanza=main --type=diff backup

# Perform manual incremental backup
pgbackrest --stanza=main --type=incr backup
```

### View Backup Logs

```bash
# View automated backup logs
docker exec -it postgres-primary cat /var/log/pgbackrest/backup-cron.log

# Follow backup logs in real-time
docker exec -it postgres-primary tail -f /var/log/pgbackrest/backup-cron.log
```

## Building the Docker Image

### Local Build

```bash
docker build -t postgres-pgbackrest:latest .
```

### Using GitHub Actions

The repository includes a GitHub Actions workflow that automatically builds and pushes the image to GitHub Container Registry (ghcr.io) on:

- Push to `main` or `develop` branches
- Tagged releases (e.g., `v1.0.0`)
- Manual workflow dispatch

To use GitHub Actions:

1. Enable GitHub Actions in your repository
2. Push to the main branch or create a tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

3. The image will be available at: `ghcr.io/<your-username>/postgres-ba:latest`

## Architecture

### Directory Structure

```
.
├── Dockerfile                  # Main Docker image definition
├── docker-compose.yml         # Docker Compose stack
├── .env.example              # Environment variables template
├── scripts/
│   ├── entrypoint.sh         # Main entrypoint script
│   ├── configure-postgres.sh # PostgreSQL configuration
│   ├── configure-pgbackrest.sh # pgBackRest configuration
│   ├── backup-cron.sh        # Backup execution script
│   └── setup-cron.sh         # Cron job setup
├── .github/
│   └── workflows/
│       └── docker-build.yml  # GitHub Actions workflow
├── .gitignore
├── .dockerignore
└── README.md
```

### How It Works

1. **Entrypoint Process**:

   - Configures pgBackRest with S3 credentials
   - Checks if PostgreSQL data exists
   - If no data and `RESTORE_FROM_BACKUP=true`, restores from S3
   - If no data and `RESTORE_FROM_BACKUP=false`, initializes new database
   - Configures PostgreSQL for WAL archiving
   - Sets up automated backup cron jobs
   - Starts PostgreSQL

2. **Backup Process**:

   - Cron triggers backup scripts at scheduled intervals
   - pgBackRest performs backup (full/diff/incr) to S3
   - WAL files are archived to S3 every 60 seconds
   - Backup logs are maintained in `/var/log/pgbackrest/`

3. **Restore Process**:
   - On first startup with empty data directory
   - Fetches latest backup from S3
   - Restores database to the point of latest backup
   - Replays WAL files for point-in-time recovery

## S3 Bucket Setup

Your S3 bucket should have the following permissions for the IAM user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::your-bucket-name"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::your-bucket-name/*"
    }
  ]
}
```

## Monitoring

### Check PostgreSQL Status

```bash
docker exec -it postgres-primary pg_isready
```

### Check Backup Status

```bash
docker exec -it postgres-primary pgbackrest --stanza=main info
```

### Check Cron Jobs

```bash
docker exec -it postgres-primary crontab -l
```

### Database Management UI

Access Adminer at http://localhost:8080

- Server: `postgres`
- Username: Value from `POSTGRES_USER`
- Password: Value from `POSTGRES_PASSWORD`
- Database: Value from `POSTGRES_DB`

### SSL Connection Examples

Connect to PostgreSQL with SSL required:

```bash
# From host (requires psql installed)
PGPASSWORD=changeme psql -h localhost -U postgres \
  --set=sslmode=require -c "SELECT version();"

# From inside container
docker exec -it postgres-ba-primary psql -h localhost -U postgres \
  --set=sslmode=require -c "SELECT version();"

# Test SSL connection with openssl
echo "" | openssl s_client -connect localhost:5432 -starttls postgres
```

**Note:** Self-signed certificates will show verification warnings, which is expected for development environments.

## Troubleshooting

### Backups Not Running

Check cron status:

```bash
docker exec -it postgres-primary ps aux | grep crond
```

Check backup logs:

```bash
docker exec -it postgres-primary cat /var/log/pgbackrest/backup-cron.log
```

### S3 Connection Issues

Verify S3 credentials and test connectivity:

```bash
docker exec -it postgres-primary pgbackrest --stanza=main check
```

### PostgreSQL Not Starting

Check PostgreSQL logs:

```bash
docker-compose logs postgres
```

Check disk space:

```bash
docker exec -it postgres-primary df -h
```

## Security Considerations

1. **SSL/TLS Encryption**: All connections are encrypted with self-signed SSL certificates
2. **Always change default passwords** in production
3. **Use strong S3 credentials** and rotate them regularly
4. **Enable S3 bucket encryption** for data at rest
5. **Use SSL/TLS** for S3 connections in production
6. **Restrict network access** using Docker networks
7. **Keep the image updated** with security patches

### Certificate Management

- Certificates are automatically generated on first startup
- Valid for 10 years from generation date
- Stored in persistent Docker volumes
- Not regenerated if they already exist (idempotent)
- Primary and Replica share the same CA in cluster mode

To verify certificate details:

```bash
# View server certificate
docker exec postgres-ba-primary openssl x509 -in \
  /var/lib/postgresql/ssl/server.crt -text -noout

# Verify certificate against CA
docker exec postgres-ba-primary openssl verify -CAfile \
  /var/lib/postgresql/ssl/root.crt \
  /var/lib/postgresql/ssl/server.crt
```

## Performance Tuning

Adjust PostgreSQL settings based on your hardware:

```env
# For 8GB RAM system
SHARED_BUFFERS=2GB
EFFECTIVE_CACHE_SIZE=6GB
MAINTENANCE_WORK_MEM=512MB
WORK_MEM=16MB
```

Adjust backup parallelism:

```env
# For better backup performance
PGBACKREST_PROCESS_MAX=8
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - See LICENSE file for details

## Support

For issues and questions:

- Open an issue on GitHub
- Check pgBackRest documentation: https://pgbackrest.org/
- Check PostgreSQL documentation: https://www.postgresql.org/docs/

## Changelog

### v1.0.0 - Production Ready ✅

- Initial release
- PostgreSQL 18 with pgBackRest
- Automated S3 backups (full/diff/incr)
- WAL archiving every 60 seconds
- Automated restore from S3
- Docker Compose stack
- GitHub Actions CI/CD
- **SSL/TLS with self-signed certificates (10 years validity)**
- **Shared CA for Primary/Replica validation**
- **Drop-in replacement mode for postgres:18-alpine (100% compatible)**

---

## ✅ Status: Production Ready

This image is **100% compatible with postgres:18-alpine** and can be used as a drop-in replacement:

### Before (postgres:18-alpine)

```yaml
postgres:
  image: postgres:18-alpine
  environment:
    POSTGRES_PASSWORD: secret
    POSTGRES_DB: mydb
```

### After (postgres-pgbackrest:latest)

```yaml
postgres:
  image: postgres-pgbackrest:latest
  environment:
    POSTGRES_PASSWORD: secret
    POSTGRES_DB: mydb
  # Everything else stays the same!
  # SSL is added automatically as a bonus
```

**Key Differences:**

- ✅ 100% PostgreSQL API compatible
- ✅ All environment variables work identically
- ✅ All volumes work identically
- ✅ Same health check works
- ✅ **Bonus: SSL/TLS encryption included by default**
- 🎁 **Bonus: pgBackRest available (but optional)**

See [Compatibility Report](docs/compatibility-report.md) for detailed validation.

## Documentation

- [SSL/TLS Configuration](docs/ssl-configuration.md) - Portuguese guide for SSL setup
- [Compatibility Report](docs/compatibility-report.md) - Validation of drop-in replacement
- [Utilities Documentation](docs/utilities-cmd.md) - Command line utilities
- [Cluster Restore Guide](docs/cluster-restore.md) - Instructions for cluster backup/restore
