# Build stage
FROM postgres:18-alpine AS builder

# Install build dependencies and pgBackRest
# Combined installation with fallback for QEMU emulation issues
RUN apk update && \
  (apk add --no-cache bash curl dcron openssl || \
  (apk add --no-cache bash curl openssl && apk add --no-cache dcron || true)) && \
  rm -rf /var/cache/apk/*

# Production stage
FROM postgres:18-alpine

# Install runtime dependencies
# Combined installation with fallback for QEMU emulation issues
RUN apk update && \
  (apk add --no-cache bash curl dcron openssl || \
  (apk add --no-cache bash curl openssl && apk add --no-cache dcron || true)) && \
  rm -rf /var/cache/apk/*

# Install pgBackRest and PostgreSQL extensions
RUN apk add --no-cache pgbackrest
RUN apk add --no-cache postgresql-contrib
RUN rm -rf /var/cache/apk/*

# Create necessary directories
RUN mkdir -p /var/log/pgbackrest \
  /var/lib/pgbackrest \
  /var/spool/pgbackrest \
  /etc/pgbackrest \
  /etc/pgbackrest/conf.d \
  /tmp/pgbackrest \
  && chown -R postgres:postgres /var/log/pgbackrest /var/lib/pgbackrest /var/spool/pgbackrest /etc/pgbackrest /tmp/pgbackrest

# Copy scripts
COPY scripts/pg-entrypoint.sh /usr/local/bin/pg-entrypoint.sh
COPY scripts/entrypoint-compat.sh /usr/local/bin/entrypoint-compat.sh
COPY scripts/backup-cron.sh /usr/local/bin/backup-cron.sh
COPY scripts/setup-cron.sh /usr/local/bin/setup-cron.sh
COPY scripts/configure-postgres.sh /usr/local/bin/configure-postgres.sh
COPY scripts/configure-pgbackrest.sh /usr/local/bin/configure-pgbackrest.sh
COPY scripts/configure-ssl-with-ca.sh /usr/local/bin/configure-ssl-with-ca.sh
COPY scripts/ensure-postgres-user.sh /usr/local/bin/ensure-postgres-user.sh
COPY scripts/pgbackrest-wrapper.sh /usr/local/bin/pgbackrest-wrapper.sh
COPY scripts/init-db.sh /docker-entrypoint-initdb.d/init-db.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/pg-entrypoint.sh \
  /usr/local/bin/entrypoint-compat.sh \
  /usr/local/bin/backup-cron.sh \
  /usr/local/bin/setup-cron.sh \
  /usr/local/bin/configure-postgres.sh \
  /usr/local/bin/configure-pgbackrest.sh \
  /usr/local/bin/configure-ssl-with-ca.sh \
  /usr/local/bin/ensure-postgres-user.sh \
  /usr/local/bin/pgbackrest-wrapper.sh \
  /docker-entrypoint-initdb.d/init-db.sh

# Replace pgbackrest with wrapper to avoid environment variable warnings
RUN mv /usr/bin/pgbackrest /usr/bin/pgbackrest-orig && \
  ln -s /usr/local/bin/pgbackrest-wrapper.sh /usr/bin/pgbackrest

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD pg_isready -U ${POSTGRES_USER:-postgres} || exit 1

# Set entrypoint - Compatible with official postgres:18-alpine
# This wrapper handles pgBackRest and SSL setup, then calls docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint-compat.sh"]
CMD ["postgres"]
