# Build stage
FROM postgres:18-alpine AS builder

# Install build dependencies
# Note: bash, wget, crond are already in the base image
RUN apk add --no-cache openssl curl 2>&1 || apk add --no-cache openssl || true
RUN rm -rf /var/cache/apk/*

# Production stage
FROM postgres:18-alpine

# Install runtime dependencies
# Note: bash, wget, crond, gosu are already in the base image
# Install only critical missing packages
RUN apk add --no-cache openssl curl su-exec 2>&1 || apk add --no-cache openssl || true

# Install pgBackRest and PostgreSQL extensions from community repo
# These are critical but may fail if community repo is unavailable
RUN apk add --no-cache pgbackrest postgresql-contrib 2>&1 || \
  echo "WARNING: pgbackrest/postgresql-contrib not installed - community repo unavailable"

# Clean cache
RUN rm -rf /var/cache/apk/*

# Create necessary directories
RUN mkdir -p /var/log/pgbackrest \
  /var/lib/pgbackrest \
  /var/spool/pgbackrest \
  /etc/pgbackrest \
  /etc/pgbackrest/conf.d \
  /etc/postgresql/ca \
  /etc/postgresql/ssl \
  /tmp/pgbackrest \
  && chown -R postgres:postgres /var/log/pgbackrest /var/lib/pgbackrest /var/spool/pgbackrest /etc/pgbackrest /etc/postgresql /tmp/pgbackrest

# Copy utility scripts
COPY scripts/backup-cron.sh /usr/local/bin/backup-cron.sh
COPY scripts/setup-cron.sh /usr/local/bin/setup-cron.sh
COPY scripts/configure-postgres.sh /usr/local/bin/configure-postgres.sh
COPY scripts/configure-pgbackrest.sh /usr/local/bin/configure-pgbackrest.sh
COPY scripts/configure-ssl-with-ca.sh /usr/local/bin/configure-ssl-with-ca.sh
COPY scripts/pgbackrest-wrapper.sh /usr/local/bin/pgbackrest-wrapper.sh
COPY scripts/init-db.sh /usr/local/bin/init-db.sh

# Copy pre-initialization scripts (run before docker-entrypoint.sh)
COPY scripts/00-setup-directories.sh /usr/local/bin/00-setup-directories.sh
COPY scripts/01-restore-from-backup.sh /usr/local/bin/01-restore-from-backup.sh
COPY scripts/02-setup-replica.sh /usr/local/bin/02-setup-replica.sh
COPY scripts/10-configure-ssl.sh /usr/local/bin/10-configure-ssl.sh
COPY scripts/20-configure-pgbackrest-postgres.sh /usr/local/bin/20-configure-pgbackrest-postgres.sh
COPY scripts/99-post-init.sh /usr/local/bin/99-post-init.sh

# Copy initialization scripts (run by docker-entrypoint.sh)
COPY scripts/20-configure-postgres-initdb.sh /docker-entrypoint-initdb.d/20-configure-postgres-initdb.sh
COPY scripts/30-init-db.sh /docker-entrypoint-initdb.d/30-init-db.sh

# Copy main entrypoint
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

# Make all scripts executable
RUN chmod +x /usr/local/bin/*.sh \
  /docker-entrypoint-initdb.d/*.sh

# Replace pgbackrest with wrapper to avoid environment variable warnings
# Only if pgbackrest was successfully installed
RUN if [ -f /usr/bin/pgbackrest ]; then \
  mv /usr/bin/pgbackrest /usr/bin/pgbackrest-orig && \
  ln -s /usr/local/bin/pgbackrest-wrapper.sh /usr/bin/pgbackrest; \
fi

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD pg_isready -U ${POSTGRES_USER:-postgres} || exit 1

# Set entrypoint - Compatible with official postgres:18-alpine
# This entrypoint runs pre-init scripts, then delegates to docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["postgres"]
