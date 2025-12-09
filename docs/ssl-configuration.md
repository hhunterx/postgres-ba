# Configuração SSL com CA

## Visão Geral

PostgreSQL SSL foi adicionado para ativar conexões criptografadas entre clientes e o servidor de banco de dados. Esta implementação utiliza uma Autoridade Certificadora (CA) compartilhada que assina certificados únicos para cada servidor, válidos por 10 anos e armazenados em volumes Docker persistentes.

## Características Principais

- **Geração Automática de Certificados**: Gera automaticamente certificados assinados pela CA na primeira inicialização
- **Armazenamento Persistente**: Certificados são armazenados em volumes Docker para persistir entre reinicializações
- **Idempotente**: Certificados são gerados apenas uma vez; certificados existentes são preservados
- **Validade de 10 Anos**: Certificados válidos por 3650 dias (10 anos)
- **Configuração Automática**: PostgreSQL é automaticamente configurado para usar SSL
- **CA Compartilhada**: Certificados de múltiplos servidores são assinados pela mesma CA
- **Validação Mútua**: Servidores validam uns aos outros através da CA

## Como Funciona

1. **Script de Geração de Certificados** (`configure-ssl-with-ca.sh`):

   - Cria diretórios para CA (`/var/lib/postgresql/ca`) e SSL (`/var/lib/postgresql/ssl`)
   - Gera a CA na primeira execução (compartilhada entre servidores):
     - Chave privada da CA: `ca.key` (2048-bit RSA)
     - Certificado da CA: `ca.crt` (auto-assinado, 10 anos)
   - Para cada servidor, gera e assina seu próprio certificado:
     - Chave privada do servidor: `server.key` (2048-bit RSA)
     - Certificado do servidor: `server.crt` (assinado pela CA, 10 anos)
     - Cópia da CA: `root.crt` (para validação)
   - Define permissões corretas (600 para chaves, 644 para certificados)
   - Executa apenas como root (via root-entrypoint.sh)

2. **Configuração PostgreSQL** (`configure-postgres.sh`):

   - Adiciona configurações SSL a `postgresql.conf`:
     - `ssl = on`
     - `ssl_cert_file = '/var/lib/postgresql/ssl/server.crt'`
     - `ssl_key_file = '/var/lib/postgresql/ssl/server.key'`
     - `ssl_ca_file = '/var/lib/postgresql/ssl/root.crt'`
   - Requer SSL obrigatoriamente (sem fallback):
     - `pg_hba.conf` com `hostssl replication` apenas

3. **Integração de Inicialização** (`entrypoint.sh`):
   - Chama `configure-ssl-with-ca.sh` durante fase root de inicialização
   - Executa antes que o PostgreSQL inicie
   - Garante que certificados existem antes do PostgreSQL iniciar

## Volumes Docker

### Setup de Instância Única (`docker-compose.yml`)

```yaml
volumes:
  postgres_ca:
    driver: local
  postgres_ssl:
    driver: local
```

### Setup de Cluster (`docker-compose.cluster.yml`)

```yaml
volumes:
  postgres_cluster_ca:
    driver: local
  postgres_cluster_primary_ssl:
    driver: local
  postgres_cluster_replica_ssl:
    driver: local
```

## Detalhes dos Certificados

### Estrutura de Diretórios

```
/var/lib/postgresql/
├── ca/              # Compartilhado entre servidores
│   ├── ca.crt       # Certificado da CA
│   ├── ca.key       # Chave privada da CA
│   └── ca.srl       # Arquivo serial da CA
└── ssl/             # Único por servidor
    ├── server.crt   # Certificado do servidor (assinado pela CA)
    ├── server.key   # Chave privada do servidor
    └── root.crt     # Cópia do certificado da CA (para validação)
```

### Detalhes de Configuração

- **Localização**: `/var/lib/postgresql/` (dentro do container)
- **Algoritmo**: RSA 2048-bit
- **Validade**: 10 anos (3650 dias)
- **CA Subject**: `/C=BR/ST=State/L=City/O=Organization/CN=PostgreSQL-CA`
- **Server Subject**: `/C=BR/ST=State/L=City/O=Organization/CN=<hostname>`

## Conexão do Cliente

Para conectar com SSL obrigatório:

```bash
psql -h localhost -U postgres -d postgres --set=sslmode=require
```

### Modos SSL Disponíveis

- `disable`: SSL não é usado
- `allow`: Conecta sem SSL se possível
- `prefer`: Tenta SSL, fallback para não-SSL (não recomendado com nosso setup)
- `require`: SSL é obrigatório (padrão recomendado)
- `verify-ca`: SSL obrigatório e valida certificado contra CA
- `verify-full`: SSL obrigatório, valida CA e hostname

## Aviso de Certificado Auto-Assinado

Como o certificado raiz é auto-assinado, clientes podem precisar confiar na CA. Para desenvolvimento:

```bash
psql -h localhost -U postgres -d postgres --set=sslmode=require
# O PostgreSQL aceitará a conexão SSL
```

Para validação completa da CA em aplicações:

```bash
# Extrair o certificado da CA do servidor
docker exec postgres-ba-primary cat /var/lib/postgresql/ssl/root.crt > /tmp/ca.crt

# Usar em conexões psql
psql -h localhost -U postgres -d postgres \
  --set=sslmode=verify-ca \
  --set=sslrootcert=/tmp/ca.crt
```

## Verificação

Para verificar que o certificado está em uso:

```bash
openssl s_client -connect localhost:5432 -starttls postgres
```

Ou dentro do container:

```bash
docker exec postgres-ba-primary cat /var/lib/postgresql/ssl/server.crt

# Verificar detalhes do certificado
docker exec postgres-ba-primary openssl x509 -in /var/lib/postgresql/ssl/server.crt -text -noout
```

Para verificar que foi assinado pela CA:

```bash
docker exec postgres-ba-primary openssl verify -CAfile /var/lib/postgresql/ssl/root.crt /var/lib/postgresql/ssl/server.crt
```

## Variáveis de Ambiente

Os diretórios de certificados podem ser customizados via variáveis de ambiente:

```yaml
environment:
  # Diretório da CA (padrão: /var/lib/postgresql/ca)
  CA_DIR: /custom/ca/path

  # Diretório SSL (padrão: /var/lib/postgresql/ssl)
  SSL_CERT_DIR: /custom/ssl/path

  # Nome do servidor (padrão: hostname do container)
  SERVER_NAME: postgres-primary
```

## Replicação e SSL

Em setups de cluster, primary e replica compartilham a mesma CA, mas cada um tem seus próprios certificados únicos armazenados em volumes separados. Isso garante SSL para:

- Conexões de clientes com o primary ou replica
- Streaming de WAL entre primary e replica (com SSL obrigatório)
- Validação mútua de certificados via CA compartilhada

### Fluxo de Replicação Segura

1. **Primary** inicia e gera a CA em `postgres_cluster_ca`
2. **Primary** gera seu certificado assinado pela CA em `postgres_cluster_primary_ssl`
3. **Replica** acessa a mesma CA em `postgres_cluster_ca`
4. **Replica** gera seu certificado assinado pela mesma CA em `postgres_cluster_replica_ssl`
5. Ambos confiam na CA compartilhada
6. Streaming de WAL ocorre com SSL obrigatório

## Notas Importantes

- Certificados **NÃO** são regenerados se já existem no volume
- A CA é compartilhada entre servidores (volume `postgres_ca` ou `postgres_cluster_ca`)
- Cada servidor tem seu próprio certificado assinado pela CA
- SSL é **obrigatório** (sem fallback para conexões não-criptografadas)
- Replicação exige SSL (`hostssl replication` no `pg_hba.conf`)
- Certificados de cliente podem ser adicionados para mTLS futuro
- Para regenerar certificados, delete os volumes SSL (não delete a CA se quiser reutilizá-la)

## Recuperação e Backup

### Backup da CA (recomendado)

```bash
# Copiar CA para local seguro
docker run --rm -v postgres_ca:/ca -v ~/backups:/backup \
  alpine tar czf /backup/ca-backup.tar.gz -C /ca .
```

### Restore da CA

```bash
# Restaurar CA de backup
docker run --rm -v postgres_ca:/ca -v ~/backups:/backup \
  alpine tar xzf /backup/ca-backup.tar.gz -C /ca
```

## Troubleshooting

### Certificado expirado

Se receber erro de certificado expirado:

```bash
# Deletar volumes SSL (mas manter CA)
docker volume rm postgres_ssl

# Reiniciar container - novos certificados serão gerados
docker compose up -d --build
```

### Erro de validação de CA

Se clientes não conseguem validar a CA:

```bash
# Verificar se a CA está correto no container
docker exec postgres-ba-primary \
  openssl verify -CAfile /var/lib/postgresql/ssl/root.crt \
  /var/lib/postgresql/ssl/server.crt
```

### Replicação não conecta

Verifique que ambos compartilham a CA:

```bash
# Primary
docker exec postgres-cluster-primary cat /var/lib/postgresql/ca/ca.crt

# Replica
docker exec postgres-cluster-replica cat /var/lib/postgresql/ca/ca.crt

# Devem ser idênticos
```
