# Fluxo do Entrypoint - PostgreSQL com pgBackRest

Este documento descreve o fluxo de inicialização da imagem `postgres-ba`.

## Visão Geral

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CONTAINER START                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         entrypoint.sh                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ PRE-INIT PHASE (sempre executa)                                      │    │
│  │                                                                       │    │
│  │  1. 00-setup-directories.sh     → Cria diretórios e permissões       │    │
│  │  2. 01-restore-from-backup.sh   → Restore S3 (se DB não existe)      │    │
│  │  3. 02-setup-replica.sh         → pg_basebackup (se PG_MODE=replica) │    │
│  │  4. 10-configure-ssl.sh         → Gera/configura certificados SSL    │    │
│  │  5. 20-configure-pgbackrest-postgres.sh → Config pgBackRest + PG     │    │
│  │  6. 99-post-init.sh             → Cron + init-db.sh em background    │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ exec docker-entrypoint.sh (oficial PostgreSQL)                       │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
                    ▼                               ▼
        ┌─────────────────────┐         ┌─────────────────────┐
        │   DB NÃO EXISTE     │         │    DB JÁ EXISTE     │
        └─────────────────────┘         └─────────────────────┘
                    │                               │
                    ▼                               │
        ┌─────────────────────┐                     │
        │      initdb         │                     │
        └─────────────────────┘                     │
                    │                               │
                    ▼                               │
        ┌─────────────────────┐                     │
        │ /docker-entrypoint- │                     │
        │ initdb.d/*.sh       │                     │
        │                     │                     │
        │ • 30-init-db.sh     │                     │
        │   └─ init-db.sh     │                     │
        │      (stanza+backup)│                     │
        └─────────────────────┘                     │
                    │                               │
                    └───────────────┬───────────────┘
                                    │
                                    ▼
                    ┌─────────────────────────────────┐
                    │      PostgreSQL Running         │
                    └─────────────────────────────────┘
                                    │
                                    ▼
                    ┌─────────────────────────────────┐
                    │  init-db.sh (background)        │
                    │  - Aguarda 10s                  │
                    │  - Verifica se stanza existe    │
                    │  - Cria stanza se necessário    │
                    │  - Faz backup full se novo      │
                    │  (IDEMPOTENTE)                  │
                    └─────────────────────────────────┘
```

## Fluxos por Cenário

### Cenário 1: Primeiro Start (DB Novo)

```
entrypoint.sh
    │
    ├─► 00-setup-directories.sh     ✓ Cria diretórios
    ├─► 01-restore-from-backup.sh   ✗ Skip (RESTORE_FROM_BACKUP não definido)
    ├─► 02-setup-replica.sh         ✗ Skip (PG_MODE != replica)
    ├─► 10-configure-ssl.sh         ✓ Gera certificados
    ├─► 20-configure-pgbackrest-postgres.sh
    │       ├─► configure-pgbackrest.sh  ✓ Cria pgbackrest.conf
    │       └─► configure-postgres.sh    ✓ postgresql.auto.conf
    ├─► 99-post-init.sh
    │       ├─► setup-cron.sh            ✓ Instala cron jobs
    │       └─► init-db.sh (background)  ✓ Agendado para 10s após start
    │
    └─► docker-entrypoint.sh
            ├─► initdb                   ✓ Cria database
            ├─► 30-init-db.sh            ✓ Chama init-db.sh
            │       └─► init-db.sh       ✓ Cria stanza + backup full
            └─► START PostgreSQL         ✓ Servidor rodando
```

### Cenário 2: Restart (DB Existente)

```
entrypoint.sh
    │
    ├─► 00-setup-directories.sh     ✓ Verifica diretórios
    ├─► 01-restore-from-backup.sh   ✗ Skip (DB existe)
    ├─► 02-setup-replica.sh         ✗ Skip (DB existe)
    ├─► 10-configure-ssl.sh         ✓ Verifica certificados
    ├─► 20-configure-pgbackrest-postgres.sh
    │       ├─► configure-pgbackrest.sh  ✓ Atualiza pgbackrest.conf
    │       └─► configure-postgres.sh    ✓ Atualiza postgresql.auto.conf
    ├─► 99-post-init.sh
    │       ├─► setup-cron.sh            ✓ Reinstala cron jobs
    │       └─► init-db.sh (background)  ✓ Agendado para 10s após start
    │
    └─► docker-entrypoint.sh
            ├─► initdb                   ✗ Skip (DB existe)
            ├─► 30-init-db.sh            ✗ Skip (initdb.d não roda)
            └─► START PostgreSQL         ✓ Servidor rodando
                    │
                    └─► init-db.sh       ✓ Verifica stanza (já existe, skip)
```

### Cenário 3: Restore do S3

```
entrypoint.sh
    │
    ├─► 00-setup-directories.sh     ✓ Cria diretórios
    ├─► 01-restore-from-backup.sh   ✓ RESTORE_FROM_BACKUP=true
    │       └─► pgbackrest restore  ✓ Baixa backup do S3
    ├─► 02-setup-replica.sh         ✗ Skip
    ├─► 10-configure-ssl.sh         ✓ Configura SSL
    ├─► 20-configure-pgbackrest-postgres.sh
    │       └─► configure-pgbackrest.sh  ✓
    │       └─► configure-postgres.sh    ✓
    ├─► 99-post-init.sh             ✓ Cron + init-db.sh
    │
    └─► docker-entrypoint.sh
            └─► START PostgreSQL    ✓ (DB restaurado, initdb.d não roda)
```

### Cenário 4: Replica Mode

```
entrypoint.sh
    │
    ├─► 00-setup-directories.sh     ✓ Cria diretórios
    ├─► 01-restore-from-backup.sh   ✗ Skip
    ├─► 02-setup-replica.sh         ✓ PG_MODE=replica
    │       └─► pg_basebackup       ✓ Copia do primary
    ├─► 10-configure-ssl.sh         ✓ Configura SSL
    ├─► 20-configure-pgbackrest-postgres.sh
    │       └─► configure-pgbackrest.sh  ✗ Skip (replica)
    │       └─► configure-postgres.sh    ✓
    ├─► 99-post-init.sh             ✗ Skip (replica não faz backup)
    │
    └─► docker-entrypoint.sh
            └─► START PostgreSQL    ✓ (modo replica)
```

### Cenário 5: DB Pré-Existente (migração da imagem oficial)

```
# Container com volume de DB criado pela imagem postgres:18-alpine oficial

entrypoint.sh
    │
    ├─► 00-setup-directories.sh     ✓ Cria diretórios pgBackRest
    ├─► 01-restore-from-backup.sh   ✗ Skip (DB existe)
    ├─► 02-setup-replica.sh         ✗ Skip (DB existe)
    ├─► 10-configure-ssl.sh         ✓ Gera/configura SSL
    ├─► 20-configure-pgbackrest-postgres.sh
    │       ├─► configure-pgbackrest.sh  ✓ Cria pgbackrest.conf
    │       └─► configure-postgres.sh    ✓ Adiciona archive_mode, etc
    ├─► 99-post-init.sh
    │       ├─► setup-cron.sh            ✓ Instala cron jobs
    │       └─► init-db.sh (background)  ✓ Cria stanza + backup full
    │
    └─► docker-entrypoint.sh
            └─► START PostgreSQL    ✓
                    │
                    └─► init-db.sh  ✓ Cria stanza + primeiro backup
```

## Scripts e Responsabilidades

| Script                                | Quando Executa                           | Responsabilidade                    |
| ------------------------------------- | ---------------------------------------- | ----------------------------------- |
| `00-setup-directories.sh`             | Sempre                                   | Criar diretórios e permissões       |
| `01-restore-from-backup.sh`           | DB não existe + RESTORE_FROM_BACKUP=true | Restore do S3                       |
| `02-setup-replica.sh`                 | DB não existe + PG_MODE=replica          | pg_basebackup do primary            |
| `10-configure-ssl.sh`                 | Sempre                                   | Gerar/verificar certificados SSL    |
| `20-configure-pgbackrest-postgres.sh` | Sempre                                   | Configurar pgBackRest e PostgreSQL  |
| `99-post-init.sh`                     | Sempre (se pgBackRest habilitado)        | Cron + agendar init-db.sh           |
| `30-init-db.sh`                       | Só DB novo (via initdb.d)                | Delega para init-db.sh              |
| `init-db.sh`                          | Background (10s após start)              | Criar stanza + backup (idempotente) |

## Variáveis de Ambiente

| Variável                         | Descrição                 | Exemplo                |
| -------------------------------- | ------------------------- | ---------------------- |
| `PGBACKREST_STANZA`              | Nome do stanza            | `my-db`                |
| `PG_MODE`                        | Modo de operação          | `primary` ou `replica` |
| `RESTORE_FROM_BACKUP`            | Ativa restore do S3       | `true`                 |
| `PRIMARY_HOST`                   | Host do primary (replica) | `postgres-primary`     |
| `PGBACKREST_REPO1_S3_BUCKET`     | Bucket S3                 | `my-backups`           |
| `PGBACKREST_REPO1_S3_ENDPOINT`   | Endpoint S3               | `s3.amazonaws.com`     |
| `PGBACKREST_REPO1_S3_KEY`        | Access Key S3             | `AKIA...`              |
| `PGBACKREST_REPO1_S3_KEY_SECRET` | Secret Key S3             | `secret...`            |
| `PGBACKREST_REPO1_S3_REGION`     | Região S3                 | `us-east-1`            |

## Idempotência

Todos os scripts são **idempotentes**:

- `configure-postgres.sh`: Usa `postgresql.auto.conf` (recriado a cada start)
- `configure-pgbackrest.sh`: Sobrescreve `pgbackrest.conf`
- `setup-cron.sh`: Reinstala crontab
- `init-db.sh`: Verifica se stanza existe antes de criar

## Compatibilidade Drop-in

A imagem é 100% compatível como drop-in replacement:

1. **Sem pgBackRest**: Se `PGBACKREST_STANZA` não definido, funciona igual à imagem oficial
2. **DB existente**: Volumes de DBs criados com `postgres:18-alpine` funcionam sem modificação
3. **Entrypoint oficial**: Sempre chamado via `exec docker-entrypoint.sh`
