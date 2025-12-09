#!/bin/bash

echo "=========================================="
echo "Teste de Funcionalidade do PostgreSQL + pgBackRest"
echo "=========================================="

# Test 1: PostgreSQL connection
echo "1. Testando conexão com PostgreSQL..."
if docker exec postgres-ba-primary psql -U postgres -d postgres -c "SELECT version();" >/dev/null 2>&1; then
    echo "   ✅ PostgreSQL está funcionando"
else
    echo "   ❌ Erro na conexão com PostgreSQL"
    exit 1
fi

# Test 2: pgBackRest stanza status
echo "2. Verificando status do stanza pgBackRest..."
STANZA_STATUS=$(docker exec postgres-ba-primary pgbackrest --stanza=main-v18 info --output=text | grep "status:" | head -1 | awk '{print $2}')
if [ "$STANZA_STATUS" = "ok" ]; then
    echo "   ✅ Stanza pgBackRest está funcionando"
else
    echo "   ❌ Problemas com o stanza pgBackRest: $STANZA_STATUS"
    exit 1
fi

# Test 3: WAL archiving
echo "3. Verificando arquivamento de WAL..."
docker exec postgres-ba-primary psql -U postgres -d postgres -c "SELECT pg_switch_wal();" >/dev/null 2>&1
sleep 3
WAL_COUNT=$(docker exec postgres-ba-primary pgbackrest --stanza=main-v18 info --output=text | grep "wal archive min/max" | wc -l)
if [ "$WAL_COUNT" -gt 0 ]; then
    echo "   ✅ WAL archiving está funcionando"
else
    echo "   ❌ Problemas com WAL archiving"
    exit 1
fi

# Test 4: Create test data and backup
echo "4. Criando dados de teste e executando backup..."
docker exec postgres-ba-primary psql -U postgres -d postgres -c "
CREATE TABLE IF NOT EXISTS test_backup (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO test_backup (data) VALUES ('Test data for backup validation');
" >/dev/null 2>&1

echo "5. Executando backup incremental..."
docker exec postgres-ba-primary pgbackrest --stanza=main-v18 backup --type=diff >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "   ✅ Backup incremental executado com sucesso"
else
    echo "   ❌ Erro no backup incremental"
    exit 1
fi

# Final status
echo ""
echo "=========================================="
echo "Status Final:"
echo "=========================================="
docker exec postgres-ba-primary pgbackrest --stanza=main-v18 info

echo ""
echo "✅ Todos os testes passaram! O sistema está funcionando corretamente."
echo ""
echo "Configuração atual:"
echo "- Stanza: main-v18"
echo "- Path S3: /postgres-ba-v18-new"
echo "- PostgreSQL 18 com volumes atualizados"
echo "- WAL archiving funcionando"
echo "- Backups funcionando"