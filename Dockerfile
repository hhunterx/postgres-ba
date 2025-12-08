FROM postgres:18-alpine

# Install pgBackRest and required dependencies
RUN apk add --no-cache \
  pgbackrest \
  bash \
  curl \
  dcron \
  postgresql-contrib \
  && rm -rf /var/cache/apk/*

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

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/root-entrypoint.sh"]
CMD ["postgres"]
