# PostgreSQL Cluster - Primary + Replica com Restauração do S3

Este setup permite restaurar um cluster PostgreSQL completo (Primary + Replica) a partir de backups armazenados no S3 usando pgBackRest.

## 📋 Arquitetura

```
┌─────────────────────────────────────────────────────┐
│                      S3 Bucket                      │
│              (pgBackRest Backups)                   │
└──────────────┬──────────────────┬───────────────────┘
               │                  │
               │ Restore          │ Restore
               ▼                  ▼
┌──────────────────────┐   ┌──────────────────────┐
│   Primary (5433)     │◄──┤   Replica (5434)     │
│  Read/Write          │   │   Read-Only          │
│  Archive WAL         │───┤   Stream Replication │
└──────────────────────┘   └──────────────────────┘
```

## 🚀 Como Usar

### 1. Configurar Credenciais S3

Primeiro, copie o arquivo de exemplo e configure suas credenciais:

```bash
cp .env.cluster.example .env
```

Edite o arquivo `.env` e configure:

- `S3_BUCKET`: Nome do seu bucket S3
- `S3_ACCESS_KEY`: Sua access key
- `S3_SECRET_KEY`: Sua secret key
- `S3_ENDPOINT`: Endpoint do S3 (padrão: s3.amazonaws.com)
- `S3_REGION`: Região do S3 (padrão: us-east-1)
- `S3_PATH`: Caminho dentro do bucket (padrão: /pgbackrest)

### 2. Iniciar o Cluster

Use o script helper para gerenciar o cluster:

```bash
# Iniciar o cluster (primary + replica)
./cluster-manager.sh start

# Verificar status
./cluster-manager.sh status

# Testar conexões e replicação
./cluster-manager.sh test
```

### 3. Verificar Restauração

Ambos os serviços (primary e replica) serão restaurados do mesmo backup no S3:

```bash
# Verificar logs do primary
./cluster-manager.sh logs-primary

# Verificar logs da replica
./cluster-manager.sh logs-replica
```

### 4. Conectar ao PostgreSQL

```bash
# Conectar ao Primary (leitura e escrita)
psql -h localhost -p 5433 -U postgres -d testdb

# Conectar à Replica (somente leitura)
psql -h localhost -p 5434 -U postgres -d testdb
```

Ou use o script:

```bash
# Shell interativo no primary
./cluster-manager.sh psql-primary

# Shell interativo na replica
./cluster-manager.sh psql-replica
```

## 🔍 Comandos Disponíveis

O script `cluster-manager.sh` oferece os seguintes comandos:

| Comando        | Descrição                                      |
| -------------- | ---------------------------------------------- |
| `start`        | Inicia o cluster (primary + replica)           |
| `stop`         | Para o cluster                                 |
| `restart`      | Reinicia o cluster                             |
| `status`       | Mostra o status dos serviços                   |
| `logs-primary` | Mostra logs do primary                         |
| `logs-replica` | Mostra logs da replica                         |
| `logs`         | Mostra logs de todos os serviços               |
| `test`         | Testa as conexões e replicação                 |
| `cleanup`      | Remove o cluster e todos os volumes (CUIDADO!) |
| `exec-primary` | Abre shell no container primary                |
| `exec-replica` | Abre shell no container replica                |
| `psql-primary` | Conecta ao PostgreSQL no primary               |
| `psql-replica` | Conecta ao PostgreSQL na replica               |

## 🔧 Verificações Importantes

### Verificar Replicação

```bash
# No primary, verificar conexões de replicação
docker exec postgres-cluster-primary psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"

# Na replica, verificar status
docker exec postgres-cluster-replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

### Verificar Dados Restaurados

```bash
# Listar databases no primary
docker exec postgres-cluster-primary psql -U postgres -c "\l"

# Verificar se os dados estão na replica também
docker exec postgres-cluster-replica psql -U postgres -c "\l"
```

### Verificar Logs do pgBackRest

```bash
# Ver logs de restauração do primary
docker exec postgres-cluster-primary cat /var/log/pgbackrest/main-restore.log

# Ver logs de restauração da replica
docker exec postgres-cluster-replica cat /var/log/pgbackrest/main-restore.log
```

## 🌐 Adminer (Interface Web)

O Adminer está disponível em: http://localhost:8081

**Conexão com Primary:**

- Sistema: PostgreSQL
- Servidor: postgres-cluster-primary
- Usuário: postgres
- Senha: (conforme configurado no .env)

**Conexão com Replica:**

- Sistema: PostgreSQL
- Servidor: postgres-cluster-replica
- Usuário: postgres
- Senha: (conforme configurado no .env)

## 📦 Volumes

O cluster usa volumes separados para cada instância:

- `postgres_cluster_primary_data`: Dados do primary
- `postgres_cluster_primary_logs`: Logs do primary
- `postgres_cluster_replica_data`: Dados da replica
- `postgres_cluster_replica_logs`: Logs da replica

## 🧪 Testando o Cluster

### Teste 1: Verificar Restauração

```bash
# Iniciar cluster
./cluster-manager.sh start

# Aguardar restauração (verificar logs)
./cluster-manager.sh logs

# Testar conexões
./cluster-manager.sh test
```

### Teste 2: Verificar Replicação

```bash
# Conectar ao primary e criar uma tabela
docker exec -it postgres-cluster-primary psql -U postgres -d testdb -c "CREATE TABLE test_replication (id SERIAL, data TEXT);"

# Inserir dados no primary
docker exec -it postgres-cluster-primary psql -U postgres -d testdb -c "INSERT INTO test_replication (data) VALUES ('teste 1'), ('teste 2');"

# Verificar se os dados aparecem na replica (pode levar alguns segundos)
docker exec -it postgres-cluster-replica psql -U postgres -d testdb -c "SELECT * FROM test_replication;"
```

### Teste 3: Tentar Escrever na Replica (deve falhar)

```bash
# Isso deve retornar erro (replica é read-only)
docker exec -it postgres-cluster-replica psql -U postgres -d testdb -c "INSERT INTO test_replication (data) VALUES ('deve falhar');"
```

## 🛑 Parar e Limpar

```bash
# Parar cluster (mantém volumes)
./cluster-manager.sh stop

# Limpar tudo (REMOVE VOLUMES)
./cluster-manager.sh cleanup
```

## ⚙️ Configurações Avançadas

### Ajustar Performance

Edite o arquivo `.env` para ajustar:

```bash
SHARED_BUFFERS=512MB
EFFECTIVE_CACHE_SIZE=2GB
MAINTENANCE_WORK_MEM=128MB
WORK_MEM=8MB
```

### Ajustar Portas

```bash
POSTGRES_PRIMARY_PORT=5433
POSTGRES_REPLICA_PORT=5434
ADMINER_PORT=8081
```

### Ajustar Paralelismo do pgBackRest

```bash
PGBACKREST_PROCESS_MAX=8  # Mais threads para restauração mais rápida
```

## 🔍 Troubleshooting

### Primary não inicia

```bash
# Verificar logs detalhados
docker logs postgres-cluster-primary

# Verificar configuração do pgBackRest
docker exec postgres-cluster-primary cat /etc/pgbackrest/pgbackrest.conf
```

### Replica não conecta ao Primary

```bash
# Verificar conectividade
docker exec postgres-cluster-replica pg_isready -h postgres-cluster-primary -p 5432

# Verificar pg_hba.conf do primary
docker exec postgres-cluster-primary cat /var/lib/postgresql/data/pgdata/pg_hba.conf
```

### Restauração falha

```bash
# Verificar se o backup existe no S3
docker exec postgres-cluster-primary pgbackrest --stanza=main info

# Verificar logs de erro
docker exec postgres-cluster-primary cat /var/log/pgbackrest/main-restore.log
```

## 📚 Referências

- [pgBackRest Documentation](https://pgbackrest.org/user-guide.html)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
