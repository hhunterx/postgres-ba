# Fluxo do Entrypoint e Cenários de Teste

## Índice

1. [Visão Geral](#visão-geral)
2. [Fluxo Completo do Entrypoint](#fluxo-completo-do-entrypoint)
3. [Árvore de Decisão](#árvore-de-decisão)
4. [Cenários de Teste Necessários](#cenários-de-teste-necessários)
5. [Mapeamento: Requisitos → Cenários](#mapeamento-requisitos--cenários)
6. [Gaps Identificados](#gaps-identificados)

---

## Visão Geral

A imagem PostgreSQL com pgBackRest segue um fluxo de inicialização dividido em 3 fases principais:

1. **Fase Pré-Inicialização**: Executa antes do `docker-entrypoint.sh` oficial
2. **Fase de Inicialização**: Delega para o `docker-entrypoint.sh` oficial do PostgreSQL
3. **Fase Pós-Inicialização**: Scripts executados via `/docker-entrypoint-initdb.d/` (apenas em novos bancos)

---

## Fluxo Completo do Entrypoint

### Fase 1: Pré-Inicialização (Sempre Executa)

```
entrypoint.sh
    │
    ├─► 00-setup-directories.sh
    │   ├─ Se PGDATA existe com PG_VERSION → ajusta permissões
    │   └─ Se PGDATA não existe → prepara diretório pai
    │   └─ Cria diretórios pgBackRest (se PGBACKREST_STANZA definido)
    │   └─ Cria diretório SSL
    │
    ├─► 01-configure-pgbackrest.sh
    │   ├─ Se PGBACKREST_STANZA definido E PG_MODE ≠ replica
    │   │  └─ Chama configure-pgbackrest.sh
    │   │     ├─ Gera /etc/pgbackrest/pgbackrest.conf
    │   │     ├─ Configura repo S3 ou local
    │   │     └─ Define opções de compressão/retenção
    │   └─ Se PG_MODE = replica → pula configuração
    │
    ├─► 02-restore-from-backup.sh
    │   ├─ Verifica RESTORE_FROM_BACKUP=true
    │   ├─ Verifica se PGDATA não existe (PG_VERSION ausente)
    │   ├─ Valida que PG_MODE ≠ replica (conflito)
    │   ├─ Verifica existência de backup com pgbackrest info
    │   ├─ Executa: pgbackrest --stanza=X --delta restore
    │
    ├─► 03-setup-replica.sh
    │   ├─ Verifica PG_MODE=replica
    │   ├─ Verifica se PGDATA não existe (PG_VERSION ausente)
    │   ├─ Valida PRIMARY_HOST definido
    │   ├─ Aguarda primary ficar ready (pg_isready)
    │   ├─ Cria replication slot no primary
    │   ├─ Executa: pg_basebackup -R (cria standby.signal + postgresql.auto.conf)
    │   └─ Nota: configure-postgres.sh reconstruirá postgresql.auto.conf
    │
    ├─► 04-configure-ssl.sh
    │   ├─ Verifica se certificados existem em /etc/postgresql/ssl/
    │   ├─ Se não existem → gera certificados auto-assinados
    │   └─ Ajusta permissões (chown postgres:postgres)
    │
    ├─► 09-configure-cron.sh
    │   ├─ Se PGBACKREST_STANZA definido E PG_MODE ≠ replica
    │   │  └─ Chama setup-cron.sh
    │   │     ├─ Configura cron para full (semanal)
    │   │     ├─ Configura cron para diff (diário)
    │   │     └─ Configura cron para incr (a cada 30min)
    │   └─ Se PG_MODE = replica → não configura cron
    │
    └─► 10-configure-postgres.sh (APENAS se PGDATA existe)
        └─ Se PGDATA/PG_VERSION existe
           └─ Chama configure-postgres.sh
              ├─ Edita postgresql.auto.conf
              ├─ Configura WAL (wal_level, max_wal_senders, archive_mode, etc)
              ├─ Se PG_MODE = replica → configura hot_standby, primary_conninfo
              └─ Se pgBackRest ativo → configura archive_command
```

### Fase 2: Inicialização (Delega para Oficial)

```
docker-entrypoint.sh (oficial)
    │
    ├─ Se PGDATA vazio
    │  ├─ Executa initdb
    │  ├─ Cria postgresql.auto.conf
    │  ├─ Executa scripts em /docker-entrypoint-initdb.d/ (ordem alfabética)
    │  │  └─ 20-new-db-only.sh
    │  │     └─ Chama configure-postgres.sh
    │  │        ├─ Configura WAL e replicação
    │  │        └─ Configura archive_command
    │  └─ Inicia PostgreSQL
    │
    └─ Se PGDATA existe
       └─ Inicia PostgreSQL
```

### Fase 3: Pós-Inicialização (Background)

```
99-stanza-check.sh (executado em background após 15s)
    │
    ├─ Se PGBACKREST_STANZA definido E PG_MODE ≠ replica
    │  ├─ Aguarda PostgreSQL ready (pg_isready)
    │  ├─ Verifica se stanza já existe (pgbackrest info)
    │  ├─ Se não existe:
    │  │  ├─ Cria stanza (pgbackrest --stanza=X stanza-create)
    │  │  └─ Executa backup inicial full
    │  └─ Se já existe → apenas reporta
    │
    └─ Se PG_MODE = replica → não executa
```

---

## Árvore de Decisão

```
┌─────────────────────────────────────┐
│   Container Start (entrypoint.sh)   │
└───────────────┬─────────────────────┘
                │
                ▼
        ┌───────────────┐
        │ PGDATA existe?│
        │ (PG_VERSION)  │
        └───┬───────┬───┘
            │       │
          SIM      NÃO
            │       │
            │       ▼
            │   ┌─────────────────┐
            │   │ PG_MODE=replica?│
            │   └───┬─────────┬───┘
            │       │         │
            │      SIM       NÃO
            │       │         │
            │       │         ▼
            │       │   ┌────────────────────┐
            │       │   │ RESTORE_FROM_      │
            │       │   │   BACKUP=true?     │
            │       │   └─┬──────────────┬───┘
            │       │     │              │
            │       │    SIM            NÃO
            │       │     │              │
            │       │     ▼              ▼
            │       │  ┌─────┐      ┌─────┐
            │       │  │ (3) │      │ (1) │
            │       │  │RESTO│      │ NEW │
            │       │  │ RE  │      │ DB  │
            │       │  └─────┘      └─────┘
            │       │
            │       ▼
            │   ┌─────┐
            │   │ (4) │
            │   │REPLI│
            │   │ CA  │
            │   └─────┘
            │
            ▼
    ┌────────────────────┐
    │ PG_MODE=replica?   │
    └─┬──────────────┬───┘
      │              │
     SIM            NÃO
      │              │
      ▼              ▼
   ┌─────┐      ┌─────┐
   │ (4) │      │ (2) │
   │REPLI│      │RESTA│
   │ CA  │      │ RT  │
   │EXIST│      │EXIST│
   └─────┘      └─────┘
                   │
                   ▼
            ┌──────────────┐
            │ Migração de  │
            │ postgres:18? │
            └──┬───────┬───┘
               │       │
              SIM     NÃO
               │       │
               ▼       │
            ┌─────┐   │
            │ (5) │   │
            │MIGRA│   │
            │ ÇÃO │   │
            └─────┘   │
                      │
            (restart normal)
```

**Legenda:**

- **(1) NEW DB**: Novo banco de dados do zero
- **(2) RESTART EXIST**: Restart de banco existente
- **(3) RESTORE**: Restore de backup S3
- **(4) REPLICA**: Modo replica (pg_basebackup)
- **(5) MIGRAÇÃO**: Migração de banco oficial postgres:18

---

## Cenários de Teste Necessários

### Cenário 1: Novo Banco de Dados ✅ (Atual)

**Objetivo**: Testar criação de banco do zero com pgBackRest

**Condições Iniciais**:

- PGDATA vazio
- PG_MODE não definido (ou "primary")
- RESTORE_FROM_BACKUP=false
- PGBACKREST_STANZA definido

**Fluxo Esperado**:

1. `00-setup-directories.sh` → cria estrutura
2. `01-configure-pgbackrest.sh` → configura pgBackRest
3. `02-restore-from-backup.sh` → pula (RESTORE_FROM_BACKUP=false)
4. `03-setup-replica.sh` → pula (PG_MODE ≠ replica)
5. `04-configure-ssl.sh` → gera certificados
6. `09-configure-cron.sh` → configura cron de backups
7. `docker-entrypoint.sh` → executa initdb
8. `/docker-entrypoint-initdb.d/20-new-db-only.sh` → configura PostgreSQL
9. PostgreSQL inicia
10. `99-stanza-check.sh` → cria stanza + backup inicial

**Validações**:

- [ ] PostgreSQL inicia com sucesso
- [ ] Certificados SSL criados e funcionando
- [ ] pgBackRest configurado corretamente
- [ ] Stanza criada no S3/repo
- [ ] Backup inicial full executado
- [ ] WAL archiving funcionando (archive_command)
- [ ] Cron configurado (full, diff, incr)
- [ ] Logs indicam sucesso em todas as etapas

---

### Cenário 2: Restart de Banco Existente ✅ (Atual)

**Objetivo**: Testar restart de container com banco já criado

**Condições Iniciais**:

- PGDATA existe com PG_VERSION
- PG_MODE não definido (ou "primary")
- PGBACKREST_STANZA definido

**Fluxo Esperado**:

1. `00-setup-directories.sh` → ajusta permissões
2. `01-configure-pgbackrest.sh` → re-configura pgBackRest
3. `02-restore-from-backup.sh` → pula (PGDATA existe)
4. `03-setup-replica.sh` → pula (PGDATA existe)
5. `04-configure-ssl.sh` → valida/re-cria certificados
6. `09-configure-cron.sh` → re-configura cron
7. `10-configure-postgres.sh` → re-aplica configurações PostgreSQL
8. `docker-entrypoint.sh` → inicia PostgreSQL
9. `99-stanza-check.sh` → valida stanza (não re-cria)

**Validações**:

- [ ] PostgreSQL inicia sem erros
- [ ] Dados persistidos mantidos
- [ ] pgBackRest ainda funcional
- [ ] Cron ainda ativo
- [ ] Não executa initdb novamente
- [ ] Não executa scripts de /docker-entrypoint-initdb.d/
- [ ] Configurações preservadas

---

### Cenário 3: Restore de Backup ✅ (Atual)

**Objetivo**: Testar restore completo de backup do S3

**Condições Iniciais**:

- PGDATA vazio
- PG_MODE não definido (ou "primary")
- RESTORE_FROM_BACKUP=true
- PGBACKREST_STANZA definido
- **Pré-requisito**: Backup existente no S3/repo

**Preparação do Teste**:

1. Criar banco primário
2. Popular com dados de teste
3. Executar backup
4. Destruir container e volumes
5. Iniciar container com RESTORE_FROM_BACKUP=true

**Fluxo Esperado**:

1. `00-setup-directories.sh` → cria estrutura
2. `01-configure-pgbackrest.sh` → configura pgBackRest
3. `02-restore-from-backup.sh` → **EXECUTA RESTORE**
   - Valida backup existe (pgbackrest info)
   - Executa pgbackrest restore
4. `03-setup-replica.sh` → pula (PG_MODE ≠ replica)
5. `04-configure-ssl.sh` → gera/valida certificados
6. `09-configure-cron.sh` → configura cron
7. `10-configure-postgres.sh` → pula (será configurado depois)
8. `docker-entrypoint.sh` → **NÃO executa initdb** (PGDATA já populado)
9. PostgreSQL inicia
10. `99-stanza-check.sh` → valida stanza

**Validações**:

- [ ] Restore completa com sucesso
- [ ] Dados restaurados corretamente
- [ ] PostgreSQL inicia normalmente
- [ ] WAL archiving funciona após restore
- [ ] Backup incremental funciona após restore
- [ ] Não executa initdb
- [ ] Configurações PostgreSQL aplicadas

---

### Cenário 4: Modo Replica ✅ (Atual)

**Objetivo**: Testar criação de replica via pg_basebackup

**Condições Iniciais**:

- PGDATA vazio
- PG_MODE=replica
- PRIMARY_HOST definido
- POSTGRES_USER, POSTGRES_PASSWORD definidos
- **Pré-requisito**: Primary rodando e acessível

**Preparação do Teste**:

1. Iniciar primary com replicação habilitada
2. Popular primary com dados
3. Iniciar replica apontando para primary

**Fluxo Esperado (Replica)**:

1. `00-setup-directories.sh` → cria estrutura
2. `01-configure-pgbackrest.sh` → **PULA** (replica não usa pgBackRest)
3. `02-restore-from-backup.sh` → pula (PG_MODE=replica, conflito)
4. `03-setup-replica.sh` → **EXECUTA**
   - Aguarda primary ready
   - Cria replication slot no primary
   - Executa pg_basebackup -R
   - Cria standby.signal
   - Gera postgresql.auto.conf inicial
5. `04-configure-ssl.sh` → gera certificados
6. `09-configure-cron.sh` → **PULA** (replica não faz backup)
7. `10-configure-postgres.sh` → pula (será configurado depois)
8. `docker-entrypoint.sh` → **NÃO executa initdb** (PGDATA já populado)
9. `20-new-db-only.sh` → **NÃO executa** (não é novo DB)
10. PostgreSQL inicia em modo standby
11. `99-stanza-check.sh` → **NÃO executa** (PG_MODE=replica)

**Fluxo Esperado (Primary)**:

- Configuração normal como Cenário 1
- Adicionar usuário de replicação
- Configurar pg_hba.conf para aceitar replicação

**Validações (Replica)**:

- [ ] pg_basebackup completa com sucesso
- [ ] Replica inicia em modo hot_standby
- [ ] Replicação streaming funciona
- [ ] Dados do primary aparecem na replica
- [ ] standby.signal existe
- [ ] Replica NÃO executa backups pgBackRest
- [ ] Replica NÃO tem cron de backups
- [ ] WAL é recebido via streaming (não archive_command)

**Validações (Primary)**:

- [ ] Primary aceita conexões de replicação
- [ ] Replication slot criado
- [ ] Dados inseridos no primary aparecem na replica

---

### Cenário 5: Migração de Banco Existente (postgres:18 oficial) ✅ (Atual)

**Objetivo**: Testar compatibilidade com banco criado pela imagem oficial

**Condições Iniciais**:

- PGDATA existe (criado por postgres:18-alpine oficial)
- PG_MODE não definido
- PGBACKREST_STANZA definido (primeira vez)
- Banco já tem dados

**Preparação do Teste**:

1. Iniciar postgres:18-alpine oficial
2. Criar database e tabelas
3. Popular com dados
4. Parar container oficial
5. Iniciar nossa imagem com mesmo PGDATA

**Fluxo Esperado**:

1. `00-setup-directories.sh` → ajusta permissões
2. `01-configure-pgbackrest.sh` → configura pgBackRest (primeira vez)
3. `02-restore-from-backup.sh` → pula (PGDATA existe)
4. `03-setup-replica.sh` → pula (PGDATA existe)
5. `04-configure-ssl.sh` → gera certificados
6. `09-configure-cron.sh` → configura cron (primeira vez)
7. `10-configure-postgres.sh` → **CRÍTICO**
   - Aplica configurações WAL
   - Adiciona archive_command
   - Configura replicação
8. `docker-entrypoint.sh` → inicia PostgreSQL
9. `99-stanza-check.sh` → cria stanza + backup inicial

**Validações**:

- [ ] PostgreSQL inicia com banco existente
- [ ] Dados preservados e acessíveis
- [ ] pgBackRest configurado pela primeira vez
- [ ] Stanza criada com sucesso
- [ ] Backup inicial executado
- [ ] WAL archiving começa a funcionar
- [ ] Cron configurado
- [ ] Sem perda de dados
- [ ] Drop-in replacement funciona

---

### Cenário 6: Restore com Delta (Necessário) ⚠️ **FALTANDO**

**Objetivo**: Testar restore com --delta (atualiza apenas diferenças)

**Condições Iniciais**:

- PGDATA existe parcialmente corrompido/incompleto
- RESTORE_FROM_BACKUP=true
- PGBACKREST_STANZA definido

**Fluxo Esperado**:

- Similar ao Cenário 3
- pgbackrest usa --delta para restaurar apenas diferenças
- Arquivos válidos são mantidos

**Validações**:

- [ ] Restore delta funciona
- [ ] Apenas arquivos necessários são baixados
- [ ] Banco volta ao estado consistente

---

### Cenário 7: Testes de Backup (Necessário) ⚠️ **FALTANDO**

**Objetivo**: Validar todos os tipos de backup e retenção

**Sub-cenários**:

#### 7a. Backup Full Manual

- [ ] Executar backup full via comando
- [ ] Validar backup aparece no S3/repo
- [ ] Validar pgbackrest info lista backup

#### 7b. Backup Diff Manual

- [ ] Popular dados após full
- [ ] Executar backup diff
- [ ] Validar backup diff referencia full

#### 7c. Backup Incr Manual

- [ ] Popular mais dados após diff
- [ ] Executar backup incr
- [ ] Validar backup incr referencia diff

#### 7d. Backups via Cron

- [ ] Aguardar cron executar
- [ ] Validar logs do cron
- [ ] Validar backups criados

#### 7e. Retenção de Backups

- [ ] Criar múltiplos backups
- [ ] Validar retenção configurada (full: 2, diff: 7)
- [ ] Validar backups antigos são removidos

---

### Cenário 8: Testes de WAL Archiving (Necessário) ⚠️ **FALTANDO**

**Objetivo**: Validar archive_command e archive_timeout

**Validações**:

- [ ] archive_mode=on
- [ ] archive_timeout=60s funciona
- [ ] WAL files são enviados a cada minuto
- [ ] pgbackrest archive-push funciona
- [ ] WAL files aparecem no S3/repo
- [ ] Logs indicam sucesso no archiving

---

### Cenário 9: Failover Replica → Primary (Necessário) ⚠️ **FALTANDO**

**Objetivo**: Promover replica para primary

**Fluxo**:

1. Iniciar primary + replica (Cenário 4)
2. Parar primary
3. Promover replica (pg_ctl promote)
4. Reconfigurar como primary
5. Habilitar pgBackRest
6. Iniciar backups

**Validações**:

- [ ] Replica promovida com sucesso
- [ ] standby.signal removido
- [ ] PostgreSQL aceita escritas
- [ ] pgBackRest configurado após promoção
- [ ] Backups funcionam no novo primary

---

### Cenário 10: Testes de SSL (Necessário) ⚠️ **PARCIAL**

**Objetivo**: Validar configuração SSL em todos os cenários

**Sub-cenários**:

#### 10a. SSL com Certificados Auto-Gerados

- [ ] Iniciar sem certificados
- [ ] Validar geração automática
- [ ] Validar conexão SSL funciona

#### 10b. SSL com Certificados Fornecidos

- [ ] Fornecer certificados via volume
- [ ] Validar certificados são usados
- [ ] Validar conexão SSL funciona

#### 10c. SSL em Replicação

- [ ] Validar conexão primary→replica usa SSL
- [ ] Validar primary_conninfo tem sslmode

---

### Cenário 11: Testes de Erro (Necessário) ⚠️ **FALTANDO**

**Objetivo**: Validar tratamento de erros e mensagens para usuário

**Sub-cenários**:

#### 11a. Configuração Inválida

- [ ] RESTORE_FROM_BACKUP=true + PG_MODE=replica → erro claro
- [ ] RESTORE_FROM_BACKUP=true sem backup → erro claro
- [ ] PG_MODE=replica sem PRIMARY_HOST → erro claro
- [ ] PGBACKREST_STANZA não definido → mensagens claras

#### 11b. Falhas de Conexão

- [ ] S3 inacessível → erro + sugestão
- [ ] Primary inacessível (replica) → erro + retry

#### 11c. Permissões

- [ ] PGDATA sem permissões → erro claro
- [ ] pgBackRest sem permissões → erro claro

---

## Mapeamento: Requisitos → Cenários

| Requisito                             | Cenários que Cobrem            |
| ------------------------------------- | ------------------------------ |
| 0. Drop-in replacement postgres:18    | Cenário 5 (Migração)           |
| 1. Entrypoint valida PGDATA existente | Cenários 1, 2, 3, 5            |
| 1. Restore de backup S3 se não existe | Cenário 3 (Restore)            |
| 1. Backups sempre configurados        | Cenários 1, 2, 5               |
| 1. Avisos de configuração inválida    | Cenário 11 (Erros) ⚠️          |
| 2. Gerar certificados SSL             | Cenários 1, 3, 4, 5, 10        |
| 2. Sempre rodar em modo SSL           | Cenário 10 ⚠️                  |
| 3. Backups via cron                   | Cenário 7d ⚠️                  |
| 4. Compatibilidade com postgres:18    | Cenário 5                      |
| 4. Backups por intervenção usuário    | Cenário 5 + Scripts manuais    |
| 4. Avisos de configuração inválida    | Cenário 11 ⚠️                  |
| 5. Suporte full, diff, incr           | Cenário 7 ⚠️                   |
| 6. WAL archive_timeout 60s            | Cenário 8 ⚠️                   |
| 7. Modo replica via pg_basebackup     | Cenário 4                      |
| 7. Replica não faz backups            | Cenário 4                      |
| 8. Tudo via variáveis de ambiente     | Todos os cenários              |
| 9. Testes isolados com cleanup        | Implementado em todos ✅       |
| 9. Ciclo de vida completo             | Parcialmente (falha Cenário 7) |

---

## Gaps Identificados

### Cenários de Teste Faltando

1. **Cenário 6**: Restore com Delta ⚠️
2. **Cenário 7**: Testes completos de Backup ⚠️
   - 7a: Full manual
   - 7b: Diff manual
   - 7c: Incr manual
   - 7d: Via cron
   - 7e: Retenção
3. **Cenário 8**: Testes de WAL Archiving ⚠️
4. **Cenário 9**: Failover Replica→Primary ⚠️
5. **Cenário 10**: Testes SSL completos ⚠️
   - 10a: Auto-gerado (parcial)
   - 10b: Fornecido
   - 10c: Em replicação
6. **Cenário 11**: Testes de Erro ⚠️

### Melhorias nos Cenários Existentes

#### Cenário 1 (New DB)

- [ ] Validar que backup inicial foi executado
- [ ] Validar que cron está ativo
- [ ] Validar que WAL archiving funciona
- [ ] Validar SSL está ativo

#### Cenário 2 (Restart)

- [ ] Validar que configurações foram re-aplicadas
- [ ] Validar que cron ainda funciona após restart
- [ ] Validar que não há re-criação de stanza

#### Cenário 3 (Restore)

- [ ] Criar teste de ciclo completo:
  1. Criar DB + popular
  2. Fazer backup
  3. Modificar dados
  4. Destruir container
  5. Restore
  6. Validar dados do backup (não os modificados)
- [ ] Validar que backups continuam após restore

#### Cenário 4 (Replica)

- [ ] Testar replication lag
- [ ] Testar que replica não aceita escritas
- [ ] Testar que WAL streaming funciona
- [ ] Validar que replica não tem cron

#### Cenário 5 (Migração)

- [ ] Validar que usuário é notificado sobre necessidade de backup inicial
- [ ] Validar que script manual está disponível
- [ ] Testar com banco que tem dados críticos

---

## Estrutura Sugerida para Novos Testes

```
tests/
├── run-all-tests.sh
├── scenario-1-new-db/          ✅ Existente
├── scenario-2-restart/         ✅ Existente
├── scenario-3-restore/         ✅ Existente
├── scenario-4-replica/         ✅ Existente
├── scenario-5-existing-db/     ✅ Existente
├── scenario-6-restore-delta/   ⚠️ CRIAR
├── scenario-7-backups/         ⚠️ CRIAR
│   ├── 7a-full-manual/
│   ├── 7b-diff-manual/
│   ├── 7c-incr-manual/
│   ├── 7d-cron/
│   └── 7e-retention/
├── scenario-8-wal-archiving/   ⚠️ CRIAR
├── scenario-9-failover/        ⚠️ CRIAR
├── scenario-10-ssl/            ⚠️ CRIAR
│   ├── 10a-auto-generated/
│   ├── 10b-provided/
│   └── 10c-replication/
└── scenario-11-errors/         ⚠️ CRIAR
    ├── 11a-invalid-config/
    ├── 11b-connection-failures/
    └── 11c-permissions/
```

---

## Prioridades de Implementação

### Alta Prioridade

1. **Cenário 7**: Testes de Backup (crítico para requisito 5)
2. **Cenário 8**: WAL Archiving (crítico para requisito 6)
3. **Cenário 11a**: Configurações Inválidas (requisitos 1 e 4)

### Média Prioridade

4. **Cenário 10b**: SSL com Certificados Fornecidos
5. **Cenário 6**: Restore Delta
6. **Cenário 9**: Failover

### Baixa Prioridade

7. **Cenário 11b/c**: Testes de erro adicionais
8. **Cenário 10c**: SSL em Replicação (já coberto indiretamente)

---

## Conclusão

O fluxo atual do entrypoint está bem estruturado e segue uma lógica clara de decisão baseada em:

- Existência de PGDATA
- Modo de operação (primary/replica)
- Necessidade de restore

Porém, os **testes atuais cobrem apenas ~50% dos requisitos**. Os principais gaps são:

- Validação de backups (manual e automático)
- Validação de WAL archiving
- Tratamento de erros
- Testes completos de SSL

Recomenda-se priorizar a implementação dos Cenários 7 e 8 para garantir que os requisitos principais (backup/restore) estão funcionando corretamente.
