# Alterações na Estrutura de Testes

## Resumo das Mudanças

A estrutura de testes foi refatorada para usar um único serviço MinIO compartilhado por todos os cenários de teste, ao invés de cada cenário ter sua própria instância do MinIO.

## O que mudou:

### 1. MinIO Centralizado
- **Criado**: `/tests/docker-compose.yml` - Serviço MinIO compartilhado
- **Portas**: 9000 (S3 API) e 9001 (Console)
- **Network**: `tests-network` - rede compartilhada entre MinIO e todos os testes

### 2. Buckets Separados
Cada cenário agora usa seu próprio bucket no MinIO:
- Scenario 1: `scenario1`
- Scenario 2: `scenario2`
- Scenario 3: `scenario3`
- Scenario 4: `scenario4`
- Scenario 5: `scenario5`

### 3. Arquivos .env Atualizados
Cada arquivo `.env` foi atualizado:
- `PGBACKREST_S3_BUCKET`: mudou de `pgbackrest` para `scenarioX`
- `PGBACKREST_S3_PATH`: mudou de `/backup/scenarioX` para `/backup`

### 4. docker-compose.yml de Cada Cenário
Removido de cada compose:
- Serviços `minio-certs`
- Serviços `minio`
- Serviços `minio-setup`
- Volumes `minio-data` e `minio-certs`
- Dependências `depends_on: minio-setup`

Adicionado em cada compose:
- Network externa `tests-network`
- Cada serviço PostgreSQL conectado à network `tests-network`

### 5. Scripts de Gerenciamento
**Criados**:
- `start-minio.sh` - Inicia o MinIO e cria todos os buckets
- `stop-minio.sh` - Para o MinIO
- `README.md` - Documentação completa da nova estrutura

**Atualizado**:
- `run-all-tests.sh` - Verifica e inicia MinIO automaticamente antes dos testes

## Como usar:

### Opção 1: Testes Individuais
```bash
# 1. Iniciar MinIO (uma vez)
cd tests
./start-minio.sh

# 2. Executar qualquer teste
cd scenario-1-new-db
./test.sh
```

### Opção 2: Todos os Testes
```bash
cd tests
./run-all-tests.sh  # Inicia MinIO automaticamente
```

## Vantagens da nova estrutura:

1. **Eficiência de recursos**: Uma única instância MinIO ao invés de 5
2. **Evita conflitos de porta**: Apenas as portas 9000 e 9001 são usadas
3. **Inicialização mais rápida**: MinIO inicia uma vez e fica disponível para todos os testes
4. **Isolamento mantido**: Cada cenário tem seu próprio bucket e caminhos
5. **Mais realista**: Simula melhor um ambiente de produção onde o S3 é compartilhado
6. **Facilita debugging**: Console do MinIO acessível em https://localhost:9001

## Isolamento entre cenários:

Apesar de compartilhar o MinIO, cada cenário mantém seu isolamento através de:
- **Buckets diferentes**: scenario1, scenario2, etc.
- **Portas PostgreSQL diferentes**: 5501, 5502, 5503, etc.
- **Volumes Docker separados**: scenario1-postgres-data, scenario2-postgres-data, etc.
- **Containers com nomes únicos**: scenario1-postgres, scenario2-postgres, etc.
- **Stanzas pgBackRest diferentes**: test-scenario1, test-scenario2, etc.
