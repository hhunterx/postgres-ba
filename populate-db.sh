#!/bin/bash
set -e

echo "=========================================="
echo "Exemplo: Populando banco de dados"
echo "=========================================="

# Configurações
CONTAINER_NAME="${CONTAINER_NAME:-postgres-ba}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-postgres}"

# Verificar se o container está rodando
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "❌ Container $CONTAINER_NAME não está rodando!"
    echo "Execute: docker compose up -d"
    exit 1
fi

echo "✓ Container encontrado"
echo "Conectando ao PostgreSQL..."

# Criar tabelas se não existirem
docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" << 'EOF'

-- Criar tabela de usuários
CREATE TABLE IF NOT EXISTS usuarios (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    idade INTEGER,
    cidade VARCHAR(100),
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Criar tabela de produtos
CREATE TABLE IF NOT EXISTS produtos (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    descricao TEXT,
    preco DECIMAL(10, 2) NOT NULL,
    estoque INTEGER DEFAULT 0,
    categoria VARCHAR(50),
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Criar tabela de pedidos
CREATE TABLE IF NOT EXISTS pedidos (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER REFERENCES usuarios(id),
    produto_id INTEGER REFERENCES produtos(id),
    quantidade INTEGER NOT NULL,
    total DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pendente',
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

EOF

echo "✓ Tabelas criadas/verificadas com sucesso!"
echo ""
echo "Inserindo dados de exemplo..."

# Inserir usuários
docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" << 'EOF'

-- Inserir usuários (usando ON CONFLICT para evitar duplicatas)
INSERT INTO usuarios (nome, email, idade, cidade) VALUES
    ('João Silva', 'joao.silva@email.com', 28, 'São Paulo'),
    ('Maria Santos', 'maria.santos@email.com', 32, 'Rio de Janeiro'),
    ('Pedro Oliveira', 'pedro.oliveira@email.com', 45, 'Belo Horizonte'),
    ('Ana Costa', 'ana.costa@email.com', 26, 'Curitiba'),
    ('Carlos Souza', 'carlos.souza@email.com', 38, 'Porto Alegre'),
    ('Juliana Lima', 'juliana.lima@email.com', 29, 'Salvador'),
    ('Roberto Alves', 'roberto.alves@email.com', 41, 'Brasília'),
    ('Fernanda Rocha', 'fernanda.rocha@email.com', 33, 'Fortaleza'),
    ('Lucas Martins', 'lucas.martins@email.com', 24, 'Recife'),
    ('Patricia Dias', 'patricia.dias@email.com', 36, 'Manaus')
ON CONFLICT (email) DO NOTHING;

-- Inserir produtos
INSERT INTO produtos (nome, descricao, preco, estoque, categoria) VALUES
    ('Notebook Dell', 'Notebook Dell Inspiron 15, 8GB RAM, 256GB SSD', 3499.90, 15, 'Eletrônicos'),
    ('Mouse Logitech', 'Mouse sem fio Logitech M280', 89.90, 50, 'Periféricos'),
    ('Teclado Mecânico', 'Teclado mecânico RGB, switches blue', 299.90, 25, 'Periféricos'),
    ('Monitor LG 24"', 'Monitor LED 24 polegadas Full HD', 899.90, 20, 'Eletrônicos'),
    ('Webcam HD', 'Webcam Full HD 1080p com microfone', 249.90, 30, 'Periféricos'),
    ('Headset Gamer', 'Headset gamer 7.1 com LED RGB', 199.90, 35, 'Periféricos'),
    ('SSD 1TB', 'SSD NVMe M.2 1TB', 599.90, 40, 'Hardware'),
    ('Memória RAM 16GB', 'Memória DDR4 16GB 3200MHz', 399.90, 45, 'Hardware'),
    ('Cadeira Gamer', 'Cadeira gamer ergonômica reclinável', 899.90, 12, 'Móveis'),
    ('Mesa para Computador', 'Mesa em L para computador', 549.90, 8, 'Móveis')
ON CONFLICT DO NOTHING;

-- Inserir pedidos (relacionando usuários e produtos)
INSERT INTO pedidos (usuario_id, produto_id, quantidade, total, status) VALUES
    (1, 1, 1, 3499.90, 'entregue'),
    (1, 2, 2, 179.80, 'entregue'),
    (2, 3, 1, 299.90, 'em_transito'),
    (3, 4, 1, 899.90, 'processando'),
    (3, 5, 1, 249.90, 'processando'),
    (4, 6, 2, 399.80, 'entregue'),
    (5, 7, 1, 599.90, 'pendente'),
    (6, 8, 2, 799.80, 'em_transito'),
    (7, 9, 1, 899.90, 'entregue'),
    (8, 10, 1, 549.90, 'processando'),
    (9, 1, 1, 3499.90, 'cancelado'),
    (10, 2, 3, 269.70, 'entregue'),
    (1, 7, 1, 599.90, 'em_transito'),
    (2, 8, 1, 399.90, 'entregue'),
    (4, 3, 1, 299.90, 'pendente'),
    (5, 4, 1, 899.90, 'processando'),
    (6, 5, 2, 499.80, 'em_transito'),
    (7, 6, 1, 199.90, 'entregue'),
    (8, 9, 1, 899.90, 'pendente'),
    (9, 10, 1, 549.90, 'entregue')
ON CONFLICT DO NOTHING;

-- Inserir 10 pedidos aleatórios a cada execução
INSERT INTO pedidos (usuario_id, produto_id, quantidade, total, status) VALUES
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END),
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END),
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END),
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END),
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END),
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END),
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END),
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END),
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END),
    ((RANDOM() * 9 + 1)::INT, (RANDOM() * 9 + 1)::INT, (RANDOM() * 5 + 1)::INT, (RANDOM() * 3000 + 100)::DECIMAL(10,2), CASE (RANDOM() * 4)::INT WHEN 0 THEN 'entregue' WHEN 1 THEN 'em_transito' WHEN 2 THEN 'processando' WHEN 3 THEN 'pendente' ELSE 'cancelado' END);

EOF

echo "✓ Dados inseridos com sucesso!"
echo ""
echo "=========================================="
echo "Verificando dados inseridos:"
echo "=========================================="

# Mostrar estatísticas
docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" << 'EOF'

SELECT 
    'Usuários' as tabela,
    COUNT(*) as total_registros
FROM usuarios
UNION ALL
SELECT 
    'Produtos',
    COUNT(*)
FROM produtos
UNION ALL
SELECT 
    'Pedidos',
    COUNT(*)
FROM pedidos
ORDER BY tabela;

EOF

echo ""
echo "=========================================="
echo "Exemplo de consultas:"
echo "=========================================="

docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" << 'EOF'

-- Top 5 produtos mais vendidos
SELECT 
    p.nome,
    SUM(pd.quantidade) as total_vendido,
    COUNT(pd.id) as num_pedidos,
    SUM(pd.total) as receita_total
FROM produtos p
JOIN pedidos pd ON p.id = pd.produto_id
GROUP BY p.id, p.nome
ORDER BY total_vendido DESC
LIMIT 5;

EOF

echo ""
echo "=========================================="
echo "Contagem final de registros por tabela:"
echo "=========================================="

docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" << 'EOF'

SELECT 
    'usuarios' as tabela,
    COUNT(*) as quantidade
FROM usuarios
UNION ALL
SELECT 
    'produtos',
    COUNT(*)
FROM produtos
UNION ALL
SELECT 
    'pedidos',
    COUNT(*)
FROM pedidos
ORDER BY tabela;

EOF

echo ""
echo "✅ Script concluído com sucesso!"
echo ""
echo "Para conectar manualmente:"
echo "  docker exec -it $CONTAINER_NAME psql -U $DB_USER"
echo ""
echo "Ou verificar os dados:"
echo "  docker exec -it $CONTAINER_NAME psql -U $DB_USER -c 'SELECT * FROM usuarios;'"
