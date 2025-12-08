#!/bin/bash
set -e

# Script para gerenciar o cluster PostgreSQL (Primary + Replica)

COMPOSE_FILE="docker-compose.cluster.yml"
ENV_FILE=".env"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

function print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function check_env() {
    if [ ! -f "$ENV_FILE" ]; then
        print_error "Arquivo .env não encontrado!"
        print_info "Copie o arquivo .env.cluster.example para .env e configure suas credenciais S3"
        print_info "cp .env.cluster.example .env"
        exit 1
    fi
    
    # Verificar se as variáveis S3 estão configuradas
    source $ENV_FILE
    if [ -z "$S3_BUCKET" ] || [ "$S3_BUCKET" == "your-bucket-name" ]; then
        print_error "Configure as credenciais S3 no arquivo .env antes de continuar"
        exit 1
    fi
}

function start_cluster() {
    print_info "Iniciando cluster PostgreSQL (Primary + Replica)..."
    check_env
    docker compose -f $COMPOSE_FILE up -d --build
    print_info "Aguardando serviços ficarem prontos..."
    sleep 5
    docker compose -f $COMPOSE_FILE ps
}

function stop_cluster() {
    print_info "Parando cluster PostgreSQL..."
    docker compose -f $COMPOSE_FILE down
}

function restart_cluster() {
    print_info "Reiniciando cluster PostgreSQL..."
    stop_cluster
    start_cluster
}

function status_cluster() {
    print_info "Status do cluster PostgreSQL:"
    docker compose -f $COMPOSE_FILE ps
}

function logs_primary() {
    print_info "Logs do Primary:"
    docker compose -f $COMPOSE_FILE logs -f postgres-primary
}

function logs_replica() {
    print_info "Logs da Replica:"
    docker compose -f $COMPOSE_FILE logs -f postgres-replica
}

function logs_all() {
    print_info "Logs de todos os serviços:"
    docker compose -f $COMPOSE_FILE logs -f
}

function cleanup_cluster() {
    print_warning "ATENÇÃO: Isso vai remover todos os containers, volumes e dados do cluster!"
    read -p "Tem certeza? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Removendo cluster e volumes..."
        docker compose -f $COMPOSE_FILE down -v
        print_info "Cluster removido com sucesso!"
    else
        print_info "Operação cancelada."
    fi
}

function test_connections() {
    print_info "Testando conexões..."
    
    source $ENV_FILE
    
    print_info "Testando Primary (porta ${POSTGRES_PRIMARY_PORT:-5433})..."
    docker exec postgres-cluster-primary pg_isready -U ${POSTGRES_USER:-postgres} || print_error "Primary não está pronto"
    
    print_info "Testando Replica (porta ${POSTGRES_REPLICA_PORT:-5434})..."
    docker exec postgres-cluster-replica pg_isready -U ${POSTGRES_USER:-postgres} || print_error "Replica não está pronta"
    
    print_info "Verificando replicação..."
    docker exec postgres-cluster-primary psql -U ${POSTGRES_USER:-postgres} -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
}

function exec_primary() {
    docker exec -it postgres-cluster-primary bash
}

function exec_replica() {
    docker exec -it postgres-cluster-replica bash
}

function psql_primary() {
    source $ENV_FILE
    docker exec -it postgres-cluster-primary psql -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres}
}

function psql_replica() {
    source $ENV_FILE
    docker exec -it postgres-cluster-replica psql -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres}
}

function show_help() {
    cat << EOF
Uso: $0 [comando]

Comandos disponíveis:
  start           - Inicia o cluster (primary + replica)
  stop            - Para o cluster
  restart         - Reinicia o cluster
  status          - Mostra o status dos serviços
  logs-primary    - Mostra logs do primary
  logs-replica    - Mostra logs da replica
  logs            - Mostra logs de todos os serviços
  test            - Testa as conexões e replicação
  cleanup         - Remove o cluster e todos os volumes (CUIDADO!)
  exec-primary    - Abre shell no container primary
  exec-replica    - Abre shell no container replica
  psql-primary    - Conecta ao PostgreSQL no primary
  psql-replica    - Conecta ao PostgreSQL na replica
  help            - Mostra esta mensagem

Exemplos:
  $0 start        # Inicia o cluster
  $0 test         # Testa conexões e replicação
  $0 logs-primary # Visualiza logs do primary

Portas padrão:
  Primary:  5433
  Replica:  5434
  Adminer:  8081

EOF
}

# Main
case "${1:-help}" in
    start)
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    restart)
        restart_cluster
        ;;
    status)
        status_cluster
        ;;
    logs-primary)
        logs_primary
        ;;
    logs-replica)
        logs_replica
        ;;
    logs)
        logs_all
        ;;
    cleanup)
        cleanup_cluster
        ;;
    test)
        test_connections
        ;;
    exec-primary)
        exec_primary
        ;;
    exec-replica)
        exec_replica
        ;;
    psql-primary)
        psql_primary
        ;;
    psql-replica)
        psql_replica
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Comando desconhecido: $1"
        show_help
        exit 1
        ;;
esac
