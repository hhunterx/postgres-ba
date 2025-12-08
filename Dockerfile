# Build arguments for multi-platform builds
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETARCH

# Build stage
FROM --platform=$TARGETPLATFORM postgres:18-alpine AS builder

# Install build dependencies and pgBackRest
# Split installations to avoid QEMU emulation issues
RUN apk update && apk upgrade
RUN apk add --no-cache bash curl
# Install dcron - busybox trigger may fail in QEMU but package installs correctly
RUN apk add --no-cache dcron || true
RUN rm -rf /var/cache/apk/*

# Production stage
FROM --platform=$TARGETPLATFORM postgres:18-alpine

# Install runtime dependencies
# Split installations to avoid QEMU emulation issues
RUN apk update && apk upgrade
RUN apk add --no-cache bash curl
# Install dcron - busybox trigger may fail in QEMU but package installs correctly
RUN apk add --no-cache dcron || true
RUN rm -rf /var/cache/apk/*

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
  && chown -R postgres:postgres /var/log/pgbackrest /var/lib/pgbackrest /var/spool/pgbackrest /etc/pgbackrest

# Copy scripts
COPY scripts/root-entrypoint.sh /usr/local/bin/root-entrypoint.sh
COPY scripts/pg-entrypoint.sh /usr/local/bin/pg-entrypoint.sh
COPY scripts/backup-cron.sh /usr/local/bin/backup-cron.sh
COPY scripts/setup-cron.sh /usr/local/bin/setup-cron.sh
COPY scripts/configure-postgres.sh /usr/local/bin/configure-postgres.sh
COPY scripts/configure-pgbackrest.sh /usr/local/bin/configure-pgbackrest.sh
COPY scripts/init-db.sh /docker-entrypoint-initdb.d/init-db.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/root-entrypoint.sh \
  /usr/local/bin/pg-entrypoint.sh \
  /usr/local/bin/backup-cron.sh \
  /usr/local/bin/setup-cron.sh \
  /usr/local/bin/configure-postgres.sh \
  /usr/local/bin/configure-pgbackrest.sh \
  /docker-entrypoint-initdb.d/init-db.sh

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD pg_isready -U ${POSTGRES_USER:-postgres} || exit 1

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/root-entrypoint.sh"]
CMD ["postgres"]
