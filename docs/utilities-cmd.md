# Ver status dos backups

docker exec postgres-ba-primary pgbackrest --stanza=main info

# Fazer backup manual

docker exec -u postgres postgres-ba-primary pgbackrest --stanza=main --type=incr backup

# Ver logs do PostgreSQL

docker logs -f postgres-ba-primary

# Ver logs de backup

docker exec postgres-ba-primary cat /var/log/pgbackrest/backup-cron.log

# Conectar ao banco

docker exec -it postgres-ba-primary psql -U postgres
