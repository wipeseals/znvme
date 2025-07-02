#!/bin/bash
# Docker helper script for znvme QEMU environment
# This script provides easy Docker-based QEMU testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Docker QEMU Environment Manager for znvme

Usage: $0 <command> [options]

Commands:
    build           Build Docker image
    up              Start Docker environment
    down            Stop Docker environment
    shell           Open shell in running container
    logs            Show container logs
    test            Run tests in container
    ci              Run CI tests (no KVM)
    status          Show Docker environment status
    clean           Clean up Docker resources
    help            Show this help message

Examples:
    $0 build          # Build the Docker image
    $0 up             # Start the environment
    $0 shell          # Connect to running container
    $0 test           # Run QEMU tests in container
    $0 clean          # Clean up everything
EOF
}

build() {
    log_info "Building Docker image..."
    cd "$SCRIPT_DIR"
    docker compose build
    log_success "Docker image built successfully"
}

up() {
    log_info "Starting Docker environment..."
    cd "$SCRIPT_DIR"
    docker compose up -d
    log_success "Docker environment started"
    log_info "Connect with: $0 shell"
}

down() {
    log_info "Stopping Docker environment..."
    cd "$SCRIPT_DIR"
    docker compose down
    log_success "Docker environment stopped"
}

shell() {
    log_info "Opening shell in container..."
    cd "$SCRIPT_DIR"
    if docker compose ps | grep -q "znvme-qemu-dev.*Up"; then
        docker compose exec znvme-qemu bash
    else
        log_error "Container is not running. Start with: $0 up"
        exit 1
    fi
}

logs() {
    log_info "Showing container logs..."
    cd "$SCRIPT_DIR"
    docker compose logs -f
}

test() {
    log_info "Running tests in Docker container..."
    cd "$SCRIPT_DIR"
    docker compose run --rm znvme-qemu ./qemu-manager.sh test
}

ci() {
    log_info "Running CI tests (no KVM)..."
    cd "$SCRIPT_DIR"
    docker compose --profile ci up --abort-on-container-exit znvme-qemu-ci
}

status() {
    log_info "Docker Environment Status:"
    echo ""
    
    cd "$SCRIPT_DIR"
    
    # Check if image exists
    if docker images | grep -q "znvme-qemu"; then
        log_success "Docker image exists"
    else
        log_warning "Docker image not built (run: $0 build)"
    fi
    
    # Check running containers
    if docker compose ps | grep -q "znvme-qemu-dev"; then
        log_success "Container is running"
        docker compose ps
    else
        log_info "Container is not running"
    fi
    
    # Check volumes
    echo ""
    log_info "Docker volumes:"
    docker volume ls | grep qemu || log_info "No QEMU volumes found"
}

clean() {
    log_info "Cleaning up Docker resources..."
    cd "$SCRIPT_DIR"
    
    # Stop containers
    docker compose down
    
    # Remove images
    if docker images | grep -q "znvme-qemu"; then
        docker rmi $(docker images -q znvme-qemu) || true
    fi
    
    # Remove volumes (ask for confirmation)
    echo ""
    read -p "Remove QEMU data volumes? This will delete all QEMU disk images. (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker volume rm $(docker volume ls -q | grep qemu) || true
        log_success "Volumes removed"
    else
        log_info "Volumes preserved"
    fi
    
    log_success "Docker cleanup completed"
}

# Main command dispatcher
case "${1:-help}" in
    build)
        build
        ;;
    up)
        up
        ;;
    down)
        down
        ;;
    shell)
        shell
        ;;
    logs)
        logs
        ;;
    test)
        test
        ;;
    ci)
        ci
        ;;
    status)
        status
        ;;
    clean)
        clean
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac